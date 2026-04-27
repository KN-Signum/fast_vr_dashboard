import asyncio
import time
import numpy as np

from brainaccess.utils import acquisition
from brainaccess.core.eeg_manager import EEGManager

CHANNELS = ["Fp1", "Fp2", "O1", "O2"]
SAMPLING_RATE = 250

eeg_stream_enabled = True

# global state (ważne dla FastAPI)
_eeg = None


def _to_uv(data: np.ndarray) -> np.ndarray:
    # BrainAccess już daje sensowne wartości → NIE mnożymy ×1e6
    return data * 1e6 if np.abs(data).mean() < 1 else data


def _compute_simple_features(eeg_uv: np.ndarray):
    """Minimal feature extraction (bez PSD na start)"""
    alpha = np.mean(np.abs(eeg_uv), axis=1)

    return {
        "alpha": alpha.tolist(),
        "beta": (alpha * 0.6).tolist(),  # placeholder
    }


def build_eeg_payload():
    global _eeg

    raw = _eeg.get_mne(tim=1.0)
    data = raw.get_data()

    eeg = data[:4, :]  # tylko EEG

    eeg_uv = _to_uv(eeg)

    band_power = _compute_simple_features(eeg_uv)

    # Debug: Check data shapes
    print(f"🧠 EEG shapes - data: {data.shape}, eeg: {eeg.shape}, eeg_uv: {eeg_uv.shape}")
    print(f"🧠 Band power - alpha len: {len(band_power['alpha'])}, beta len: {len(band_power['beta'])}")
    print(f"🧠 Alpha values: {band_power['alpha']}")

    # Send raw signal: all samples for all 4 channels
    raw_signal = {
        "Fp1": eeg_uv[0, :].tolist(),
        "Fp2": eeg_uv[1, :].tolist(),
        "O1": eeg_uv[2, :].tolist(),
        "O2": eeg_uv[3, :].tolist(),
    }

    return {
        "type": "eeg_data",
        "sampling_rate": SAMPLING_RATE,
        "channels": CHANNELS,
        "raw_signal": raw_signal,  # NEW: Full waveform for all channels
        "data_uv": eeg_uv[:, -1].tolist(),   # ostatnia próbka
        "band_power": band_power,
        "timestamp_ms": int(time.time() * 1000),
    }


async def eeg_stream_task(manager):
    """
    Real BrainAccess stream (10 Hz websocket feed)
    """
    global eeg_stream_enabled, _eeg

    print("🧠 EEG init...")

    mgr = EEGManager()
    _eeg = acquisition.EEG(mode="roll")

    _eeg.setup(
        mgr,
        device_name="BA MINI 037",
        cap={0: "Fp1", 1: "Fp2", 2: "O1", 3: "O2"},
        sfreq=250,
    )

    _eeg.start_acquisition()

    print("🧠 EEG streaming started")

    try:
        while eeg_stream_enabled:
            try:
                payload = build_eeg_payload()
                await manager.broadcast_json(payload)
            except Exception as e:
                print("EEG loop error:", e)

            await asyncio.sleep(0.1)

    except asyncio.CancelledError:
        pass

    finally:
        eeg_stream_enabled = False
        try:
            _eeg.stop_acquisition()
            _eeg.close()
        except:
            pass

        print("🧠 EEG stopped")