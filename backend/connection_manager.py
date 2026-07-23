from __future__ import annotations

import logging

from fastapi import WebSocket


logger = logging.getLogger(__name__)


class ConnectionManager:
    def __init__(self) -> None:
        self.active_connections: list[WebSocket] = []

    async def connect(self, websocket: WebSocket) -> None:
        await websocket.accept()
        self.active_connections.append(websocket)
        logger.info(
            "WebSocket client connected; active clients: %d",
            len(self.active_connections),
        )

    def disconnect(self, websocket: WebSocket) -> None:
        if websocket not in self.active_connections:
            return
        self.active_connections.remove(websocket)
        logger.info(
            "WebSocket client disconnected; active clients: %d",
            len(self.active_connections),
        )

    async def broadcast_binary(
        self,
        data: bytes,
        sender: WebSocket | None = None,
    ) -> None:
        await self._broadcast("send_bytes", data, sender)

    async def broadcast_json(
        self,
        data: dict,
        sender: WebSocket | None = None,
    ) -> None:
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
