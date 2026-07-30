from __future__ import annotations

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from dataclasses import dataclass, field
from typing import Awaitable, Callable, Literal

from fastapi import FastAPI, HTTPException, Response, WebSocket, WebSocketDisconnect
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field
from starlette.background import BackgroundTask
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.cors import CORSMiddleware

from beacon_manager import BeaconManager
from config import AppSettings
from connection_manager import ConnectionManager
from eeg_service import create_eeg_service
from paths import AppPaths
from session_repository import (
    ActiveSessionExistsError,
    SessionNotFoundError,
    SessionRepository,
    SessionStateError,
)
from session_service import SessionService


logger = logging.getLogger(__name__)
StreamRunner = Callable[[ConnectionManager], Awaitable[None]]


@dataclass(slots=True)
class RuntimeState:
    et_status: str = "disabled"
    et_error: str | None = None
    beacon_running: bool = False
    tasks: list[asyncio.Task] = field(default_factory=list)


class SessionCreateRequest(BaseModel):
    patient_id: str = Field(min_length=1, max_length=256)
    preferred_hand: Literal["not_specified", "left", "right", "ambidextrous"]
    notes: str = Field(default="", max_length=10_000)


class SessionEventRequest(BaseModel):
    label: str = Field(min_length=1, max_length=256)
    category: str = Field(min_length=1, max_length=128)
    note: str = Field(default="", max_length=4_000)


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
        et_status={
            "off": "disabled",
            "vr": "awaiting_vr",
            "mock": "pending",
        }[resolved_settings.et_mode],
    )
    eeg_service = create_eeg_service(
        resolved_settings.eeg_mode,
        resolved_settings.eeg_device_name,
    )
    beacon = BeaconManager(ws_port=resolved_settings.port)
    session_repository = SessionRepository(
        paths.session_database,
        paths.session_dir,
    )
    session_service = SessionService(
        session_repository,
        export_dir=paths.export_dir,
    )
    manager.set_recording_observers(
        json_observer=session_service.record_json,
        binary_observer=session_service.record_binary,
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI):
        logger.info(
            "Starting runtime: environment=%s eeg=%s et=%s",
            resolved_settings.environment,
            resolved_settings.eeg_mode,
            resolved_settings.et_mode,
        )

        try:
            await session_service.start()
            await eeg_service.start(manager)

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

            yield
        finally:
            logger.info("Stopping Panel VR background services")
            if beacon.running:
                await beacon.stop()
            runtime.beacon_running = False

            await eeg_service.stop()

            for task in runtime.tasks:
                task.cancel()
            if runtime.tasks:
                await asyncio.gather(*runtime.tasks, return_exceptions=True)
            runtime.tasks.clear()

            if runtime.et_status not in {"disabled", "awaiting_vr", "error"}:
                runtime.et_status = "stopped"
            await session_service.stop()

    app = FastAPI(
        title="Panel VR",
        version=resolved_settings.app_version,
        lifespan=lifespan,
    )
    app.state.settings = resolved_settings
    app.state.paths = paths
    app.state.connection_manager = manager
    app.state.runtime = runtime
    app.state.eeg_service = eeg_service
    app.state.beacon = beacon
    app.state.session_service = session_service

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
            "eeg_device_name": resolved_settings.eeg_device_name,
            "eeg_status": eeg_service.status.value,
            "eeg_error": eeg_service.error,
            "et_mode": resolved_settings.et_mode,
            "et_status": runtime.et_status,
            "et_error": runtime.et_error,
            "beacon_running": runtime.beacon_running,
            "active_session_id": session_service.active_session_id,
            "session_recording_error": session_service.error,
        }

    @app.post("/api/sessions", status_code=201)
    async def create_session(request: SessionCreateRequest) -> dict:
        patient_id = request.patient_id.strip()
        if not patient_id:
            raise HTTPException(status_code=422, detail="ID pacjenta jest wymagane")
        try:
            created = await session_service.create_session(
                patient_id=patient_id,
                preferred_hand=request.preferred_hand,
                notes=request.notes.strip(),
            )
            try:
                await eeg_service.start_erd_baseline()
            except Exception:
                logger.warning(
                    "Could not start the ERD baseline for the new session",
                    exc_info=True,
                )
            return created
        except ActiveSessionExistsError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error

    @app.get("/api/sessions/active")
    async def active_session() -> dict | None:
        return await session_service.active_summary()

    @app.get("/api/sessions/recovered")
    async def recovered_session() -> dict | None:
        return await session_service.recovered_summary()

    @app.get("/api/sessions/{session_id}/summary")
    async def session_summary(session_id: str) -> dict:
        try:
            return await session_service.summary(session_id)
        except SessionNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error

    @app.post("/api/sessions/{session_id}/events", status_code=201)
    async def add_session_event(
        session_id: str,
        request: SessionEventRequest,
    ) -> dict:
        label = request.label.strip()
        if not label:
            raise HTTPException(status_code=422, detail="Nazwa zdarzenia jest wymagana")
        try:
            return await session_service.add_event(
                session_id,
                label=label,
                category=request.category.strip(),
                note=request.note.strip(),
            )
        except SessionNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        except SessionStateError as error:
            raise HTTPException(status_code=409, detail=str(error)) from error

    @app.post("/api/sessions/{session_id}/end")
    async def end_session(session_id: str) -> dict:
        try:
            return await session_service.end_session(session_id)
        except SessionNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error

    @app.get("/api/sessions/{session_id}/download/summary")
    async def download_session_summary(session_id: str) -> Response:
        try:
            summary = await session_service.summary(session_id)
        except SessionNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        return Response(
            content=json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
            media_type="application/json",
            headers={
                "Content-Disposition": (
                    f'attachment; filename="summary_report_{session_id}.json"'
                )
            },
        )

    @app.get("/api/sessions/{session_id}/download/raw")
    async def download_session_raw_data(session_id: str) -> FileResponse:
        try:
            archive = await session_service.raw_archive(session_id)
        except SessionNotFoundError as error:
            raise HTTPException(status_code=404, detail=str(error)) from error
        return FileResponse(
            archive,
            media_type="application/zip",
            filename=f"raw_data_{session_id}.zip",
            background=BackgroundTask(archive.unlink, missing_ok=True),
        )

    @app.websocket("/ws")
    async def websocket_endpoint(websocket: WebSocket):
        role = websocket.query_params.get("role", "vr").strip().lower()
        if role not in {"dashboard", "vr"}:
            role = "unknown"
        await manager.connect(websocket, role=role)
        logger.info("WebSocket %s connected from %s", role, websocket.client)
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
                    if not isinstance(message, dict):
                        logger.warning("Ignoring non-object WebSocket JSON")
                        continue
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
