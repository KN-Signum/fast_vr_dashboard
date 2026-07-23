from __future__ import annotations

import argparse
import json
import logging
import socket
import sys
import threading
import time
import urllib.error
import urllib.request
import webbrowser
from dataclasses import replace
from pathlib import Path
from typing import Callable

import uvicorn
from fastapi import FastAPI

from config import AppSettings
from logging_setup import configure_logging
from paths import AppPaths


logger = logging.getLogger(__name__)
CreateApp = Callable[[AppSettings], FastAPI]


def _dashboard_url(port: int) -> str:
    return f"http://127.0.0.1:{port}"


def _health_url(port: int) -> str:
    return f"{_dashboard_url(port)}/api/health"


def _existing_panel_vr(port: int, timeout: float = 0.5) -> bool:
    try:
        with urllib.request.urlopen(_health_url(port), timeout=timeout) as response:
            payload = json.load(response)
        return payload.get("application") == "panel-vr"
    except (OSError, ValueError, urllib.error.URLError):
        return False


def _port_available(port: int) -> bool:
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
            if sys.platform == "win32":
                probe.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
            probe.bind(("127.0.0.1", port))
        return True
    except OSError:
        return False


def _show_error(title: str, message: str) -> None:
    logger.error("%s: %s", title, message)
    if sys.platform == "win32":
        try:
            import ctypes

            ctypes.windll.user32.MessageBoxW(0, message, title, 0x10)
            return
        except Exception:
            logger.exception("Could not display the Windows error dialog")
    if sys.stderr is not None:
        print(f"{title}: {message}", file=sys.stderr)


def _open_browser_when_ready(
    port: int,
    *,
    timeout_seconds: float = 30.0,
) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        if _existing_panel_vr(port):
            webbrowser.open(_dashboard_url(port))
            return
        time.sleep(0.25)
    _show_error(
        "Panel VR",
        "Serwer nie uruchomil sie w oczekiwanym czasie. Sprawdz plik logu.",
    )


def _parse_args(argv: list[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Panel VR backend launcher")
    parser.add_argument("--port", type=int, help="HTTP and WebSocket port")
    parser.add_argument("--data-dir", type=Path, help="Writable application directory")
    parser.add_argument("--eeg-device", help="BrainAccess Bluetooth device name")
    parser.add_argument(
        "--mock-eeg",
        action="store_true",
        help="Use generated EEG data instead of a physical sensor",
    )
    parser.add_argument(
        "--mock-et",
        action="store_true",
        help="Use generated eye-tracking data instead of VR data",
    )
    parser.add_argument(
        "--no-browser",
        action="store_true",
        help="Do not open the dashboard automatically",
    )
    return parser.parse_args(argv)


def run(
    create_app: CreateApp | None = None,
    argv: list[str] | None = None,
) -> int:
    args = _parse_args(argv)
    try:
        settings = AppSettings.from_env(default_environment="production")
        settings = replace(
            settings,
            port=args.port if args.port is not None else settings.port,
            data_dir=args.data_dir if args.data_dir is not None else settings.data_dir,
            eeg_mode="mock" if args.mock_eeg else settings.eeg_mode,
            eeg_device_name=(
                args.eeg_device
                if args.eeg_device is not None
                else settings.eeg_device_name
            ),
            et_mode="mock" if args.mock_et else settings.et_mode,
            open_browser=False if args.no_browser else settings.open_browser,
        )
        if not 1 <= settings.port <= 65535:
            raise ValueError("Port must be between 1 and 65535")
    except ValueError as error:
        _show_error("Nieprawidlowa konfiguracja", str(error))
        return 2

    paths = AppPaths.from_settings(settings)
    try:
        configure_logging(paths, settings.log_level)
    except OSError as error:
        _show_error("Blad zapisu", f"Nie mozna utworzyc katalogu danych: {error}")
        return 3

    if _existing_panel_vr(settings.port):
        logger.info("Panel VR is already running on port %d", settings.port)
        if settings.open_browser:
            webbrowser.open(_dashboard_url(settings.port))
        return 0

    if not _port_available(settings.port):
        _show_error(
            "Port jest zajety",
            f"Port {settings.port} jest uzywany przez inny program.",
        )
        return 4

    if create_app is None:
        from main import create_app as app_factory
    else:
        app_factory = create_app

    try:
        app = app_factory(settings)
    except Exception as error:
        logger.exception("Could not create the Panel VR application")
        _show_error("Blad uruchamiania", str(error))
        return 5

    if settings.open_browser:
        threading.Thread(
            target=_open_browser_when_ready,
            args=(settings.port,),
            daemon=True,
            name="panel-vr-browser",
        ).start()

    logger.info(
        "Starting Panel VR %s on %s:%d",
        settings.app_version,
        settings.host,
        settings.port,
    )
    try:
        uvicorn.run(
            app,
            host=settings.host,
            port=settings.port,
            log_config=None,
        )
    except Exception as error:
        logger.exception("Panel VR server stopped with an error")
        _show_error("Blad serwera", str(error))
        return 6
    return 0


def main() -> int:
    return run()


if __name__ == "__main__":
    raise SystemExit(main())
