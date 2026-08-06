from __future__ import annotations

import json
from pathlib import Path
from typing import Any


def analyze_bird_counts(path: Path) -> dict[str, int | None] | None:
    visible_total = None
    visible_left = None
    visible_right = None
    reported_left = 0
    reported_right = 0
    has_bird_data = False

    if not path.exists():
        return None

    with path.open("r", encoding="utf-8") as source:
        for line in source:
            if not line.strip():
                continue
            try:
                record = json.loads(line)
            except (json.JSONDecodeError, TypeError):
                continue
            payload = record.get("payload")
            if not isinstance(payload, dict):
                continue

            message_type = payload.get("type")
            if message_type == "bird_count":
                has_bird_data = True
                visible_total = _count(payload.get("visible"))
                visible_left = _count(payload.get("left"))
                visible_right = _count(payload.get("right"))
                reported_left = 0
                reported_right = 0
            elif message_type == "bird_observation":
                has_bird_data = True
                reported_left = _count(payload.get("reported_left")) or 0
                reported_right = _count(payload.get("reported_right")) or 0
                observation_left = _count(payload.get("visible_left"))
                observation_right = _count(payload.get("visible_right"))
                if observation_left is not None:
                    visible_left = observation_left
                if observation_right is not None:
                    visible_right = observation_right

    if not has_bird_data:
        return None
    if visible_total is None and visible_left is not None and visible_right is not None:
        visible_total = visible_left + visible_right
    return {
        "visible_total": visible_total,
        "visible_left": visible_left,
        "visible_right": visible_right,
        "reported_total": reported_left + reported_right,
        "reported_left": reported_left,
        "reported_right": reported_right,
    }


def _count(value: Any) -> int | None:
    if isinstance(value, bool) or not isinstance(value, int) or value < 0:
        return None
    return value
