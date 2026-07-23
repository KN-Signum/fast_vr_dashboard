from __future__ import annotations

import asyncio
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from config import AppSettings
from main import create_app


def _settings(
    static_dir: Path,
    *,
    environment: str = "test",
    eeg_mode: str = "off",
    et_mode: str = "off",
) -> AppSettings:
    return AppSettings.from_env(
        environ={
            "VRDASH_ENV": environment,
            "VRDASH_EEG_MODE": eeg_mode,
            "VRDASH_ET_MODE": et_mode,
            "VRDASH_BEACON_ENABLED": "false",
            "VRDASH_STATIC_DIR": str(static_dir),
        }
    )


def _health_endpoint(app):
    return next(
        route.endpoint
        for route in app.routes
        if getattr(route, "path", None) == "/api/health"
    )


class AppFactoryTests(unittest.IsolatedAsyncioTestCase):
    async def test_health_reports_runtime_configuration(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            static_dir = Path(temporary_directory)
            (static_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            app = create_app(_settings(static_dir))

            async with app.router.lifespan_context(app):
                health = await _health_endpoint(app)()

            self.assertEqual(health["status"], "ok")
            self.assertEqual(health["application"], "panel-vr")
            self.assertEqual(health["eeg_status"], "disabled")
            self.assertEqual(health["et_status"], "disabled")
            self.assertFalse(health["beacon_running"])

    async def test_production_et_waits_for_vr_without_starting_mock(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            static_dir = Path(temporary_directory)
            (static_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            settings = _settings(
                static_dir,
                environment="production",
                eeg_mode="off",
                et_mode="vr",
            )

            with patch("main._load_et_runner") as load_et_runner:
                app = create_app(settings)
                async with app.router.lifespan_context(app):
                    health = await _health_endpoint(app)()

            load_et_runner.assert_called_once_with("vr")
            self.assertEqual(health["et_status"], "awaiting_vr")

    async def test_mock_streams_are_started_and_cancelled(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            static_dir = Path(temporary_directory)
            (static_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            settings = _settings(
                static_dir,
                eeg_mode="mock",
                et_mode="mock",
            )
            started: set[str] = set()

            async def eeg_runner(_):
                started.add("eeg")
                await asyncio.Event().wait()

            async def et_runner(_):
                started.add("et")
                await asyncio.Event().wait()

            with (
                patch("main._load_eeg_runner", return_value=eeg_runner),
                patch("main._load_et_runner", return_value=et_runner),
            ):
                app = create_app(settings)
                async with app.router.lifespan_context(app):
                    await asyncio.sleep(0)
                    health = await _health_endpoint(app)()
                    self.assertEqual(started, {"eeg", "et"})
                    self.assertEqual(health["eeg_status"], "running")
                    self.assertEqual(health["et_status"], "running")

                self.assertEqual(app.state.runtime.tasks, [])
                self.assertEqual(app.state.runtime.eeg_status, "stopped")
                self.assertEqual(app.state.runtime.et_status, "stopped")

    def test_missing_flutter_build_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            settings = _settings(Path(temporary_directory))

            with self.assertRaisesRegex(
                RuntimeError,
                "Nie znaleziono aplikacji Flutter Web",
            ):
                create_app(settings)


if __name__ == "__main__":
    unittest.main()
