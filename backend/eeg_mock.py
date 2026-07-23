from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np

from eeg_payload import EegPayload

CHANNELS = ["F3", "F4", "C3", "C4", "P3", "P4", "O1", "O2"]
SAMPLING_RATE = 250
WINDOW_SECONDS = 1.0
TICK_SECONDS = 0.1

@dataclass(slots=True)
class MockBandState:
    baseline: dict[str, np.ndarray] = field(default_factory=dict)
    sample_cursor: int = 0


_state = MockBandState()


def reset_mock_state() -> None:
    global _state
    _state = MockBandState()


def _band_ranges() -> dict[str, tuple[float, float]]:
    return {
        "delta": (0.5, 4.0),
        "theta": (4.0, 8.0),
        "alpha": (8.0, 13.0),
        "beta": (13.0, 30.0),
        "gamma": (30.0, 45.0),
    }


def _generate_waveforms() -> np.ndarray:
    sample_count = int(SAMPLING_RATE * WINDOW_SECONDS)
    base_index = _state.sample_cursor
    time_axis = (np.arange(sample_count) + base_index) / SAMPLING_RATE

    waveforms = []
    for channel_index, _ in enumerate(CHANNELS):
        alpha_freq = 9.5 + channel_index * 0.4
        theta_freq = 5.0 + channel_index * 0.25
        beta_freq = 18.0 + channel_index * 0.6

        alpha = 24.0 * np.sin(2.0 * math.pi * alpha_freq * time_axis + channel_index)
        theta = 12.0 * np.sin(2.0 * math.pi * theta_freq * time_axis + channel_index * 0.7)
        beta = 7.0 * np.sin(2.0 * math.pi * beta_freq * time_axis + channel_index * 1.3)
        drift = 3.0 * np.sin(2.0 * math.pi * 0.8 * time_axis + channel_index * 0.2)
        noise = np.random.normal(0.0, 2.0, sample_count)

        waveforms.append(alpha + theta + beta + drift + noise)

    _state.sample_cursor += int(SAMPLING_RATE * TICK_SECONDS)
    return np.asarray(waveforms, dtype=float)


def _band_power_from_waveforms(waveforms: np.ndarray) -> dict[str, list[float]]:
    freqs = np.fft.rfftfreq(waveforms.shape[1], d=1.0 / SAMPLING_RATE)
    spectrum = np.abs(np.fft.rfft(waveforms, axis=1)) ** 2

    band_power: dict[str, list[float]] = {}
    for band_name, (low, high) in _band_ranges().items():
        mask = (freqs >= low) & (freqs < high)
        if not np.any(mask):
            band_power[band_name] = [0.0] * waveforms.shape[0]
            continue

        values = [
            float(np.trapezoid(channel_spectrum[mask], freqs[mask]))
            for channel_spectrum in spectrum
        ]
        band_power[band_name] = values

    return band_power


def _update_baseline(band_power: dict[str, list[float]]) -> dict[str, list[float]]:
    erd: dict[str, list[float]] = {}
    smoothing = 0.92

    for band_name, values in band_power.items():
        current = np.asarray(values, dtype=float)
        baseline = _state.baseline.get(band_name)
        if baseline is None:
            baseline = current.copy()
        else:
            baseline = smoothing * baseline + (1.0 - smoothing) * current
        _state.baseline[band_name] = baseline

        safe_baseline = np.where(baseline == 0.0, 1.0, baseline)
        erd[band_name] = (((baseline - current) / safe_baseline) * 100.0).tolist()

    return erd


def build_mock_eeg_payload() -> dict:
    waveforms = _generate_waveforms()
    band_power = _band_power_from_waveforms(waveforms)
    erd = _update_baseline(band_power)

    alpha = np.asarray(band_power["alpha"], dtype=float)
    beta = np.asarray(band_power["beta"], dtype=float)
    focus_index = float(np.mean(beta / np.maximum(alpha + beta, 1e-6)))

    return EegPayload(
        sampling_rate=SAMPLING_RATE,
        channels=CHANNELS,
        raw_signal={
            channel: waveforms[index, :].tolist()
            for index, channel in enumerate(CHANNELS)
        },
        data_uv=waveforms[:, -1].tolist(),
        band_power=band_power,
        erd=erd,
        focus_index=focus_index,
    ).to_dict()
