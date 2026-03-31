"""
EEG stream module — BrainAccess integration.

Current state: fully mocked (no physical device needed).
When the BrainAccess device is available, replace the mock generation
section with real SDK calls (see TODO comments).

ERD (Event-Related Desynchronization) overview
-----------------------------------------------
ERD measures a *relative decrease* in oscillatory power within a frequency
band compared to a pre-event baseline. Formula:

    ERD% = (A - R) / R * 100

    A = power in the event window (e.g. during motor task)
    R = power in the reference/baseline window (e.g. 1s before stimulus)

Negative ERD% → desynchronization (suppressed rhythm, active processing)
Positive ERD% → synchronization (ERS, e.g. beta rebound after movement)

Most relevant bands for VR cognitive research:
  • Mu / Alpha (8–12 Hz)  — motor planning, visual attention
  • Beta       (13–30 Hz) — motor execution; beta ERS = post-movement rebound
  • Theta       (4–8 Hz)  — working memory, cognitive load
  • Delta       (1–4 Hz)  — deep cognitive states, attentional narrowing

In the dashboard, ERD can be shown as a bar chart per channel,
where negative = desync (engagement) and positive = sync (idle).
"""

import asyncio
import random
import math
import time


# Channel layout — 8-channel cap (standard 10-20 positions)
CHANNELS = ["Fp1", "Fp2", "F3", "F4", "C3", "C4", "P3", "P4"]
SAMPLING_RATE = 250  # Hz — typical BrainAccess board


def _mock_band_power() -> dict[str, list[float]]:
    """
    Simulate realistic band power values (µV²/Hz) per channel.

    TODO: Replace with real computation:
        raw = eeg.get_mne(tim=1.0)         # last 1s of data
        psds, freqs = raw.compute_psd().get_data(return_freqs=True)
        # slice psds by frequency band indices
    """
    n = len(CHANNELS)
    return {
        "delta": [round(random.uniform(0.5, 2.0), 3) for _ in range(n)],
        "theta": [round(random.uniform(0.3, 1.5), 3) for _ in range(n)],
        "alpha": [round(random.uniform(0.8, 3.0), 3) for _ in range(n)],
        "beta":  [round(random.uniform(0.2, 1.2), 3) for _ in range(n)],
    }


def _mock_erd(band_power: dict[str, list[float]]) -> dict[str, list[float]]:
    """
    Simulate ERD% values per channel for alpha and beta bands.

    ERD% = (A - R) / R * 100
    Negative = desynchronization (engagement / motor activity).
    Positive = synchronization (beta rebound / idle state).

    TODO: Replace with baseline-relative computation:
        baseline_power = ...  # average power during pre-stimulus period
        event_power    = ...  # power during event window
        erd_pct = (event_power - baseline_power) / baseline_power * 100
    """
    n = len(CHANNELS)
    erd = {}
    for band in ("alpha", "beta"):
        values = []
        for i in range(n):
            # Simulate slow drift: ERD oscillates over time using sine
            t = time.time()
            drift = math.sin(t * 0.3 + i) * 15          # slow modulation
            noise = random.gauss(0, 5)                    # random noise
            erd_pct = -20 + drift + noise                 # baseline ~-20% (mild desync)
            values.append(round(erd_pct, 2))
        erd[band] = values
    return erd


def _mock_focus_index(band_power: dict[str, list[float]]) -> float:
    """
    Compute a simple focus index: mean(alpha) / (mean(alpha) + mean(beta)).

    Higher value → more alpha relative to beta → relaxed / less focused.
    Lower value  → more beta relative to alpha → active / focused.

    TODO: Can also derive from ERD: sustained alpha ERD = sustained attention.
    """
    alpha_mean = sum(band_power["alpha"]) / len(CHANNELS)
    beta_mean  = sum(band_power["beta"])  / len(CHANNELS)
    return round(alpha_mean / (alpha_mean + beta_mean), 3)


def build_eeg_payload() -> dict:
    """
    Build a single EEG WebSocket message.

    This function is the integration seam:
    - In mock mode: calls _mock_* helpers above.
    - In production: call the BrainAccess SDK here and compute real values.

    TODO (production):
        from brainaccess.utils import acquisition
        raw = eeg.get_mne(tim=1.0)
        band_power = compute_band_power(raw)   # your real implementation
        erd        = compute_erd(raw, baseline) # your real implementation
    """
    band_power = _mock_band_power()
    erd        = _mock_erd(band_power)

    return {
        "type":          "eeg_data",
        "sampling_rate": SAMPLING_RATE,
        "channels":      CHANNELS,
        "band_power":    band_power,   # µV²/Hz per channel
        "erd":           erd,          # ERD% per channel (alpha + beta)
        "focus_index":   _mock_focus_index(band_power),  # 0–1 scalar
        "timestamp_ms":  int(time.time() * 1000),
    }


# --- Stream task ---

eeg_stream_enabled = True


async def eeg_stream_task(manager) -> None:
    """
    Broadcasts EEG data to all WebSocket clients at ~10 Hz.

    10 Hz is enough for smooth real-time plots on the dashboard;
    the raw 250 Hz is processed inside build_eeg_payload() and
    summarised into band power / ERD before sending.

    TODO: Initialize real BrainAccess device before starting the loop:
        from brainaccess.utils import acquisition
        from brainaccess.core.eeg_manager import EEGManager
        mgr = EEGManager()
        eeg = acquisition.EEG(mode="roll")
        eeg.setup(mgr, device_name="BA BOARD", cap={i: ch for i, ch in enumerate(CHANNELS)})
        eeg.start_acquisition()
        # then call eeg.get_mne(tim=1.0) inside the loop
    """
    global eeg_stream_enabled
    print("🧠 EEG stream started (10 Hz)...")

    try:
        while eeg_stream_enabled:
            payload = build_eeg_payload()
            await manager.broadcast_json(payload)
            await asyncio.sleep(0.1)   # 10 Hz
    except asyncio.CancelledError:
        print("🧠 EEG stream stopped")
    except Exception as e:
        print(f"❌ EEG stream error: {e}")
