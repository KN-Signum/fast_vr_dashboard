from __future__ import annotations

import logging
from logging.handlers import RotatingFileHandler

from paths import AppPaths


_HANDLER_MARKER = "_panel_vr_handler"


def configure_logging(paths: AppPaths, level: str) -> None:
    paths.ensure_writable_directories()
    root_logger = logging.getLogger()
    numeric_level = getattr(logging, level.upper())
    root_logger.setLevel(numeric_level)

    for handler in list(root_logger.handlers):
        if getattr(handler, _HANDLER_MARKER, False):
            root_logger.removeHandler(handler)
            handler.close()

    formatter = logging.Formatter(
        "%(asctime)s %(levelname)s %(name)s: %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
    )

    console_handler = logging.StreamHandler()
    console_handler.setLevel(numeric_level)
    console_handler.setFormatter(formatter)
    setattr(console_handler, _HANDLER_MARKER, True)

    file_handler = RotatingFileHandler(
        paths.log_dir / "panel-vr.log",
        maxBytes=5 * 1024 * 1024,
        backupCount=5,
        encoding="utf-8",
    )
    file_handler.setLevel(numeric_level)
    file_handler.setFormatter(formatter)
    setattr(file_handler, _HANDLER_MARKER, True)

    root_logger.addHandler(console_handler)
    root_logger.addHandler(file_handler)
    logging.captureWarnings(True)
