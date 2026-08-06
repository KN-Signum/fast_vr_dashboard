from __future__ import annotations

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from launcher import _load_environment_file


class LauncherEnvironmentTests(unittest.TestCase):
    def test_loads_env_file_without_overriding_process_environment(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            env_file = Path(temporary_directory) / ".env"
            env_file.write_text(
                "# Supabase\n"
                "VRDASH_SUPABASE_URL=https://example.supabase.co\n"
                "VRDASH_SUPABASE_BUCKET='file-bucket'\n",
                encoding="utf-8",
            )
            with patch.dict(
                os.environ,
                {"VRDASH_SUPABASE_BUCKET": "environment-bucket"},
                clear=True,
            ):
                _load_environment_file(env_file)

                self.assertEqual(
                    os.environ["VRDASH_SUPABASE_URL"],
                    "https://example.supabase.co",
                )
                self.assertEqual(
                    os.environ["VRDASH_SUPABASE_BUCKET"],
                    "environment-bucket",
                )


if __name__ == "__main__":
    unittest.main()
