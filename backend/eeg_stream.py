from __future__ import annotations

import logging
import threading
from typing import Any

import numpy as np

from eeg_payload import EegPayload


logger = logging.getLogger(__name__)

CHANNELS = ["Fp1", "Fp2", "O1", "O2"]
CHANNEL_MAP = {0: "Fp1", 1: "Fp2", 2: "O1", 3: "O2"}
SAMPLING_RATE = 250


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

    def start(self) -> None:
        from brainaccess.core import eeg_channel
        from brainaccess.core.eeg_manager import EEGManager
        from brainaccess.utils import acquisition

        self._manager_destroyed = False
        self._sequence = 0
        self._sample_cursor = 0
        try:
            self._eeg = acquisition.EEG(mode="roll")
            self._core_initialized = True
            self._manager = EEGManager()
            self._eeg.setup(
                self._manager,
                device_name=self.device_name,
                cap=CHANNEL_MAP,
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
        payload = EegPayload(
            sampling_rate=SAMPLING_RATE,
            channels=CHANNELS,
            raw_signal={
                channel: eeg_uv[index, :].tolist()
                for index, channel in enumerate(CHANNELS)
            },
            data_uv=eeg_uv[:, -1].tolist(),
            sequence=self._sequence,
            sample_start=self._sample_cursor,
            sample_count=sample_count,
        ).to_dict()
        self._sequence += 1
        self._sample_cursor += sample_count
        return payload

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
