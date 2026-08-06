from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from bird_count_analysis import analyze_bird_counts


class BirdCountAnalysisTests(unittest.TestCase):
    def test_returns_latest_generated_and_reported_bird_counts(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "vr_events.ndjson"
            records = [
                {"payload": {"type": "bird_count", "visible": 8, "left": 4, "right": 4}},
                {
                    "payload": {
                        "type": "bird_observation",
                        "reported_left": 3,
                        "reported_right": 2,
                        "visible_left": 4,
                        "visible_right": 4,
                    }
                },
            ]
            path.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            result = analyze_bird_counts(path)

        self.assertEqual(
            result,
            {
                "visible_total": 8,
                "visible_left": 4,
                "visible_right": 4,
                "reported_total": 5,
                "reported_left": 3,
                "reported_right": 2,
            },
        )

    def test_new_generated_count_resets_previous_reported_values(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "vr_events.ndjson"
            records = [
                {
                    "payload": {
                        "type": "bird_observation",
                        "reported_left": 4,
                        "reported_right": 3,
                    }
                },
                {"payload": {"type": "bird_count", "visible": 2, "left": 0, "right": 2}},
            ]
            path.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            result = analyze_bird_counts(path)

        self.assertEqual(result["visible_left"], 0)
        self.assertEqual(result["reported_total"], 0)


if __name__ == "__main__":
    unittest.main()
