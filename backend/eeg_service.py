from __future__ import annotations

import asyncio
import logging
from abc import ABC, abstractmethod
from enum import StrEnum
from typing import Callable, Protocol

from connection_manager import ConnectionManager


logger = logging.getLogger(__name__)


class EegStatus(StrEnum):
    DISCONNECTED = "disconnected"
    CONNECTING = "connecting"
    STREAMING = "streaming"
    ERROR = "error"


class BrainAccessStreamProtocol(Protocol):
    def start(self) -> None: ...

    def build_payload(self) -> dict: ...

    def close(self) -> None: ...


BrainAccessStreamFactory = Callable[[str], BrainAccessStreamProtocol]


class EegService(ABC):
    def __init__(self, mode: str) -> None:
        self.mode = mode
        self.status = EegStatus.DISCONNECTED
        self.error: str | None = None
        self._task: asyncio.Task | None = None
        self._stop_event = asyncio.Event()

    async def start(self, manager: ConnectionManager) -> None:
        if self._task is not None and not self._task.done():
            return

        self.error = None
        self._stop_event.clear()
        self.status = EegStatus.CONNECTING
        self._task = asyncio.create_task(
            self._run_guarded(manager),
            name=f"panel-vr-eeg-{self.mode}",
        )
        await asyncio.sleep(0)

    async def stop(self) -> None:
        task = self._task
        if task is None:
            if self.status != EegStatus.ERROR:
                self.status = EegStatus.DISCONNECTED
            return

        self._stop_event.set()
        if not task.done():
            try:
                await asyncio.wait_for(asyncio.shield(task), timeout=15.0)
            except TimeoutError:
                logger.warning("EEG service did not stop in time; cancelling it")
                task.cancel()
                await asyncio.gather(task, return_exceptions=True)

        self._task = None
        if self.status != EegStatus.ERROR:
            self.status = EegStatus.DISCONNECTED

    async def _run_guarded(self, manager: ConnectionManager) -> None:
        try:
            await self._run(manager)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            self.status = EegStatus.ERROR
            self.error = str(error)
            logger.exception("%s EEG service stopped with an error", self.mode)
        else:
            if self.status != EegStatus.ERROR:
                self.status = EegStatus.DISCONNECTED

    async def _wait_for_tick(self, seconds: float) -> None:
        try:
            await asyncio.wait_for(self._stop_event.wait(), timeout=seconds)
        except TimeoutError:
            pass

    @abstractmethod
    async def _run(self, manager: ConnectionManager) -> None:
        raise NotImplementedError


class DisabledEegService(EegService):
    def __init__(self) -> None:
        super().__init__("off")

    async def start(self, manager: ConnectionManager) -> None:
        self.status = EegStatus.DISCONNECTED
        self.error = None

    async def _run(self, manager: ConnectionManager) -> None:
        return


class MockEegService(EegService):
    def __init__(self) -> None:
        super().__init__("mock")

    async def _run(self, manager: ConnectionManager) -> None:
        from eeg_mock import TICK_SECONDS, build_mock_eeg_payload, reset_mock_state

        reset_mock_state()
        self.status = EegStatus.STREAMING
        logger.info("Mock EEG stream started")

        while not self._stop_event.is_set():
            payload = await asyncio.to_thread(build_mock_eeg_payload)
            await manager.broadcast_json(payload)
            await self._wait_for_tick(TICK_SECONDS)

        logger.info("Mock EEG stream stopped")


class BrainAccessEegService(EegService):
    def __init__(
        self,
        device_name: str,
        *,
        stream_factory: BrainAccessStreamFactory | None = None,
    ) -> None:
        super().__init__("real")
        self.device_name = device_name
        self._stream_factory = stream_factory or _create_brainaccess_stream
        self._stream: BrainAccessStreamProtocol | None = None

    async def _run(self, manager: ConnectionManager) -> None:
        stream = await asyncio.to_thread(self._stream_factory, self.device_name)
        self._stream = stream
        try:
            logger.info("Connecting to BrainAccess EEG device %s", self.device_name)
            await asyncio.to_thread(stream.start)
            self.status = EegStatus.STREAMING
            logger.info("BrainAccess EEG stream started")

            while not self._stop_event.is_set():
                try:
                    payload = await asyncio.to_thread(stream.build_payload)
                except Exception:
                    logger.warning(
                        "Could not build a BrainAccess EEG payload",
                        exc_info=True,
                    )
                else:
                    await manager.broadcast_json(payload)
                await self._wait_for_tick(0.1)
        finally:
            try:
                await asyncio.to_thread(stream.close)
            except Exception:
                logger.exception("Could not close the BrainAccess EEG stream")
            self._stream = None
            logger.info("BrainAccess EEG stream stopped")


def _create_brainaccess_stream(device_name: str) -> BrainAccessStreamProtocol:
    from eeg_stream import BrainAccessStream

    return BrainAccessStream(device_name=device_name)


def create_eeg_service(mode: str, device_name: str) -> EegService:
    if mode == "off":
        return DisabledEegService()
    if mode == "mock":
        return MockEegService()
    if mode == "real":
        return BrainAccessEegService(device_name=device_name)
    raise ValueError(f"Unsupported EEG mode: {mode}")
