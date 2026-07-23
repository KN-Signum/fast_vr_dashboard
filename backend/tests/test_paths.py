from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from config import AppSettings
from paths import AppPaths, default_data_dir, resource_root


class AppPathsTests(unittest.TestCase):
    def test_default_data_directory_is_platform_specific(self) -> None:
        home = Path("/users/tester")

        self.assertEqual(
            default_data_dir(
                platform="win32",
                environ={"LOCALAPPDATA": "C:/LocalData"},
                home=home,
            ),
            Path("C:/LocalData/NEXT/PanelVR"),
        )
        self.assertEqual(
            default_data_dir(platform="darwin", environ={}, home=home),
            home / "Library/Application Support/NEXT/PanelVR",
        )
        self.assertEqual(
            default_data_dir(platform="linux", environ={}, home=home),
            home / ".local/share/next/panelvr",
        )

    def test_resource_root_uses_the_entry_file_directory(self) -> None:
        self.assertEqual(
            resource_root("/tmp/_MEI12345/main.py"),
            Path("/tmp/_MEI12345").resolve(),
        )

    def test_explicit_paths_and_writable_directories(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            base = Path(temporary_directory)
            static_dir = base / "web"
            data_dir = base / "data"
            settings = AppSettings.from_env(
                environ={
                    "VRDASH_DATA_DIR": str(data_dir),
                    "VRDASH_STATIC_DIR": str(static_dir),
                }
            )

            paths = AppPaths.from_settings(settings)
            paths.ensure_writable_directories()

            self.assertEqual(paths.static_dir, static_dir.resolve())
            self.assertTrue(paths.log_dir.is_dir())
            self.assertTrue(paths.session_dir.is_dir())


if __name__ == "__main__":
    unittest.main()
