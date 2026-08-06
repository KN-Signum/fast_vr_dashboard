from __future__ import annotations

from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import quote
from urllib.request import Request, urlopen


class SupabaseUploadError(RuntimeError):
    pass


def upload_zip(
    archive: Path,
    *,
    filename: str,
    supabase_url: str,
    service_role_key: str,
    bucket: str,
) -> None:
    object_url = (
        f"{supabase_url.rstrip('/')}/storage/v1/object/"
        f"{quote(bucket, safe='')}/{quote(filename, safe='')}"
    )
    request = Request(
        object_url,
        data=archive.read_bytes(),
        method="POST",
        headers={
            "Authorization": f"Bearer {service_role_key}",
            "apikey": service_role_key,
            "Content-Type": "application/zip",
            "x-upsert": "true",
        },
    )
    try:
        with urlopen(request, timeout=120) as response:
            if response.status < 200 or response.status >= 300:
                raise SupabaseUploadError(
                    f"Supabase zwrócił status {response.status}"
                )
    except HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace").strip()
        message = f"Supabase zwrócił status {error.code}"
        if detail:
            message = f"{message}: {detail}"
        raise SupabaseUploadError(message) from error
    except URLError as error:
        raise SupabaseUploadError(f"Nie można połączyć się z Supabase: {error.reason}") from error
