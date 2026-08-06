from __future__ import annotations

import re


_UNSAFE_FILENAME_PART = re.compile(r"[^A-Za-z0-9._-]+")


def safe_filename_part(value: str, *, fallback: str) -> str:
    sanitized = _UNSAFE_FILENAME_PART.sub("_", value.strip())
    sanitized = sanitized.strip("._-")
    return sanitized or fallback
