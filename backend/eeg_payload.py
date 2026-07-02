from __future__ import annotations

from dataclasses import asdict, dataclass, field
from time import time
from typing import Any


@dataclass(slots=True)
class EegPayload:
    type: str = "eeg_data"
    sampling_rate: int = 250
    channels: list[str] = field(default_factory=list)
    raw_signal: dict[str, list[float]] = field(default_factory=dict)
    data_uv: list[float] = field(default_factory=list)
    band_power: dict[str, list[float]] = field(default_factory=dict)
    erd: dict[str, list[float]] = field(default_factory=dict)
    focus_index: float = 0.0
    timestamp_ms: int = field(default_factory=lambda: int(time() * 1000))

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)