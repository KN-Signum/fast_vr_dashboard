import asyncio
import json
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from typing import List
from contextlib import asynccontextmanager
from et_mock import eye_tracking_mock_task, et_stream_enabled

et_stream_task = None

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup
    global et_stream_task
    print("🧠 Inicjalizacja strumienia danych...")
    et_stream_task = asyncio.create_task(eye_tracking_mock_task(manager))
    
    yield  # App running
    
    # Shutdown
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

class WasmSecurityMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"
        return response

app.add_middleware(WasmSecurityMiddleware)

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

# --- EEG ---
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

# Static web frontend app
app.mount("/", StaticFiles(directory="static/web", html=True), name="static")

if __name__ == "__main__":
    import uvicorn
    # Uruchamiamy na 8000
    uvicorn.run(app, host="0.0.0.0", port=8080)