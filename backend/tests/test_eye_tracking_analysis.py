from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from eye_tracking_analysis import analyze_eye_tracking


class EyeTrackingAnalysisTests(unittest.TestCase):
    def test_builds_heatmap_and_directional_percentages(self) -> None:
        records = [
            _record(0.1, 0.9),
            _record(0.2, 0.5),
            _record(0.5, 0.5),
            _record(0.9, 0.1),
            _record(-1, 0.5),
            {"payload": {"type": "eye_tracking"}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "eye_tracking.ndjson"
            path.write_text(
                "\n".join(json.dumps(record) for record in records) + "\n",
                encoding="utf-8",
            )

            analysis = analyze_eye_tracking(path)

        self.assertEqual(analysis["total_records"], 6)
        self.assertEqual(analysis["valid_points"], 4)
        self.assertEqual(analysis["valid_percent"], 66.67)
        self.assertEqual(
            analysis["horizontal"],
            {"left": 50.0, "center": 25.0, "right": 25.0},
        )
        self.assertEqual(
            analysis["vertical"],
            {"top": 25.0, "middle": 50.0, "bottom": 25.0},
        )
        self.assertEqual(analysis["regions"]["top_left"], 25.0)
        self.assertEqual(analysis["regions"]["bottom_right"], 25.0)
        self.assertEqual(analysis["heatmap_percent"][0][1], 25.0)
        self.assertEqual(analysis["heatmap_percent"][7][10], 25.0)

    def test_returns_zeroed_analysis_without_projected_gaze(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            analysis = analyze_eye_tracking(Path(directory) / "missing.ndjson")

        self.assertEqual(analysis["total_records"], 0)
        self.assertEqual(analysis["valid_points"], 0)
        self.assertEqual(analysis["valid_percent"], 0.0)
        self.assertEqual(len(analysis["heatmap_percent"]), 8)
        self.assertTrue(
            all(len(row) == 12 for row in analysis["heatmap_percent"])
        )


def _record(x: float, y: float) -> dict:
    return {
        "received_at": "2026-08-03T10:00:00Z",
        "payload": {
            "type": "eye_tracking",
            "gaze_screen_x": x,
            "gaze_screen_y": y,
        },
    }


if __name__ == "__main__":
    unittest.main()
