from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from session_repository import SessionRepository
from session_service import SessionService


class SessionServiceTests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.service = SessionService(
            SessionRepository(root / "sessions.sqlite3", root / "sessions"),
            export_dir=root / "exports",
        )
        await self.service.start()

    async def asyncTearDown(self) -> None:
        await self.service.stop()
        self.temporary_directory.cleanup()

    async def test_records_server_and_vr_data_but_not_dashboard_commands(self) -> None:
        created = await self.service.create_session(
            patient_id="patient-001",
            preferred_hand="left",
            notes="",
            eeg_enabled_at_start=False,
        )
        session_id = created["session_id"]

        self.service.record_json(
            {"type": "eeg_data", "sequence": 0},
            sender_role=None,
        )
        self.service.record_json(
            {"type": "eye_tracking", "gaze_screen_x": 0.5},
            sender_role="vr",
        )
        self.service.record_json(
            {"type": "scene_state", "scene": "forest"},
            sender_role="vr",
        )
        self.service.record_json(
            {"type": "state_update", "current_view": "painting"},
            sender_role="vr_simulator",
        )
        self.service.record_json(
            {"type": "command", "action": "pause"},
            sender_role="dashboard",
        )
        self.service.record_json(
            {
                "type": "bird_observation",
                "side": "left",
                "delta": 1,
                "reported_left": 1,
                "reported_right": 0,
            },
            sender_role="dashboard",
        )
        self.service.record_binary(b"\xff\xd8frame", sender_role="vr")
        await self.service.add_event(
            session_id,
            label="Utrata koncentracji",
            category="patient_behavior",
            note="",
        )

        summary = await self.service.end_session(session_id)

        self.assertEqual(summary["counts"]["eeg_records"], 1)
        self.assertEqual(summary["counts"]["eye_tracking_records"], 1)
        self.assertEqual(summary["counts"]["vr_events"], 3)
        self.assertEqual(summary["counts"]["vr_frames"], 1)
        self.assertEqual(summary["counts"]["session_events"], 1)
        self.assertFalse(summary["eeg_enabled_at_start"])
        self.assertIsNone(self.service.active_session_id)

        records_path = (
            self.service.repository.session_directory(session_id)
            / "vr_events.ndjson"
        )
        records = [
            json.loads(line)
            for line in records_path.read_text(encoding="utf-8").splitlines()
        ]
        simulated = next(record for record in records if record.get("simulated"))
        self.assertEqual(simulated["source_role"], "vr_simulator")
        self.assertEqual(simulated["payload"]["current_view"], "painting")
        observation = next(
            record
            for record in records
            if record["payload"].get("type") == "bird_observation"
        )
        self.assertEqual(observation["source_role"], "dashboard")
        self.assertEqual(observation["payload"]["side"], "left")


if __name__ == "__main__":
    unittest.main()
