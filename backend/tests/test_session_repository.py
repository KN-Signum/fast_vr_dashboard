from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from session_repository import (
    ActiveSessionExistsError,
    SessionRepository,
)


class SessionRepositoryTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.repository = SessionRepository(
            self.root / "sessions.sqlite3",
            self.root / "sessions",
        )
        self.repository.initialize()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_records_and_exports_a_complete_session(self) -> None:
        created = self.repository.create_session(
            patient_id="patient-001",
            preferred_hand="right",
            notes="Baseline",
        )
        session_id = created["session_id"]
        self.repository.append_records(
            session_id,
            [
                (
                    "eeg_records",
                    {
                        "received_at": "2026-01-01T00:00:01Z",
                        "payload": {"type": "eeg_data", "sequence": 0},
                    },
                ),
                (
                    "eye_tracking_records",
                    {
                        "received_at": "2026-01-01T00:00:02Z",
                        "payload": {"type": "eye_tracking"},
                    },
                ),
                (
                    "vr_events",
                    {
                        "received_at": "2026-01-01T00:00:03Z",
                        "payload": {"type": "scene_state"},
                    },
                ),
                (
                    "vr_frames",
                    {
                        "received_at": "2026-01-01T00:00:04Z",
                        "byte_length": 1024,
                    },
                ),
            ],
        )
        event = self.repository.add_event(
            session_id,
            label="Przerwa",
            category="support",
            note="Pacjent poprosił o przerwę",
        )
        summary = self.repository.end_session(session_id)

        self.assertEqual(summary["status"], "completed")
        self.assertEqual(summary["counts"]["eeg_records"], 1)
        self.assertEqual(summary["counts"]["eye_tracking_records"], 1)
        self.assertEqual(summary["counts"]["vr_events"], 1)
        self.assertEqual(summary["counts"]["vr_frames"], 1)
        self.assertEqual(summary["counts"]["session_events"], 1)
        self.assertEqual(summary["session_events"][0]["id"], event["id"])

        archive = self.repository.create_raw_archive(
            session_id,
            self.root / "exports",
        )
        with zipfile.ZipFile(archive) as raw_data:
            self.assertEqual(
                set(raw_data.namelist()),
                {
                    "session.json",
                    "eeg.ndjson",
                    "eye_tracking.ndjson",
                    "vr_events.ndjson",
                    "vr_frames.ndjson",
                    "session_events.ndjson",
                },
            )
            exported_summary = json.loads(raw_data.read("session.json"))
            self.assertEqual(exported_summary["session_id"], session_id)
            exported_events = [
                json.loads(line)
                for line in raw_data.read("session_events.ndjson")
                .decode("utf-8")
                .splitlines()
            ]
            self.assertEqual(exported_events, [event])

    def test_only_one_session_can_be_active(self) -> None:
        self.repository.create_session(
            patient_id="patient-001",
            preferred_hand="left",
            notes="",
        )

        with self.assertRaises(ActiveSessionExistsError):
            self.repository.create_session(
                patient_id="patient-002",
                preferred_hand="right",
                notes="",
            )

    def test_active_session_is_marked_interrupted_during_recovery(self) -> None:
        created = self.repository.create_session(
            patient_id="patient-001",
            preferred_hand="not_specified",
            notes="",
        )
        eeg_path = (
            self.repository.session_directory(created["session_id"]) / "eeg.ndjson"
        )
        eeg_path.write_text(
            '{"received_at":"2026-01-01T00:00:00Z","payload":{}}\n',
            encoding="utf-8",
        )

        recovered = self.repository.recover_active_sessions()
        summary = self.repository.summary(created["session_id"])

        self.assertEqual(recovered, [created["session_id"]])
        self.assertEqual(summary["status"], "interrupted")
        self.assertIsNotNone(summary["ended_at"])
        self.assertEqual(summary["counts"]["eeg_records"], 1)
        recovered_summary = self.repository.take_recovered_session()
        self.assertEqual(recovered_summary["session_id"], created["session_id"])
        self.assertIsNone(self.repository.take_recovered_session())


if __name__ == "__main__":
    unittest.main()
