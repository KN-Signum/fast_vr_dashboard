from __future__ import annotations

import asyncio
import io
import json
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

from fastapi.testclient import TestClient

from config import AppSettings
from eeg_service import EegStatus
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
            "VRDASH_DATA_DIR": str(static_dir / "data"),
        }
    )


def _health_endpoint(app):
    return next(
        route.endpoint
        for route in app.routes
        if getattr(route, "path", None) == "/api/health"
    )


class FakeEegService:
    def __init__(self, started: set[str]) -> None:
        self.enabled = True
        self.status = EegStatus.DISCONNECTED
        self.error = None
        self._started = started

    async def start(self, _manager) -> None:
        self._started.add("eeg")
        self.status = EegStatus.STREAMING

    async def stop(self) -> None:
        self.status = EegStatus.DISCONNECTED

    async def start_erd_baseline(self) -> None:
        return

    async def set_enabled(self, enabled, manager) -> None:
        self.enabled = enabled
        if enabled:
            await self.start(manager)
        else:
            self.status = EegStatus.DISABLED


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
            self.assertEqual(health["eeg_device_name"], "BA MINI 037")
            self.assertFalse(health["eeg_enabled"])
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

            async def et_runner(_):
                started.add("et")
                await asyncio.Event().wait()

            with (
                patch(
                    "main.create_eeg_service",
                    return_value=FakeEegService(started),
                ),
                patch("main._load_et_runner", return_value=et_runner),
            ):
                app = create_app(settings)
                async with app.router.lifespan_context(app):
                    await asyncio.sleep(0)
                    health = await _health_endpoint(app)()
                    self.assertEqual(started, {"eeg", "et"})
                    self.assertEqual(health["eeg_status"], "streaming")
                    self.assertEqual(health["et_status"], "running")

                self.assertEqual(app.state.runtime.tasks, [])
                self.assertEqual(
                    app.state.eeg_service.status,
                    EegStatus.DISCONNECTED,
                )
                self.assertEqual(app.state.runtime.et_status, "stopped")

    def test_missing_flutter_build_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            settings = _settings(Path(temporary_directory))

            with self.assertRaisesRegex(
                RuntimeError,
                "Nie znaleziono aplikacji Flutter Web",
            ):
                create_app(settings)


class SessionApiTests(unittest.TestCase):
    def test_eeg_can_be_disabled_before_session_and_enabled_after_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            static_dir = Path(temporary_directory)
            (static_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            app = create_app(_settings(static_dir, eeg_mode="mock"))

            with TestClient(app) as client:
                health = client.get("/api/health").json()
                self.assertTrue(health["eeg_enabled"])

                disabled = client.put("/api/eeg", json={"enabled": False})
                self.assertEqual(disabled.status_code, 200)
                self.assertFalse(disabled.json()["eeg_enabled"])
                self.assertEqual(disabled.json()["eeg_status"], "disabled")

                created = client.post(
                    "/api/sessions",
                    json={
                        "patient_id": "patient-no-eeg",
                        "preferred_hand": "not_specified",
                        "notes": "",
                    },
                )
                self.assertEqual(created.status_code, 201)
                self.assertFalse(created.json()["eeg_enabled_at_start"])
                session_id = created.json()["session_id"]

                blocked = client.put("/api/eeg", json={"enabled": True})
                self.assertEqual(blocked.status_code, 409)

                client.post(f"/api/sessions/{session_id}/end")
                enabled = client.put("/api/eeg", json={"enabled": True})
                self.assertEqual(enabled.status_code, 200)
                self.assertTrue(enabled.json()["eeg_enabled"])

    def test_session_lifecycle_records_websocket_data_and_downloads_raw_zip(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            static_dir = Path(temporary_directory)
            (static_dir / "index.html").write_text("<html></html>", encoding="utf-8")
            app = create_app(_settings(static_dir))

            with TestClient(app) as client:
                created_response = client.post(
                    "/api/sessions",
                    json={
                        "patient_id": "patient-001",
                        "preferred_hand": "left",
                        "notes": "API test",
                    },
                )
                self.assertEqual(created_response.status_code, 201)
                session_id = created_response.json()["session_id"]

                with client.websocket_connect("/ws?role=vr") as websocket:
                    websocket.send_json({"type": "eeg_data", "sequence": 0})
                    websocket.send_json(
                        {
                            "type": "eye_tracking",
                            "gaze_screen_x": 0.5,
                            "gaze_screen_y": 0.75,
                        }
                    )
                    websocket.send_json({"type": "scene_state", "scene": "forest"})
                    websocket.send_bytes(b"\xff\xd8frame")

                with client.websocket_connect("/ws?role=dashboard") as websocket:
                    websocket.send_json({"type": "command", "action": "pause"})

                event_response = client.post(
                    f"/api/sessions/{session_id}/events",
                    json={
                        "label": "Przerwa",
                        "category": "support",
                        "note": "",
                    },
                )
                self.assertEqual(event_response.status_code, 201)

                active_notes_response = client.put(
                    f"/api/sessions/{session_id}/post-session-notes",
                    json={"notes": "Too early"},
                )
                self.assertEqual(active_notes_response.status_code, 409)

                ended_response = client.post(f"/api/sessions/{session_id}/end")
                self.assertEqual(ended_response.status_code, 200)
                summary = ended_response.json()
                self.assertEqual(summary["status"], "completed")
                self.assertFalse(summary["eeg_enabled_at_start"])
                self.assertEqual(summary["counts"]["eeg_records"], 1)
                self.assertEqual(summary["counts"]["eye_tracking_records"], 1)
                self.assertEqual(summary["counts"]["vr_events"], 1)
                self.assertEqual(summary["counts"]["vr_frames"], 1)
                self.assertEqual(summary["counts"]["session_events"], 1)
                self.assertEqual(
                    summary["eye_tracking_analysis"]["valid_points"],
                    1,
                )

                notes_response = client.put(
                    f"/api/sessions/{session_id}/post-session-notes",
                    json={"notes": "  Pacjent czuł się dobrze.  "},
                )
                self.assertEqual(notes_response.status_code, 200)
                summary = notes_response.json()
                self.assertEqual(
                    summary["post_session_notes"],
                    "Pacjent czuł się dobrze.",
                )

                report_response = client.get(
                    f"/api/sessions/{session_id}/download/summary"
                )
                self.assertEqual(report_response.status_code, 200)
                self.assertEqual(
                    report_response.headers["content-type"], "application/pdf"
                )
                self.assertIn(
                    f'filename="raport_sesji_{session_id}.pdf"',
                    report_response.headers["content-disposition"],
                )
                self.assertTrue(report_response.content.startswith(b"%PDF-"))

                raw_response = client.get(
                    f"/api/sessions/{session_id}/download/raw"
                )
                self.assertEqual(raw_response.status_code, 200)
                self.assertEqual(raw_response.headers["content-type"], "application/zip")
                with zipfile.ZipFile(io.BytesIO(raw_response.content)) as archive:
                    self.assertIn("eeg.ndjson", archive.namelist())
                    self.assertIn("session.json", archive.namelist())
                    exported_summary = json.loads(archive.read("session.json"))
                    self.assertEqual(
                        exported_summary["post_session_notes"],
                        "Pacjent czuł się dobrze.",
                    )


if __name__ == "__main__":
    unittest.main()
