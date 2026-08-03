from __future__ import annotations

import asyncio
import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from session_repository import SessionRepository, isoformat, utc_now


logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class QueuedRecord:
    session_id: str
    stream: str
    record: dict[str, Any]


class SessionService:
    def __init__(
        self,
        repository: SessionRepository,
        *,
        export_dir: Path,
        queue_size: int = 10_000,
        batch_size: int = 256,
    ) -> None:
        self.repository = repository
        self.export_dir = export_dir
        self.queue: asyncio.Queue[QueuedRecord] = asyncio.Queue(maxsize=queue_size)
        self.batch_size = batch_size
        self.active_session_id: str | None = None
        self.error: str | None = None
        self._writer_task: asyncio.Task | None = None
        self._dropped_records = 0
        self._lifecycle_lock = asyncio.Lock()

    async def start(self) -> None:
        await asyncio.to_thread(self.repository.initialize)
        recovered = await asyncio.to_thread(self.repository.recover_active_sessions)
        if recovered:
            logger.warning("Recovered interrupted sessions: %s", ", ".join(recovered))
        active = await asyncio.to_thread(self.repository.get_active_session)
        self.active_session_id = active["id"] if active is not None else None
        self._writer_task = asyncio.create_task(
            self._writer_loop(),
            name="panel-vr-session-writer",
        )

    async def stop(self) -> None:
        async with self._lifecycle_lock:
            session_id = self.active_session_id
            self.active_session_id = None
            await self.queue.join()
            await self._flush_drops(session_id)
            if session_id is not None:
                await asyncio.to_thread(
                    self.repository.end_session,
                    session_id,
                    status="interrupted",
                )
            if self._writer_task is not None:
                self._writer_task.cancel()
                await asyncio.gather(self._writer_task, return_exceptions=True)
                self._writer_task = None

    async def create_session(
        self,
        *,
        patient_id: str,
        preferred_hand: str,
        notes: str,
        eeg_enabled_at_start: bool = True,
    ) -> dict[str, Any]:
        async with self._lifecycle_lock:
            summary = await asyncio.to_thread(
                self.repository.create_session,
                patient_id=patient_id,
                preferred_hand=preferred_hand,
                notes=notes,
                eeg_enabled_at_start=eeg_enabled_at_start,
            )
            self.active_session_id = summary["session_id"]
            self.error = None
            self._dropped_records = 0
            return summary

    async def end_session(self, session_id: str) -> dict[str, Any]:
        async with self._lifecycle_lock:
            if self.active_session_id == session_id:
                self.active_session_id = None
                await self.queue.join()
                await self._flush_drops(session_id)
            return await asyncio.to_thread(self.repository.end_session, session_id)

    async def update_post_session_notes(
        self,
        session_id: str,
        notes: str,
    ) -> dict[str, Any]:
        return await asyncio.to_thread(
            self.repository.update_post_session_notes,
            session_id,
            notes,
        )

    async def add_event(
        self,
        session_id: str,
        *,
        label: str,
        category: str,
        note: str,
    ) -> dict[str, Any]:
        return await asyncio.to_thread(
            self.repository.add_event,
            session_id,
            label=label,
            category=category,
            note=note,
        )

    async def active_summary(self) -> dict[str, Any] | None:
        session_id = self.active_session_id
        if session_id is None:
            return None
        return await asyncio.to_thread(self.repository.summary, session_id)

    async def recovered_summary(self) -> dict[str, Any] | None:
        return await asyncio.to_thread(self.repository.take_recovered_session)

    async def summary(self, session_id: str) -> dict[str, Any]:
        await self._flush_active_session(session_id)
        return await asyncio.to_thread(self.repository.summary, session_id)

    async def raw_archive(self, session_id: str) -> Path:
        await self._flush_active_session(session_id)
        return await asyncio.to_thread(
            self.repository.create_raw_archive,
            session_id,
            self.export_dir,
        )

    def record_json(self, payload: dict[str, Any], sender_role: str | None) -> None:
        message_type = payload.get("type")
        if message_type == "eeg_data":
            self._enqueue("eeg_records", {"payload": payload})
        elif message_type == "eye_tracking":
            self._enqueue("eye_tracking_records", {"payload": payload})
        elif sender_role != "dashboard":
            self._enqueue("vr_events", {"payload": payload})

    def record_binary(self, data: bytes, sender_role: str | None) -> None:
        if sender_role == "dashboard":
            return
        self._enqueue("vr_frames", {"byte_length": len(data)})

    def _enqueue(self, stream: str, record: dict[str, Any]) -> None:
        session_id = self.active_session_id
        if session_id is None:
            return
        record["received_at"] = isoformat(utc_now())
        try:
            self.queue.put_nowait(
                QueuedRecord(
                    session_id=session_id,
                    stream=stream,
                    record=record,
                )
            )
        except asyncio.QueueFull:
            self._dropped_records += 1
            self.error = "Kolejka zapisu sesji jest pełna"

    async def _writer_loop(self) -> None:
        while True:
            first = await self.queue.get()
            batch = [first]
            while len(batch) < self.batch_size:
                try:
                    batch.append(self.queue.get_nowait())
                except asyncio.QueueEmpty:
                    break

            grouped: dict[str, list[tuple[str, dict[str, Any]]]] = {}
            for item in batch:
                grouped.setdefault(item.session_id, []).append(
                    (item.stream, item.record)
                )
            try:
                for session_id, records in grouped.items():
                    await asyncio.to_thread(
                        self.repository.append_records,
                        session_id,
                        records,
                    )
            except Exception as exc:
                self.error = str(exc)
                self._dropped_records += len(batch)
                logger.exception("Could not persist a session recording batch")
            finally:
                for _ in batch:
                    self.queue.task_done()

    async def _flush_drops(self, session_id: str | None) -> None:
        dropped = self._dropped_records
        self._dropped_records = 0
        if session_id is not None and dropped:
            await asyncio.to_thread(
                self.repository.record_drops,
                session_id,
                dropped,
            )

    async def _flush_active_session(self, session_id: str) -> None:
        if self.active_session_id != session_id:
            return
        await self.queue.join()
        await self._flush_drops(session_id)
