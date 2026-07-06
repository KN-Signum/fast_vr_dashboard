import asyncio
import json
import os
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware
from typing import List
from contextlib import asynccontextmanager
from et_mock import eye_tracking_mock_task, et_stream_enabled
from beacon_manager import BeaconManager

USE_REAL_EEG = 0

if USE_REAL_EEG:
    from eeg_stream import eeg_stream_task
else:
    from eeg_mock import eeg_mock_task as eeg_stream_task

et_stream_task  = None
eeg_task = None
beacon = BeaconManager(ws_port=8080)  # match your uvicorn port

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

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global et_stream_task, eeg_task
    print("🧠 Inicjalizacja strumienia danych...")
    print(f"🧪 EEG mode: {'real' if USE_REAL_EEG else 'mock'}")
    et_stream_task = asyncio.create_task(eye_tracking_mock_task(manager))
    eeg_task = asyncio.create_task(eeg_stream_task(manager))
    await beacon.start() 

    yield  # App running
    
    # Shutdown
    global et_stream_enabled
    print("🛑 Zamykanie zadań...")
    await beacon.stop() 
    et_stream_enabled = False
    if et_stream_task:
        et_stream_task.cancel()
        try:
            await et_stream_task
        except asyncio.CancelledError:
            pass
    if eeg_task:
        eeg_task.cancel()
        try:
            await eeg_task
        except asyncio.CancelledError:
            pass

app = FastAPI(lifespan=lifespan)

# CORS middleware for WebSocket connections
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class WasmSecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        return response

app.add_middleware(WasmSecurityMiddleware)

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    await manager.connect(websocket)
    print(f"🔌 WS connected: {websocket.client}")
    # await beacon.stop() 
    try:
        while True:
            data = await websocket.receive()
            if "bytes" in data:
                await manager.broadcast_binary(data["bytes"], sender=websocket)
            elif "text" in data:
                message = json.loads(data["text"])
                print(f"📨 WS text received: {message.get('type', 'unknown')}")
                await manager.broadcast_json(message, sender=websocket)
    except WebSocketDisconnect:
        manager.disconnect(websocket)
        print(f"🔌 WS disconnected: {websocket.client}")
    except Exception as e:
        print(f"⚠️ Błąd połączenia: {e}")
        manager.disconnect(websocket)

# Static web frontend app
app.mount("/", StaticFiles(directory="static/web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    # Uruchamiamy na 8080
    uvicorn.run(app, host="0.0.0.0", port=8080)

# Set USE_REAL_EEG=1 to use the BrainAccess-backed EEG stream.
# uv uv run uvicorn main:app --host 0.0.0.0 --port 8080
