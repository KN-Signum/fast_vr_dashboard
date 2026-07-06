"""
UDP Beacon Manager for headset discovery.
Broadcasts the server's WebSocket URL so that headsets on the local network
can auto-discover this server and connect as WebSocket clients.
"""

import asyncio
import json
import logging
import os
import socket
import subprocess
import sys

logger = logging.getLogger(__name__)

BEACON_PORT = 15000
BEACON_INTERVAL = 1.0  # seconds between broadcasts


def _interface_ip(interface: str) -> str | None:
    """Return IPv4 for a named interface when available (macOS/Linux)."""
    if sys.platform == "darwin":
        try:
            ip = subprocess.check_output(
                ["ipconfig", "getifaddr", interface],
                text=True,
                stderr=subprocess.DEVNULL,
            ).strip()
            return ip or None
        except Exception:
            return None

    try:
        import fcntl
        import struct

        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            return socket.inet_ntoa(
                fcntl.ioctl(
                    s.fileno(),
                    0x8915,  # SIOCGIFADDR
                    struct.pack("256s", interface.encode()[:15]),
                )[20:24]
            )
    except Exception:
        return None


def _get_local_ip() -> str:
    """Detect the LAN IP headsets should use to reach this machine."""
    override = os.environ.get("BEACON_HOST", "").strip()
    if override:
        return override

    # Prefer Wi-Fi on macOS — the 8.8.8.8 trick often picks VPN/Ethernet instead.
    for interface in ("en0", "en1", "wlan0", "eth0"):
        ip = _interface_ip(interface)
        if ip and not ip.startswith("127."):
            return ip

    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            s.connect(("8.8.8.8", 80))
            return s.getsockname()[0]
    except Exception:
        return socket.gethostbyname(socket.gethostname())


class BeaconManager:
    """Broadcasts a UDP beacon so headsets can discover this server."""

    def __init__(self, ws_port: int = 8080):
        self._ws_port = ws_port
        self._running = False
        self._task: asyncio.Task | None = None
        self._sock: socket.socket | None = None

    @property
    def running(self) -> bool:
        return self._running

    def _build_payload(self) -> bytes:
        """Build the JSON beacon payload with the current server IP."""
        local_ip = _get_local_ip()
        payload = {
            "service": "hrv-biofeedback",
            "ws_url": f"ws://{local_ip}:{self._ws_port}/ws",
        }
        return json.dumps(payload).encode("utf-8")

    async def start(self):
        if self._running:
            logger.info("Beacon already running")
            return

        # 1. Grab the correct local IP first
        local_ip = _get_local_ip()

        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
        self._sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        self._sock.setblocking(False)

        # Bind all interfaces so broadcast works even when multiple NICs are active.
        self._sock.bind(("0.0.0.0", 0))

        self._running = True
        self._task = asyncio.create_task(self._broadcast_loop())
        ws_url = f"ws://{local_ip}:{self._ws_port}/ws"
        logger.info(f"UDP beacon started on port {BEACON_PORT}")
        logger.info(f"Headsets should connect to: {ws_url}")
        print(f"📡 Beacon advertising: {ws_url}")

    async def stop(self):
        """Stop the beacon broadcast."""
        if not self._running:
            return

        self._running = False
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None

        if self._sock:
            self._sock.close()
            self._sock = None

        logger.info("UDP beacon stopped")

    async def _broadcast_loop(self):
        """Send beacon packets at a fixed interval."""
        try:
            while self._running:
                try:
                    payload = self._build_payload()
                    self._sock.sendto(payload, ("255.255.255.255", BEACON_PORT))
                except Exception as e:
                    logger.warning(f"Beacon send failed: {e}")
                await asyncio.sleep(BEACON_INTERVAL)
        except asyncio.CancelledError:
            pass
