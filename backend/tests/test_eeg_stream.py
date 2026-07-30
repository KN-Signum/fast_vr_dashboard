from __future__ import annotations

import unittest

import numpy as np

from eeg_stream import BrainAccessStream, _FreshEegBuffer


def _chunk(sample_numbers: list[int], offset: float = 0.0) -> list[np.ndarray]:
    samples = np.asarray(sample_numbers, dtype=np.uint64)
    base = np.arange(len(sample_numbers), dtype=float) + offset
    return [
        samples,
        base + 10.0,
        base + 20.0,
        base + 30.0,
        base + 40.0,
    ]


class FreshEegBufferTests(unittest.TestCase):
    def setUp(self) -> None:
        self.buffer = _FreshEegBuffer([1, 2, 3, 4], sample_index=0)

    def test_drains_fresh_callback_samples(self) -> None:
        self.buffer.add_chunk(_chunk([100, 101, 102]), 3)

        eeg, sample_numbers = self.buffer.drain() or (None, None)

        np.testing.assert_array_equal(sample_numbers, [100, 101, 102])
        np.testing.assert_array_equal(eeg[0], [10.0, 11.0, 12.0])
        self.assertIsNone(self.buffer.drain())

    def test_callback_data_is_copied(self) -> None:
        chunk = _chunk([100, 101])
        self.buffer.add_chunk(chunk, 2)
        chunk[1][:] = -1

        eeg, _ = self.buffer.drain() or (None, None)

        np.testing.assert_array_equal(eeg[0], [10.0, 11.0])

    def test_discards_overlapping_samples(self) -> None:
        self.buffer.add_chunk(_chunk([100, 101, 102]), 3)
        self.buffer.drain()
        self.buffer.add_chunk(_chunk([102, 103, 104], offset=50.0), 3)

        eeg, sample_numbers = self.buffer.drain() or (None, None)

        np.testing.assert_array_equal(sample_numbers, [103, 104])
        np.testing.assert_array_equal(eeg[0], [61.0, 62.0])

    def test_rejects_non_increasing_sensor_sample_numbers(self) -> None:
        self.buffer.add_chunk(_chunk([100, 102, 101]), 3)

        with self.assertRaisesRegex(RuntimeError, "not increasing"):
            self.buffer.drain()


class BrainAccessStreamPayloadTests(unittest.TestCase):
    def test_payload_contains_only_fresh_sensor_samples(self) -> None:
        stream = BrainAccessStream("test")
        stream._buffer = _FreshEegBuffer([1, 2, 3, 4], sample_index=0)
        stream._buffer.add_chunk(_chunk([500, 501, 502]), 3)

        first = stream.build_payload()
        self.assertIsNotNone(first)
        assert first is not None
        self.assertEqual(first["sequence"], 0)
        self.assertEqual(first["sample_start"], 500)
        self.assertEqual(first["sample_count"], 3)
        self.assertEqual(first["raw_signal"]["Fp1"], [10.0, 11.0, 12.0])
        self.assertEqual(first["data_uv"], [12.0, 22.0, 32.0, 42.0])
        self.assertEqual(first["band_power"], {})
        self.assertEqual(first["erd"], {})

        self.assertIsNone(stream.build_payload())

        stream._buffer.add_chunk(_chunk([503, 504], offset=100.0), 2)
        second = stream.build_payload()
        self.assertIsNotNone(second)
        assert second is not None
        self.assertEqual(second["sequence"], 1)
        self.assertEqual(second["sample_start"], 503)


if __name__ == "__main__":
    unittest.main()
