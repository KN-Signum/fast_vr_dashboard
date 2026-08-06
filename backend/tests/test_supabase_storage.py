from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

from supabase_storage import upload_zip


class SupabaseStorageTests(unittest.TestCase):
    def test_upload_zip_posts_archive_to_private_storage_api(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            archive = Path(temporary_directory) / "raw data.zip"
            archive.write_bytes(b"zip-content")
            response = MagicMock()
            response.status = 200
            response.__enter__.return_value = response

            with patch("supabase_storage.urlopen", return_value=response) as open_url:
                upload_zip(
                    archive,
                    filename="raw data.zip",
                    supabase_url="https://example.supabase.co/",
                    service_role_key="secret-key",
                    bucket="raw sessions",
                )

            request = open_url.call_args.args[0]
            self.assertEqual(
                request.full_url,
                "https://example.supabase.co/storage/v1/object/"
                "raw%20sessions/raw%20data.zip",
            )
            self.assertEqual(request.method, "POST")
            self.assertEqual(request.data, b"zip-content")
            self.assertEqual(request.get_header("Authorization"), "Bearer secret-key")
            self.assertEqual(request.get_header("Content-type"), "application/zip")
            self.assertEqual(request.get_header("X-upsert"), "true")


if __name__ == "__main__":
    unittest.main()
