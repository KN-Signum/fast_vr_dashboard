from __future__ import annotations

import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping

from config import AppSettings


APP_AUTHOR = "NEXT"
APP_NAME = "PanelVR"


def resource_root(anchor_file: str | Path | None = None) -> Path:
    anchor = Path(__file__ if anchor_file is None else anchor_file)
    return anchor.resolve().parent


def default_data_dir(
    *,
    platform: str | None = None,
    environ: Mapping[str, str] | None = None,
    home: Path | None = None,
) -> Path:
    current_platform = sys.platform if platform is None else platform
    env = os.environ if environ is None else environ
    home_dir = Path.home() if home is None else home

    if current_platform == "win32":
        local_app_data = env.get("LOCALAPPDATA")
        base = Path(local_app_data) if local_app_data else home_dir / "AppData" / "Local"
        return base / APP_AUTHOR / APP_NAME

    if current_platform == "darwin":
        return home_dir / "Library" / "Application Support" / APP_AUTHOR / APP_NAME

    xdg_data_home = env.get("XDG_DATA_HOME")
    base = Path(xdg_data_home) if xdg_data_home else home_dir / ".local" / "share"
    return base / APP_AUTHOR.lower() / APP_NAME.lower()


@dataclass(frozen=True, slots=True)
class AppPaths:
    resource_dir: Path
    static_dir: Path
    data_dir: Path
    log_dir: Path
    session_dir: Path
    session_database: Path
    export_dir: Path

    @classmethod
    def from_settings(cls, settings: AppSettings) -> AppPaths:
        resources = resource_root()
        data = (
            settings.data_dir.expanduser().resolve()
            if settings.data_dir is not None
            else default_data_dir()
        )
        static = (
            settings.static_dir.expanduser().resolve()
            if settings.static_dir is not None
            else resources / "static" / "web"
        )
        return cls(
            resource_dir=resources,
            static_dir=static,
            data_dir=data,
            log_dir=data / "logs",
            session_dir=data / "sessions",
            session_database=data / "sessions.sqlite3",
            export_dir=data / "exports",
        )

    def ensure_writable_directories(self) -> None:
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.export_dir.mkdir(parents=True, exist_ok=True)
