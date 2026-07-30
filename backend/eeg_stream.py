from __future__ import annotations

import logging
import threading
from typing import Any

import numpy as np

from eeg_payload import EegPayload


logger = logging.getLogger(__name__)

CHANNELS = ["F3", "F4", "C3", "C4", "P3", "P4", "O1", "O2"]
CHANNEL_MAP = dict(enumerate(CHANNELS))
BIAS_CHANNELS = list(CHANNEL_MAP)
SAMPLING_RATE = 250
ERD_BASELINE_SECONDS = 30
ERD_WINDOW_SECONDS = 1
ERD_CURRENT_WINDOW_SECONDS = 5
ALPHA_BAND_HZ = (8.0, 13.0)
EEG_CLIPPING_THRESHOLD_UV = 562_499.0
EEG_FLAT_RANGE_UV = 0.5
ERD_MAX_DETRENDED_PEAK_UV = 5_000.0


class _AlphaErdProcessor:
    def __init__(self) -> None:
        self._window_samples = SAMPLING_RATE * ERD_WINDOW_SECONDS
        self._pending = np.empty((len(CHANNELS), 0), dtype=float)
        self._baseline_windows: list[np.ndarray] = []
        self._baseline: np.ndarray | None = None
        self._current_windows: list[np.ndarray] = []
        self._collecting = False

    def start_baseline(self) -> None:
        self._pending = np.empty((len(CHANNELS), 0), dtype=float)
        self._baseline_windows = []
        self._baseline = None
        self._current_windows = []
        self._collecting = True

    @property
    def baseline_seconds(self) -> int:
        return min(len(self._baseline_windows), ERD_BASELINE_SECONDS)

    @property
    def status(self) -> str:
        if self._baseline is not None:
            return "ready"
        return "collecting" if self._collecting else "waiting"

    def add_samples(
        self,
        samples: np.ndarray,
    ) -> tuple[
        dict[str, list[float]],
        dict[str, list[float]],
        dict[str, list[float]],
    ]:
        if self._baseline is None and not self._collecting:
            return {}, {}, {}
        self._pending = np.concatenate((self._pending, samples), axis=1)
        latest_power: np.ndarray | None = None

        while self._pending.shape[1] >= self._window_samples:
            window = self._pending[:, : self._window_samples]
            self._pending = self._pending[:, self._window_samples :]
            detrended = self._linear_detrend(window)
            if not self._is_usable_window(window, detrended):
                continue
            power = self._alpha_power(detrended)

            if self._baseline is None:
                self._baseline_windows.append(power)
                if len(self._baseline_windows) == ERD_BASELINE_SECONDS:
                    self._baseline = np.median(self._baseline_windows, axis=0)
                    self._collecting = False
            else:
                self._current_windows.append(power)
                if len(self._current_windows) > ERD_CURRENT_WINDOW_SECONDS:
                    self._current_windows.pop(0)
                if len(self._current_windows) == ERD_CURRENT_WINDOW_SECONDS:
                    latest_power = np.median(self._current_windows, axis=0)

        if latest_power is None or self._baseline is None:
            return {}, {}, {}

        epsilon = np.finfo(float).eps
        normalized = (
            (self._baseline - latest_power)
            / (self._baseline + latest_power + epsilon)
            * 100.0
        )
        conventional = (
            (self._baseline - latest_power)
            / np.maximum(self._baseline, epsilon)
            * 100.0
        )
        return (
            {"alpha": latest_power.tolist()},
            {"alpha": normalized.tolist()},
            {"alpha": conventional.tolist()},
        )

    def _linear_detrend(self, samples: np.ndarray) -> np.ndarray:
        positions = np.arange(samples.shape[1], dtype=float)
        positions -= np.mean(positions)
        denominator = np.sum(positions**2)
        means = np.mean(samples, axis=1, keepdims=True)
        slopes = np.sum((samples - means) * positions, axis=1) / denominator
        return samples - means - slopes[:, np.newaxis] * positions

    def _is_usable_window(
        self,
        raw: np.ndarray,
        detrended: np.ndarray,
    ) -> bool:
        if not np.all(np.isfinite(raw)) or not np.all(np.isfinite(detrended)):
            return False
        if np.any(np.abs(raw) >= EEG_CLIPPING_THRESHOLD_UV):
            return False
        if np.any(np.ptp(raw, axis=1) < EEG_FLAT_RANGE_UV):
            return False
        return not np.any(
            np.max(np.abs(detrended), axis=1) > ERD_MAX_DETRENDED_PEAK_UV
        )

    def _alpha_power(self, detrended: np.ndarray) -> np.ndarray:
        tapered = detrended * np.hanning(detrended.shape[1])
        spectrum = np.abs(np.fft.rfft(tapered, axis=1)) ** 2
        frequencies = np.fft.rfftfreq(
            detrended.shape[1],
            d=1.0 / SAMPLING_RATE,
        )
        low, high = ALPHA_BAND_HZ
        band = (frequencies >= low) & (frequencies < high)
        return np.mean(spectrum[:, band], axis=1)


class _FreshEegBuffer:
    def __init__(self, channel_indexes: list[int]) -> None:
        self._channel_indexes = channel_indexes
        self._lock = threading.Lock()
        self._pending: list[np.ndarray] = []
        self._error: Exception | None = None

    def add_chunk(self, chunk: list[np.ndarray], chunk_size: int) -> None:
        try:
            eeg = np.vstack(
                [
                    np.asarray(chunk[index], dtype=float).copy()
                    for index in self._channel_indexes
                ]
            )
            if eeg.shape != (len(CHANNELS), chunk_size):
                raise ValueError(
                    f"Unexpected EEG chunk shape {eeg.shape}; "
                    f"expected ({len(CHANNELS)}, {chunk_size})"
                )
        except Exception as error:
            with self._lock:
                self._error = error
            return

        with self._lock:
            self._pending.append(eeg)

    def drain(self) -> np.ndarray | None:
        with self._lock:
            if self._error is not None:
                error = self._error
                self._error = None
                raise RuntimeError("BrainAccess chunk callback failed") from error
            if not self._pending:
                return None
            pending = self._pending
            self._pending = []

        return np.concatenate(pending, axis=1)


class BrainAccessStream:
    def __init__(self, device_name: str) -> None:
        self.device_name = device_name
        self._manager: Any | None = None
        self._eeg: Any | None = None
        self._buffer: _FreshEegBuffer | None = None
        self._manager_destroyed = False
        self._core_initialized = False
        self._sequence = 0
        self._sample_cursor = 0
        self._erd_processor = _AlphaErdProcessor()

    def start(self) -> None:
        from brainaccess.core import eeg_channel
        from brainaccess.core.eeg_manager import EEGManager
        from brainaccess.utils import acquisition

        self._manager_destroyed = False
        self._sequence = 0
        self._sample_cursor = 0
        self._erd_processor = _AlphaErdProcessor()
        try:
            self._eeg = acquisition.EEG(mode="roll")
            self._core_initialized = True
            self._manager = EEGManager()
            self._eeg.setup(
                self._manager,
                device_name=self.device_name,
                cap=CHANNEL_MAP,
                bias=BIAS_CHANNELS,
                sfreq=SAMPLING_RATE,
                zeros_at_start=SAMPLING_RATE,
            )
            self._eeg.start_acquisition()

            channel_indexes = [
                self._manager.get_channel_index(
                    eeg_channel.ELECTRODE_MEASUREMENT + electrode
                )
                for electrode in CHANNEL_MAP
            ]
            self._buffer = _FreshEegBuffer(channel_indexes)
            self._manager.set_callback_chunk(self._buffer.add_chunk)
        except Exception:
            self.close()
            raise

    def build_payload(self) -> dict | None:
        if self._buffer is None:
            raise RuntimeError("BrainAccess EEG stream is not initialized")

        eeg_uv = self._buffer.drain()
        if eeg_uv is None:
            return None

        sample_count = eeg_uv.shape[1]
        band_power, erd, erd_conventional = self._erd_processor.add_samples(
            eeg_uv
        )
        payload = EegPayload(
            sampling_rate=SAMPLING_RATE,
            channels=CHANNELS,
            raw_signal={
                channel: eeg_uv[index, :].tolist()
                for index, channel in enumerate(CHANNELS)
            },
            data_uv=eeg_uv[:, -1].tolist(),
            band_power=band_power,
            erd=erd,
            erd_conventional=erd_conventional,
            erd_status=self._erd_processor.status,
            erd_baseline_seconds=self._erd_processor.baseline_seconds,
            erd_baseline_target_seconds=ERD_BASELINE_SECONDS,
            sequence=self._sequence,
            sample_start=self._sample_cursor,
            sample_count=sample_count,
        ).to_dict()
        self._sequence += 1
        self._sample_cursor += sample_count
        return payload

    def start_erd_baseline(self) -> None:
        self._erd_processor.start_baseline()

    def close(self) -> None:
        eeg = self._eeg
        manager = self._manager

        if eeg is not None and manager is not None:
            try:
                if manager.is_streaming():
                    eeg.stop_acquisition()
            except Exception:
                logger.warning("Could not stop BrainAccess acquisition", exc_info=True)

        if manager is not None and not self._manager_destroyed:
            try:
                manager.destroy()
            except Exception:
                logger.warning("Could not destroy BrainAccess manager", exc_info=True)
            finally:
                self._manager_destroyed = True

        if eeg is not None and self._core_initialized:
            try:
                eeg.close()
            except Exception:
                logger.warning("Could not close BrainAccess core", exc_info=True)
            finally:
                self._core_initialized = False

        self._eeg = None
        self._manager = None
        self._buffer = None
