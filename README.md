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

## Session recording

FastAPI is the authoritative owner of sessions. The Flutter dashboard creates
and ends sessions through `/api/sessions`, adds observed events through the
session API, and uses WebSocket data only for the live view. The backend records
EEG, eye-tracking, VR JSON messages, and VR frame metadata while a session is
active.

Session metadata and counts are stored in SQLite. Raw streams are appended to
NDJSON files under the writable application data directory. Ending a session
flushes pending records before the summary is returned. If the application
stops with an active session, that session is marked as interrupted on the next
startup, its counters are reconciled with the raw files, and it is shown in the
dashboard summary.

The summary download is JSON. The raw-data download is a ZIP containing the
summary plus separate NDJSON files for EEG, eye tracking, VR events, VR frame
metadata, and clinician observations.

## Frontend release build

The release version is stored in `VERSION`. The same version must be present in
`frontend/pubspec.yaml` and `backend/pyproject.toml`; the verifier rejects a
mismatch.

On Windows, run the frontend gate, backend tests, PyInstaller build, package
verification, and packaged-server smoke test:

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

## Backend package

Build only the backend package on Windows:

```powershell
.\scripts\build_backend.ps1
```

The output is a one-directory package under `dist\PanelVR`. It contains the
`PanelVR.exe` launcher, the Flutter bundle, Python runtime dependencies, and the
BrainAccess native DLLs. Keep this directory intact; the executable is not
standalone outside it.

The package build writes `package-manifest.json` with release metadata and the
SHA-256 hash of every packaged file. It then starts the frozen application with
mock EEG and eye tracking, checks `/api/health`, verifies that Flutter is
served, and exercises session creation, completion, and both export formats.
File verification and the smoke test can also be run independently:

```powershell
uv run --project backend --group package python scripts\verify_backend_package.py
uv run --project backend --group package python scripts\smoke_test_package.py
```

PyInstaller builds are platform-specific. A macOS build validates packaging
logic locally but cannot replace the final Windows x64 build or physical
BrainAccess hardware test.

## Windows client release

The final Windows command builds and tests the frontend and backend, packages
the server, compiles the installer, creates a portable ZIP, and publishes
SHA-256 checksums:

```powershell
.\scripts\build_release.ps1 -ConfirmBrainAccessRedistribution
```

Install Inno Setup 6.3 or newer on the build machine before running it. The
command refuses to build from a dirty worktree unless `-AllowDirty` is
explicitly supplied. The BrainAccess confirmation switch is mandatory because
redistribution rights must be reviewed outside the codebase.

For Authenticode signing, install the Windows 10 SDK and provide the SHA-1
certificate thumbprint:

```powershell
.\scripts\build_release.ps1 `
  -ConfirmBrainAccessRedistribution `
  -CertificateThumbprint "CERTIFICATE_SHA1_THUMBPRINT"
```

Unsigned builds are supported for internal testing but may trigger Microsoft
Defender SmartScreen. Final artifacts are written below `release\<version>`.
Follow [WINDOWS_RELEASE_CHECKLIST.md](WINDOWS_RELEASE_CHECKLIST.md) for clean
machine and hardware acceptance testing.
