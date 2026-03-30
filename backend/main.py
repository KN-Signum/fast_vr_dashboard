import asyncio
import json
import random
from dataclasses import dataclass, asdict
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from typing import List
from contextlib import asynccontextmanager

# --- EYE TRACKING DATA MODEL ---
@dataclass
class Vector3:
    x: float
    y: float
    z: float

@dataclass
class EyeTransform:
    """Represents 3D rotation matrix as 3 orthonormal axes + origin"""
    x_axis: Vector3  # Right vector
    y_axis: Vector3  # Up vector
    z_axis: Vector3  # Forward vector
    origin: Vector3  # Eye position in world space

@dataclass
class EyeTrackingData:
    """Mock eye tracking data from VR app"""
    type: str = "eye_tracking"
    player_position: Vector3 = None
    eyes_position: Vector3 = None
    eyes_transform: EyeTransform = None
    
    def to_dict(self):
        """Convert to JSON-serializable dict"""
        return {
            "type": self.type,
            "player_position": asdict(self.player_position),
            "eyes_position": asdict(self.eyes_position),
            "eyes_transform": {
                "x_axis": asdict(self.eyes_transform.x_axis),
                "y_axis": asdict(self.eyes_transform.y_axis),
                "z_axis": asdict(self.eyes_transform.z_axis),
                "origin": asdict(self.eyes_transform.origin),
            }
        }

# Global flag to control ET stream
et_stream_enabled = True
et_stream_task = None

async def eye_tracking_mock_task():
    """
    Mock eye tracking stream: Generates realistic ET data and broadcasts every 50ms (~20 FPS)
    
    TODO: For production use, replace this with actual BrainAccess API or VR app data
    TODO: Calibration needed for coordinate system mapping:
      - Camera position, FOV, and projection matrix from VR app
      - World-to-screen transformation based on actual game camera setup
    """
    global et_stream_enabled, manager
    print("👁️ Eye-tracking mock stream started (20 FPS)...")
    
    # Base positions for realistic simulation
    base_player_pos = Vector3(x=120.0, y=3.0, z=95.0)
    base_eyes_pos = Vector3(x=120.0, y=3.65, z=95.0)
    
    try:
        while et_stream_enabled:
            # Simulate small variations in eye position (micro-movements)
            eyes_x = base_eyes_pos.x + random.uniform(-0.5, 0.5)
            eyes_y = base_eyes_pos.y + random.uniform(-0.3, 0.3)
            eyes_z = base_eyes_pos.z + random.uniform(-0.5, 0.5)
            
            # Simulate eye rotation (gaze direction) as a rotation matrix
            # (Simple approximation - in production, derive from actual eye gaze)
            angle = random.uniform(0, 2 * 3.14159)
            x_axis = Vector3(x=0.97, y=-0.018, z=-0.244)  # Right
            y_axis = Vector3(x=0.014, y=0.9998, z=-0.015)  # Up
            z_axis = Vector3(x=0.244, y=0.011, z=0.970)    # Forward (gaze direction)
            
            # Add small random variations to simulate natural eye movement
            x_axis.x += random.uniform(-0.02, 0.02)
            y_axis.y += random.uniform(-0.02, 0.02)
            z_axis.z += random.uniform(-0.02, 0.02)
            
            eyes_transform = EyeTransform(
                x_axis=x_axis,
                y_axis=y_axis,
                z_axis=z_axis,
                origin=Vector3(x=eyes_x, y=eyes_y, z=eyes_z)
            )
            
            et_data = EyeTrackingData(
                player_position=base_player_pos,
                eyes_position=Vector3(x=eyes_x, y=eyes_y, z=eyes_z),
                eyes_transform=eyes_transform
            )
            
            # Broadcast to all connected clients
            await manager.broadcast_json(et_data.to_dict())
            
            # 50ms interval = 20 FPS (matching VR preview FPS)
            await asyncio.sleep(0.05)
    except asyncio.CancelledError:
        print("👁️ Eye-tracking stream stopped")
    except Exception as e:
        print(f"❌ Eye-tracking error: {e}")

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Logika przy starcie (Startup)
    global et_stream_task
    print("🧠 Inicjalizacja strumienia danych...")
    et_stream_task = asyncio.create_task(eye_tracking_mock_task())
    
    yield  # Tutaj aplikacja "działa"
    
    # Logika przy zamknięciu (Shutdown)
    global et_stream_enabled
    print("🛑 Zamykanie zadań...")
    et_stream_enabled = False
    if et_stream_task:
        et_stream_task.cancel()
        try:
            await et_stream_task
        except asyncio.CancelledError:
            pass

app = FastAPI(lifespan=lifespan)

# --- 1. NAGŁÓWKI DLA WASM (Kluczowe w 2026!) ---
class WasmSecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        # Te nagłówki pozwalają Skwasm/Wasm działać z pełną prędkością
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        return response

app.add_middleware(WasmSecurityMiddleware)

# --- Zarządzanie połączeniami (bez zmian) ---
class ConnectionManager:
    def __init__(self):
        self.active_connections: List[WebSocket] = []

    async def connect(self, websocket: WebSocket):
        await websocket.accept()
        self.active_connections.append(websocket)
        print(f"✅ Klient podłączony. Aktywnych: {len(self.active_connections)}")

    def disconnect(self, websocket: WebSocket):
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)
            print(f"❌ Klient rozłączony. Pozostało: {len(self.active_connections)}")

    async def broadcast_binary(self, data: bytes, sender: WebSocket):
        for connection in self.active_connections:
            if connection != sender:
                try: await connection.send_bytes(data)
                except: pass

    async def broadcast_json(self, data: dict, sender: WebSocket = None):
        for connection in self.active_connections:
            if connection != sender:
                try: await connection.send_json(data)
                except: pass

manager = ConnectionManager()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    try:
        while True:
            data = await websocket.receive()
            if "bytes" in data:
                await manager.broadcast_binary(data["bytes"], sender=websocket)
            elif "text" in data:
                message = json.loads(data["text"])
                await manager.broadcast_json(message, sender=websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
    except Exception as e:
        print(f"⚠️ Błąd połączenia: {e}")
        manager.disconnect(websocket)

# --- Logika EEG (Miejsce na BrainAccess) ---
# async def eeg_stream_task():
#     print("🧠 Start symulacji strumienia EEG...")
#     while True:
#         mock_eeg = {
#             "type": "eeg_data",
#             "channels": [0.12, -0.45, 0.88, 0.23],
#             "focus_level": 0.75
#         }
#         await manager.broadcast_json(mock_eeg)
#         await asyncio.sleep(0.1)

# @app.on_event("startup")
# async def startup_event():
#     asyncio.create_task(eeg_stream_task())

# --- 2. POPRAWKA ŚCIEŻKI DO PLIKÓW ---
# Skieruj directory na "static/web", żeby index.html był w rogu serwera
app.mount("/", StaticFiles(directory="static/web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    # Uruchamiamy na 8000
    uvicorn.run(app, host="0.0.0.0", port=8080)