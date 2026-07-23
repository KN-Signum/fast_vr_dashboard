from __future__ import annotations

import logging
import tempfile
import unittest
from pathlib import Path

from config import AppSettings
from logging_setup import configure_logging
from paths import AppPaths


class LoggingSetupTests(unittest.TestCase):
    def tearDown(self) -> None:
        root_logger = logging.getLogger()
        for handler in list(root_logger.handlers):
            if getattr(handler, "_panel_vr_handler", False):
                root_logger.removeHandler(handler)
                handler.close()

    def test_configure_logging_writes_to_application_data(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            settings = AppSettings.from_env(
                environ={"VRDASH_DATA_DIR": temporary_directory}
            )
            paths = AppPaths.from_settings(settings)

            configure_logging(paths, "INFO")
            logging.getLogger("test").info("runtime foundation test")
            for handler in logging.getLogger().handlers:
                handler.flush()

            log_file = Path(temporary_directory) / "logs" / "panel-vr.log"
            self.assertTrue(log_file.is_file())
            self.assertIn(
                "runtime foundation test",
                log_file.read_text(encoding="utf-8"),
            )


if __name__ == "__main__":
    unittest.main()
