from __future__ import annotations

import asyncio
import unittest

from eeg_mock import build_mock_eeg_payload, reset_mock_state
from eeg_service import (
    BrainAccessEegService,
    DisabledEegService,
    EegStatus,
    MockEegService,
    create_eeg_service,
)


class FakeConnectionManager:
    def __init__(self) -> None:
        self.payloads: list[dict] = []
        self.received = asyncio.Event()

    async def broadcast_json(self, payload: dict, sender=None) -> None:
        self.payloads.append(payload)
        self.received.set()


class FakeBrainAccessStream:
    def __init__(self, *, fail_on_start: bool = False) -> None:
        self.fail_on_start = fail_on_start
        self.started = False
        self.closed = False

    def start(self) -> None:
        if self.fail_on_start:
            raise RuntimeError("sensor unavailable")
        self.started = True

    def build_payload(self) -> dict:
        return {"type": "eeg_data", "channels": ["Fp1"]}

    def close(self) -> None:
        self.closed = True


async def _wait_for_status(
    service,
    expected: EegStatus,
    *,
    timeout: float = 1.0,
) -> None:
    async def wait() -> None:
        while service.status != expected:
            await asyncio.sleep(0)

    await asyncio.wait_for(wait(), timeout=timeout)


class EegServiceTests(unittest.IsolatedAsyncioTestCase):
    def test_mock_payloads_have_contiguous_non_overlapping_sample_offsets(self) -> None:
        reset_mock_state()

        first = build_mock_eeg_payload()
        second = build_mock_eeg_payload()

        self.assertEqual(first["sequence"], 0)
        self.assertEqual(first["sample_start"], 0)
        self.assertEqual(first["sample_count"], 250)
        self.assertEqual(second["sequence"], 1)
        self.assertEqual(second["sample_start"], 250)
        self.assertEqual(second["sample_count"], 250)

    async def test_disabled_service_stays_disconnected(self) -> None:
        manager = FakeConnectionManager()
        service = DisabledEegService()

        await service.start(manager)
        await service.stop()

        self.assertEqual(service.status, EegStatus.DISCONNECTED)
        self.assertEqual(manager.payloads, [])

    async def test_mock_service_broadcasts_and_stops(self) -> None:
        manager = FakeConnectionManager()
        service = MockEegService()

        await service.start(manager)
        await asyncio.wait_for(manager.received.wait(), timeout=2.0)

        self.assertEqual(service.status, EegStatus.STREAMING)
        self.assertEqual(manager.payloads[0]["type"], "eeg_data")

        await service.stop()
        self.assertEqual(service.status, EegStatus.DISCONNECTED)

    async def test_brainaccess_service_uses_device_and_closes_stream(self) -> None:
        manager = FakeConnectionManager()
        stream = FakeBrainAccessStream()
        requested_devices: list[str] = []

        def stream_factory(device_name: str):
            requested_devices.append(device_name)
            return stream

        service = BrainAccessEegService(
            "BA MINI TEST",
            stream_factory=stream_factory,
        )

        await service.start(manager)
        await asyncio.wait_for(manager.received.wait(), timeout=1.0)

        self.assertEqual(requested_devices, ["BA MINI TEST"])
        self.assertTrue(stream.started)
        self.assertEqual(service.status, EegStatus.STREAMING)

        await service.stop()
        self.assertTrue(stream.closed)
        self.assertEqual(service.status, EegStatus.DISCONNECTED)

    async def test_brainaccess_initialization_failure_sets_error_state(self) -> None:
        manager = FakeConnectionManager()
        stream = FakeBrainAccessStream(fail_on_start=True)
        service = BrainAccessEegService(
            "BA MINI TEST",
            stream_factory=lambda _: stream,
        )

        with self.assertLogs("eeg_service", level="ERROR"):
            await service.start(manager)
            await _wait_for_status(service, EegStatus.ERROR)

        self.assertEqual(service.error, "sensor unavailable")
        self.assertTrue(stream.closed)
        await service.stop()
        self.assertEqual(service.status, EegStatus.ERROR)

    def test_factory_selects_service_without_loading_brainaccess(self) -> None:
        self.assertIsInstance(create_eeg_service("off", "device"), DisabledEegService)
        self.assertIsInstance(create_eeg_service("mock", "device"), MockEegService)
        self.assertIsInstance(
            create_eeg_service("real", "device"),
            BrainAccessEegService,
        )


if __name__ == "__main__":
    unittest.main()
