import asyncio
import json
from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from typing import List
from contextlib import asynccontextmanager

@asynccontextmanager
async def lifespan(app: FastAPI):
    # Logika przy starcie (Startup)
    print("🧠 Inicjalizacja strumienia danych...")
    # eeg_task = asyncio.create_task(eeg_stream_task())
    
    yield  # Tutaj aplikacja "działa"
    
    # Logika przy zamknięciu (Shutdown)
    print("🛑 Zamykanie zadań...")
    # eeg_task.cancel()

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