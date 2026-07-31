from __future__ import annotations

import re
import unittest
from datetime import UTC, datetime

from session_report import build_session_report


class SessionReportTests(unittest.TestCase):
    def test_builds_pdf_with_polish_text_and_multiple_event_pages(self) -> None:
        events = [
            {
                "id": str(index),
                "label": f"Zdarzenie {index}: dyskomfort i nudności",
                "category": "patient_behavior",
                "note": "Pacjent zgłosił potrzebę krótkiej przerwy & obserwacji <test>.",
                "occurred_at": "2026-07-31T08:01:00Z",
                "elapsed_ms": index * 15_000,
                "source": "dashboard",
            }
            for index in range(60)
        ]
        summary = {
            "session_id": "session-001",
            "patient_id": "pacjent-Żółć",
            "preferred_hand": "right",
            "notes": "Zażółć gęślą jaźń\nDruga linia notatki.",
            "status": "completed",
            "started_at": "2026-07-31T08:00:00Z",
            "ended_at": "2026-07-31T08:15:00Z",
            "duration_seconds": 900,
            "counts": {
                "eeg_records": 1000,
                "eye_tracking_records": 2000,
                "vr_events": 12,
                "vr_frames": 3000,
                "session_events": len(events),
            },
            "dropped_records": 0,
            "session_events": events,
        }

        report = build_session_report(
            summary,
            app_version="0.1.2",
            generated_at=datetime(2026, 7, 31, 10, 0, tzinfo=UTC),
        )

        self.assertTrue(report.startswith(b"%PDF-"))
        self.assertIn(b"%%EOF", report)
        self.assertGreater(len(report), 50_000)
        self.assertGreaterEqual(len(re.findall(rb"/Type\s*/Page(?!s)", report)), 2)

    def test_builds_pdf_without_notes_or_events(self) -> None:
        summary = {
            "session_id": "session-002",
            "patient_id": "patient-002",
            "preferred_hand": "not_specified",
            "notes": "",
            "status": "interrupted",
            "started_at": "2026-07-31T08:00:00Z",
            "ended_at": None,
            "duration_seconds": 5.5,
            "counts": {},
            "dropped_records": 3,
            "session_events": [],
        }

        report = build_session_report(summary, app_version="0.1.2")

        self.assertTrue(report.startswith(b"%PDF-"))
        self.assertIn(b"%%EOF", report)


if __name__ == "__main__":
    unittest.main()
