from __future__ import annotations

import logging

import numpy as np

from brainaccess.core.eeg_manager import EEGManager
from brainaccess.utils import acquisition
from eeg_payload import EegPayload


logger = logging.getLogger(__name__)

CHANNELS = ["Fp1", "Fp2", "O1", "O2"]
CHANNEL_MAP = {0: "Fp1", 1: "Fp2", 2: "O1", 3: "O2"}
SAMPLING_RATE = 250
WINDOW_SECONDS = 1


def _to_uv(data: np.ndarray) -> np.ndarray:
    return data * 1e6 if np.abs(data).mean() < 1 else data


def _compute_simple_features(eeg_uv: np.ndarray) -> dict[str, list[float]]:
    alpha = np.mean(np.abs(eeg_uv), axis=1)
    return {
        "alpha": alpha.tolist(),
        "beta": (alpha * 0.6).tolist(),
    }


class BrainAccessStream:
    def __init__(self, device_name: str) -> None:
        self.device_name = device_name
        self._manager: EEGManager | None = None
        self._eeg: acquisition.EEG | None = None
        self._manager_destroyed = False
        self._core_initialized = False

    def start(self) -> None:
        self._manager_destroyed = False
        try:
            self._eeg = acquisition.EEG(mode="roll")
            self._core_initialized = True
            self._manager = EEGManager()
            self._eeg.setup(
                self._manager,
                device_name=self.device_name,
                cap=CHANNEL_MAP,
                sfreq=SAMPLING_RATE,
                zeros_at_start=SAMPLING_RATE * WINDOW_SECONDS,
            )
            self._eeg.start_acquisition()
        except Exception:
            self.close()
            raise

    def build_payload(self) -> dict:
        if self._eeg is None:
            raise RuntimeError("BrainAccess EEG stream is not initialized")

        raw = self._eeg.get_mne(tim=WINDOW_SECONDS, annotations=False)
        data = raw.get_data()
        eeg_uv = _to_uv(data[: len(CHANNELS), :])
        if eeg_uv.shape[1] == 0:
            raise RuntimeError("BrainAccess EEG stream returned no samples")

        return EegPayload(
            sampling_rate=SAMPLING_RATE,
            channels=CHANNELS,
            raw_signal={
                channel: eeg_uv[index, :].tolist()
                for index, channel in enumerate(CHANNELS)
            },
            data_uv=eeg_uv[:, -1].tolist(),
            band_power=_compute_simple_features(eeg_uv),
        ).to_dict()

    def close(self) -> None:
        eeg = self._eeg
        manager = self._manager
        self._eeg = None
        self._manager = None

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
