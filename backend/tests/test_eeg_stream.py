from __future__ import annotations

import unittest

import numpy as np

from eeg_stream import (
    BIAS_CHANNELS,
    CHANNEL_MAP,
    CHANNELS,
    ERD_BASELINE_SECONDS,
    SAMPLING_RATE,
    BrainAccessStream,
    _AlphaErdProcessor,
    _FreshEegBuffer,
)


def _chunk(sample_numbers: list[int], offset: float = 0.0) -> list[np.ndarray]:
    samples = np.asarray(sample_numbers, dtype=np.uint64)
    base = np.arange(len(sample_numbers), dtype=float) + offset
    return [samples, *[base + 10.0 * index for index in range(1, 9)]]


class FreshEegBufferTests(unittest.TestCase):
    def test_bias_feedback_uses_all_measurement_channels(self) -> None:
        self.assertEqual(BIAS_CHANNELS, list(CHANNEL_MAP))

    def setUp(self) -> None:
        self.buffer = _FreshEegBuffer(list(range(1, 9)))

    def test_drains_fresh_callback_samples(self) -> None:
        self.buffer.add_chunk(_chunk([100, 101, 102]), 3)

        eeg = self.buffer.drain()

        self.assertIsNotNone(eeg)
        assert eeg is not None
        np.testing.assert_array_equal(eeg[0], [10.0, 11.0, 12.0])
        self.assertIsNone(self.buffer.drain())

    def test_callback_data_is_copied(self) -> None:
        chunk = _chunk([100, 101])
        self.buffer.add_chunk(chunk, 2)
        chunk[1][:] = -1

        eeg = self.buffer.drain()

        self.assertIsNotNone(eeg)
        assert eeg is not None
        np.testing.assert_array_equal(eeg[0], [10.0, 11.0])

    def test_keeps_samples_from_consecutive_callbacks(self) -> None:
        self.buffer.add_chunk(_chunk([100, 101, 102]), 3)
        self.buffer.add_chunk(_chunk([102, 103, 104], offset=50.0), 3)

        eeg = self.buffer.drain()

        self.assertIsNotNone(eeg)
        assert eeg is not None
        np.testing.assert_array_equal(
            eeg[0],
            [10.0, 11.0, 12.0, 60.0, 61.0, 62.0],
        )


class BrainAccessStreamPayloadTests(unittest.TestCase):
    def test_payload_contains_only_fresh_sensor_samples(self) -> None:
        stream = BrainAccessStream("test")
        stream._buffer = _FreshEegBuffer(list(range(1, 9)))
        stream._buffer.add_chunk(_chunk([500, 501, 502]), 3)

        first = stream.build_payload()
        self.assertIsNotNone(first)
        assert first is not None
        self.assertEqual(first["sequence"], 0)
        self.assertEqual(first["sample_start"], 0)
        self.assertEqual(first["sample_count"], 3)
        self.assertEqual(first["channels"], CHANNELS)
        self.assertEqual(first["raw_signal"]["F3"], [10.0, 11.0, 12.0])
        self.assertEqual(first["data_uv"], [12.0, 22.0, 32.0, 42.0, 52.0, 62.0, 72.0, 82.0])
        self.assertEqual(first["band_power"], {})
        self.assertEqual(first["erd"], {})
        self.assertEqual(first["erd_conventional"], {})
        self.assertEqual(first["erd_status"], "waiting")

        self.assertIsNone(stream.build_payload())

        stream._buffer.add_chunk(_chunk([503, 504], offset=100.0), 2)
        second = stream.build_payload()
        self.assertIsNotNone(second)
        assert second is not None
        self.assertEqual(second["sequence"], 1)
        self.assertEqual(second["sample_start"], 3)


class AlphaErdProcessorTests(unittest.TestCase):
    def test_uses_robust_baseline_and_bounded_smoothed_change(self) -> None:
        processor = _AlphaErdProcessor()
        processor.start_baseline()
        time_axis = np.arange(SAMPLING_RATE) / SAMPLING_RATE
        baseline_wave = np.sin(2.0 * np.pi * 10.0 * time_axis)
        linear_drift = np.linspace(0.0, 100.0, SAMPLING_RATE)

        for index in range(ERD_BASELINE_SECONDS):
            amplitude = 10.0 if index == 0 else 1.0
            baseline = np.tile(
                amplitude * baseline_wave + linear_drift,
                (len(CHANNELS), 1),
            )
            band_power, erd, conventional = processor.add_samples(baseline)
            self.assertEqual(band_power, {})
            self.assertEqual(erd, {})
            self.assertEqual(conventional, {})

        self.assertEqual(processor.status, "ready")
        self.assertEqual(processor.baseline_seconds, ERD_BASELINE_SECONDS)

        current = np.tile(
            baseline_wave * 0.5 + linear_drift,
            (len(CHANNELS), 1),
        )
        for _ in range(4):
            band_power, erd, conventional = processor.add_samples(current)
            self.assertEqual(band_power, {})
            self.assertEqual(erd, {})
            self.assertEqual(conventional, {})

        band_power, erd, conventional = processor.add_samples(current)

        self.assertEqual(list(band_power), ["alpha"])
        np.testing.assert_allclose(erd["alpha"], [60.0] * len(CHANNELS))
        np.testing.assert_allclose(
            conventional["alpha"],
            [75.0] * len(CHANNELS),
        )

    def test_rejects_bad_windows_without_advancing_baseline(self) -> None:
        processor = _AlphaErdProcessor()
        processor.start_baseline()
        time_axis = np.arange(SAMPLING_RATE) / SAMPLING_RATE
        clipped = np.tile(
            562_500.0 + np.sin(2.0 * np.pi * 10.0 * time_axis),
            (len(CHANNELS), 1),
        )

        band_power, erd, conventional = processor.add_samples(clipped)

        self.assertEqual(band_power, {})
        self.assertEqual(erd, {})
        self.assertEqual(conventional, {})
        self.assertEqual(processor.baseline_seconds, 0)


if __name__ == "__main__":
    unittest.main()
