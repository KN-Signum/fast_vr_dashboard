from __future__ import annotations

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Awaitable, Callable

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.staticfiles import StaticFiles
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware

from beacon_manager import BeaconManager
from config import AppSettings
from connection_manager import ConnectionManager
from paths import AppPaths


logger = logging.getLogger(__name__)
StreamRunner = Callable[[ConnectionManager], Awaitable[None]]


@dataclass(slots=True)
class RuntimeState:
    eeg_status: str = "disabled"
    et_status: str = "disabled"
    eeg_error: str | None = None
    et_error: str | None = None
    beacon_running: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)


class ResponseHeadersMiddleware(BaseHTTPMiddleware):
    _NO_CACHE_PATHS = {
        "/",
        "/index.html",
        "/main.dart.js",
        "/flutter.js",
        "/flutter_bootstrap.js",
        "/flutter_service_worker.js",
        "/manifest.json",
        "/version.json",
        "/build-info.json",
    }

    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["Cross-Origin-Embedder-Policy"] = "require-corp"
        response.headers["Cross-Origin-Opener-Policy"] = "same-origin"

        if request.url.path.startswith("/api/") or request.url.path in self._NO_CACHE_PATHS:
            response.headers["Cache-Control"] = "no-store, no-cache, must-revalidate"
            response.headers["Pragma"] = "no-cache"
            response.headers["Expires"] = "0"
        return response


def _load_eeg_runner(mode: str) -> StreamRunner | None:
    if mode == "off":
        return None
    if mode == "mock":
        import eeg_mock

        eeg_mock.eeg_mock_enabled = True
        return eeg_mock.eeg_mock_task

    from eeg_stream import eeg_stream_task

    return eeg_stream_task


def _load_et_runner(mode: str) -> StreamRunner | None:
    if mode != "mock":
        return None

    import et_mock

    et_mock.et_stream_enabled = True
    return et_mock.eye_tracking_mock_task


def _start_stream(
    *,
    name: str,
    runner: StreamRunner,
    manager: ConnectionManager,
    runtime: RuntimeState,
) -> asyncio.Task:
    status_field = f"{name}_status"
    error_field = f"{name}_error"

    async def guarded_runner() -> None:
        setattr(runtime, status_field, "running")
        setattr(runtime, error_field, None)
        try:
            await runner(manager)
        except asyncio.CancelledError:
            raise
        except Exception as error:
            setattr(runtime, status_field, "error")
            setattr(runtime, error_field, str(error))
            logger.exception("%s stream stopped with an error", name.upper())
        else:
            setattr(runtime, status_field, "stopped")

    task = asyncio.create_task(
        guarded_runner(),
        name=f"panel-vr-{name}-stream",
    )
    runtime.tasks.append(task)
    return task


def _validate_static_dir(paths: AppPaths) -> None:
    index_file = paths.static_dir / "index.html"
    if not index_file.is_file():
        raise RuntimeError(
            "Nie znaleziono aplikacji Flutter Web. "
            f"Oczekiwany plik: {index_file}"
        )


def create_app(settings: AppSettings | None = None) -> FastAPI:
    resolved_settings = settings or AppSettings.from_env()
    paths = AppPaths.from_settings(resolved_settings)
    _validate_static_dir(paths)

    manager = ConnectionManager()
    runtime = RuntimeState(
        eeg_status="disabled" if resolved_settings.eeg_mode == "off" else "pending",
        et_status={
            "off": "disabled",
            "vr": "awaiting_vr",
            "mock": "pending",
        }[resolved_settings.et_mode],
    )
    beacon = BeaconManager(ws_port=resolved_settings.port)

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        logger.info(
            "Starting runtime: environment=%s eeg=%s et=%s",
            resolved_settings.environment,
            resolved_settings.eeg_mode,
            resolved_settings.et_mode,
        )

        try:
            eeg_runner = _load_eeg_runner(resolved_settings.eeg_mode)
            if eeg_runner is not None:
                _start_stream(
                    name="eeg",
                    runner=eeg_runner,
                    manager=manager,
                    runtime=runtime,
                )
        except Exception as error:
            runtime.eeg_status = "error"
            runtime.eeg_error = str(error)
            logger.exception("Could not initialize the EEG stream")

        try:
            et_runner = _load_et_runner(resolved_settings.et_mode)
            if et_runner is not None:
                _start_stream(
                    name="et",
                    runner=et_runner,
                    manager=manager,
                    runtime=runtime,
                )
        except Exception as error:
            runtime.et_status = "error"
            runtime.et_error = str(error)
            logger.exception("Could not initialize the eye-tracking stream")

        if resolved_settings.beacon_enabled:
            try:
                await beacon.start()
                runtime.beacon_running = beacon.running
            except Exception:
                logger.exception("Could not start the UDP beacon")

        try:
            yield
        finally:
            logger.info("Stopping Panel VR background services")
            if beacon.running:
                await beacon.stop()
            runtime.beacon_running = False

            for task in runtime.tasks:
                task.cancel()
            if runtime.tasks:
                await asyncio.gather(*runtime.tasks, return_exceptions=True)
            runtime.tasks.clear()

            if runtime.eeg_status not in {"disabled", "error"}:
                runtime.eeg_status = "stopped"
            if runtime.et_status not in {"disabled", "awaiting_vr", "error"}:
                runtime.et_status = "stopped"

    app = FastAPI(
        title="Panel VR",
        version=resolved_settings.app_version,
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.paths = paths
    app.state.connection_manager = manager
    app.state.runtime = runtime
    app.state.beacon = beacon

    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(ResponseHeadersMiddleware)

    @app.get("/api/health")
    async def health() -> dict:
        return {
            "status": "ok",
            "application": "panel-vr",
            "version": resolved_settings.app_version,
            "environment": resolved_settings.environment,
            "eeg_mode": resolved_settings.eeg_mode,
            "eeg_status": runtime.eeg_status,
            "eeg_error": runtime.eeg_error,
            "et_mode": resolved_settings.et_mode,
            "et_status": runtime.et_status,
            "et_error": runtime.et_error,
            "beacon_running": runtime.beacon_running,
        }

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket):
        await manager.connect(websocket)
        logger.info("WebSocket connected from %s", websocket.client)
        try:
            while True:
                data = await websocket.receive()
                if data.get("type") == "websocket.disconnect":
                    break

                binary_data = data.get("bytes")
                text_data = data.get("text")
                if binary_data is not None:
                    await manager.broadcast_binary(
                        binary_data,
                        sender=websocket,
                    )
                elif text_data is not None:
                    message = json.loads(text_data)
                    logger.debug(
                        "WebSocket JSON received: %s",
                        message.get("type", "unknown"),
                    )
                    await manager.broadcast_json(message, sender=websocket)
        except WebSocketDisconnect:
            logger.info("WebSocket disconnected from %s", websocket.client)
        except Exception:
            logger.exception("WebSocket connection failed")
        finally:
            manager.disconnect(websocket)

    app.mount(
        "/",
        StaticFiles(directory=paths.static_dir, html=True),
        name="static",
    )
    return app


settings = AppSettings.from_env(default_environment="development")
app = create_app(settings)


if __name__ == "__main__":
    from launcher import run

    raise SystemExit(run(create_app=create_app))
