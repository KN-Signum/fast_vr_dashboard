from __future__ import annotations

import json
import sqlite3
import tempfile
import unittest
import zipfile
from pathlib import Path

from session_repository import (
    ActiveSessionExistsError,
    SessionRepository,
    SessionStateError,
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
            eeg_enabled_at_start=False,
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
        with self.assertRaises(SessionStateError):
            self.repository.update_post_session_notes(
                session_id,
                "Nie można jeszcze zapisać",
            )
        summary = self.repository.end_session(session_id)
        summary = self.repository.update_post_session_notes(
            session_id,
            "Pacjent zgłosił lekkie zmęczenie.",
        )

        self.assertEqual(summary["status"], "completed")
        self.assertFalse(summary["eeg_enabled_at_start"])
        self.assertEqual(summary["counts"]["eeg_records"], 1)
        self.assertEqual(summary["counts"]["eye_tracking_records"], 1)
        self.assertEqual(summary["counts"]["vr_events"], 1)
        self.assertEqual(summary["counts"]["vr_frames"], 1)
        self.assertEqual(summary["counts"]["session_events"], 1)
        self.assertEqual(summary["session_events"][0]["id"], event["id"])
        self.assertEqual(
            summary["post_session_notes"],
            "Pacjent zgłosił lekkie zmęczenie.",
        )

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
            self.assertFalse(exported_summary["eeg_enabled_at_start"])
            self.assertEqual(
                exported_summary["post_session_notes"],
                "Pacjent zgłosił lekkie zmęczenie.",
            )
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

    def test_adds_post_session_notes_column_to_existing_database(self) -> None:
        database_path = self.root / "legacy.sqlite3"
        connection = sqlite3.connect(database_path)
        try:
            connection.execute(
                """
                CREATE TABLE sessions (
                    id TEXT PRIMARY KEY,
                    status TEXT NOT NULL,
                    recovery_pending INTEGER NOT NULL DEFAULT 0,
                    eeg_enabled_at_start INTEGER NOT NULL DEFAULT 1
                )
                """
            )
            connection.commit()
        finally:
            connection.close()

        repository = SessionRepository(database_path, self.root / "legacy-sessions")
        repository.initialize()

        connection = sqlite3.connect(database_path)
        try:
            columns = {
                row[1]
                for row in connection.execute("PRAGMA table_info(sessions)").fetchall()
            }
        finally:
            connection.close()
        self.assertIn("post_session_notes", columns)

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
