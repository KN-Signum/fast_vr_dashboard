from __future__ import annotations

import logging
from collections.abc import Callable
from typing import Any

from fastapi import WebSocket


logger = logging.getLogger(__name__)
JsonObserver = Callable[[dict[str, Any], str | None], None]
BinaryObserver = Callable[[bytes, str | None], None]


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: list[WebSocket] = []
        self._roles: dict[WebSocket, str] = {}
        self._json_observer: JsonObserver | None = None
        self._binary_observer: BinaryObserver | None = None

    def set_recording_observers(
        self,
        *,
        json_observer: JsonObserver,
        binary_observer: BinaryObserver,
    ) -> None:
        self._json_observer = json_observer
        self._binary_observer = binary_observer

    async def connect(self, websocket: WebSocket, *, role: str = "vr") -> None:
        await websocket.accept()
        self.active_connections.append(websocket)
        self._roles[websocket] = role
        logger.info(
            "WebSocket %s client connected; active clients: %d",
            role,
            len(self.active_connections),
        )

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket not in self.active_connections:
            return
        self.active_connections.remove(websocket)
        self._roles.pop(websocket, None)
        logger.info(
            "WebSocket client disconnected; active clients: %d",
            len(self.active_connections),
        )

    async def broadcast_binary(
        self,
        data: bytes,
        sender: WebSocket | None = None,
    ) -> None:
        if self._binary_observer is not None:
            self._binary_observer(data, self._roles.get(sender))
        await self._broadcast("send_bytes", data, sender)

    async def broadcast_json(
        self,
        data: dict,
        sender: WebSocket | None = None,
    ) -> None:
        if self._json_observer is not None:
            self._json_observer(data, self._roles.get(sender))
        await self._broadcast("send_json", data, sender)

    async def _broadcast(
        self,
        method_name: str,
        data: object,
        sender: WebSocket | None,
    ) -> None:
        disconnected: list[WebSocket] = []
        for connection in tuple(self.active_connections):
            if connection is sender:
                continue
            try:
                await getattr(connection, method_name)(data)
            except Exception:
                logger.warning(
                    "Removing a WebSocket client after a send failure",
                    exc_info=True,
                )
                disconnected.append(connection)

        for connection in disconnected:
            self.disconnect(connection)
