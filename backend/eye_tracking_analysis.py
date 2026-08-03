from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Any


HEATMAP_COLUMNS = 12
HEATMAP_ROWS = 8
_HORIZONTAL_REGIONS = ("left", "center", "right")
_VERTICAL_REGIONS = ("bottom", "middle", "top")


def analyze_eye_tracking(
    path: Path,
    *,
    columns: int = HEATMAP_COLUMNS,
    rows: int = HEATMAP_ROWS,
) -> dict[str, Any]:
    if columns <= 0 or rows <= 0:
        raise ValueError("Heatmap dimensions must be positive")

    heatmap = [[0 for _ in range(columns)] for _ in range(rows)]
    horizontal = {name: 0 for name in _HORIZONTAL_REGIONS}
    vertical = {name: 0 for name in _VERTICAL_REGIONS}
    regions = {
        f"{vertical_name}_{horizontal_name}": 0
        for vertical_name in reversed(_VERTICAL_REGIONS)
        for horizontal_name in _HORIZONTAL_REGIONS
    }
    total_records = 0
    valid_points = 0

    if path.exists():
        with path.open("r", encoding="utf-8") as source:
            for line in source:
                if not line.strip():
                    continue
                total_records += 1
                try:
                    record = json.loads(line)
                except (json.JSONDecodeError, TypeError):
                    continue
                payload = record.get("payload")
                if not isinstance(payload, dict):
                    continue
                x = _normalized_coordinate(payload.get("gaze_screen_x"))
                y = _normalized_coordinate(payload.get("gaze_screen_y"))
                if x is None or y is None:
                    continue

                valid_points += 1
                column = min(int(x * columns), columns - 1)
                row_from_bottom = min(int(y * rows), rows - 1)
                row = rows - 1 - row_from_bottom
                heatmap[row][column] += 1

                horizontal_name = _third(x, _HORIZONTAL_REGIONS)
                vertical_name = _third(y, _VERTICAL_REGIONS)
                horizontal[horizontal_name] += 1
                vertical[vertical_name] += 1
                regions[f"{vertical_name}_{horizontal_name}"] += 1

    return {
        "total_records": total_records,
        "valid_points": valid_points,
        "valid_percent": _percentage(valid_points, total_records),
        "columns": columns,
        "rows": rows,
        "heatmap_percent": [
            [_percentage(value, valid_points) for value in row] for row in heatmap
        ],
        "horizontal": {
            name: _percentage(horizontal[name], valid_points)
            for name in _HORIZONTAL_REGIONS
        },
        "vertical": {
            name: _percentage(vertical[name], valid_points)
            for name in reversed(_VERTICAL_REGIONS)
        },
        "regions": {
            name: _percentage(value, valid_points)
            for name, value in regions.items()
        },
    }


def _normalized_coordinate(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    coordinate = float(value)
    if not math.isfinite(coordinate) or not 0.0 <= coordinate <= 1.0:
        return None
    return coordinate


def _third(value: float, names: tuple[str, str, str]) -> str:
    if value < 1 / 3:
        return names[0]
    if value < 2 / 3:
        return names[1]
    return names[2]


def _percentage(value: int, total: int) -> float:
    if total <= 0:
        return 0.0
    return round(value * 100.0 / total, 2)
