# Panel VR

Panel VR combines a FastAPI WebSocket server with a Flutter web dashboard for
VR, eye-tracking, and BrainAccess EEG sessions.

## Development

Start the backend:

```shell
cd backend
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Start Flutter on a different port:

```shell
cd frontend
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173
```

The release dashboard derives its WebSocket address from the page URL and
connects to same-origin `/ws`, including a custom FastAPI port. A debug build
started with `flutter run` connects to `ws://127.0.0.1:8080/ws`.

## Frontend release build

The release version is stored in `VERSION`. The same version must be present in
`frontend/pubspec.yaml` and `backend/pyproject.toml`; the verifier rejects a
mismatch.

On Windows, run the complete frontend gate and backend tests:

```powershell
.\scripts\build_all.ps1
```

To build only the frontend:

```powershell
.\scripts\build_frontend.ps1
```

The build machine needs Flutter, Dart, Git, and uv on `PATH`. The delivered
client package will not need those tools.

The frontend build performs dependency resolution, formatting checks, static
analysis, tests, and a release web compilation. It writes `build-info.json`
with the app version, build number, Git commit, dirty-worktree flag, and UTC
timestamp. It then replaces `backend/static/web` with an exact copy of
`frontend/build/web`.

The same pipeline can be run on macOS or Linux:

```shell
uv run --project backend python scripts/build_frontend.py
```

Verify an existing generated and served bundle without rebuilding:

```shell
uv run --project backend python scripts/verify_frontend_build.py
```

The verifier requires the two bundles to have identical file lists and SHA-256
hashes, and checks the Flutter and build metadata versions. Generated files
under `backend/static/web` remain tracked for now and must only be refreshed
through this pipeline.
