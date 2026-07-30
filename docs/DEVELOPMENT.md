# Development Guide

## Prerequisites

Common:

- Git;
- Python 3.13;
- uv;
- Flutter stable compatible with the pinned CI version (`3.41.2`);
- Dart supplied with Flutter;
- Chrome for Flutter web development.

Windows real EEG:

- Windows x64;
- BrainAccess MINI and BrainAccess USB BLE adapter;
- Microsoft Visual C++ Redistributable x64;
- vendored BrainAccess DLLs under `backend/brainaccess/lib`.

Release-only:

- Inno Setup 6;
- Windows 10 SDK `signtool.exe` when Authenticode signing is enabled.

## Repository Layout

```text
backend/
  main.py                    FastAPI application and API routes
  launcher.py                production entry point
  connection_manager.py      WebSocket peer registry and broadcast
  beacon_manager.py          UDP headset discovery
  eeg_service.py             mode, retry, and stream lifecycle
  eeg_stream.py              BrainAccess callback adapter
  eeg_payload.py             EEG WebSocket schema
  session_service.py         async recording queue and lifecycle
  session_repository.py      SQLite, NDJSON, recovery, exports
  brainaccess/               vendored SDK and native libraries
  static/web/                generated Flutter release served by FastAPI
  tests/
frontend/
  lib/providers/             application state
  lib/screens/               setup, live, and summary screens
  lib/services/              REST client
  lib/widgets/               controls, preview, ET, timeline, EEG
  test/
installer/                   Inno Setup definition and client readme
scripts/                     build, verification, smoke, and release tooling
docs/                        project documentation
```

## First Setup

Backend:

```shell
cd backend
uv sync --all-groups
```

Frontend:

```shell
cd frontend
flutter pub get
```

## Development Modes

### Two-Process UI Development

Terminal 1:

```shell
cd backend
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Terminal 2:

```shell
cd frontend
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173
```

This is the fastest frontend loop. Flutter debug uses the backend on
`127.0.0.1:8080` regardless of the browser's development origin.

### Integrated Served Dashboard

Build and mirror Flutter into the backend:

```shell
uv run --project backend python scripts/build_frontend.py
```

Then:

```shell
cd backend
uv run python launcher.py --mock-eeg --mock-et
```

Open `http://127.0.0.1:8080`. This verifies same-origin behavior used by the
packaged product.

### Real EEG and VR Eye Tracking

On Windows:

```powershell
$env:VRDASH_EEG_MODE = "real"
$env:VRDASH_ET_MODE = "vr"
uv run --project backend python backend\launcher.py --no-browser
```

Use the BrainAccess USB BLE adapter. Stop BrainAccess Board and any other
program connected to the sensor before starting the backend.

### Disable Optional Streams

```shell
VRDASH_EEG_MODE=off VRDASH_ET_MODE=off \
uv run --project backend python backend/launcher.py
```

## Quality Gates

Backend:

```shell
cd backend
uv run --group dev pytest
```

Frontend:

```shell
cd frontend
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

All checks plus a Flutter release build, PyInstaller package, file verification,
and packaged-server smoke test on Windows:

```powershell
.\scripts\build_all.ps1
```

`-SkipFrontendChecks` and `-SkipPackageSmoke` exist for local iteration, not
release acceptance.

## Frontend Release Assets

Run:

```shell
uv run --project backend python scripts/build_frontend.py
```

The script:

1. validates `VERSION`, backend version, and Flutter version;
2. resolves Flutter dependencies;
3. runs format, analysis, and tests unless explicitly skipped;
4. runs `flutter build web --release`;
5. writes `build-info.json` with version, build number, commit, worktree state,
   and UTC build time;
6. atomically mirrors the exact build into `backend/static/web`;
7. verifies file lists and SHA-256 hashes.

Verify existing assets without rebuilding:

```shell
uv run --project backend python scripts/verify_frontend_build.py
```

Generated files are tracked. Commit the complete generated update together with
its source change. Never copy only `main.dart.js`; stale service-worker or asset
files can otherwise serve a mixed release.

## Changing WebSocket Messages

1. Define ownership: backend-generated, Unity-generated, or dashboard command.
2. Keep a top-level JSON `type`.
3. Update the sender and every receiver in the same change.
4. Decide how the active session records the message.
5. Update [the architecture contract](ARCHITECTURE.md).
6. Add parser/provider and backend recording tests.
7. Test with mock data before using hardware.

Do not repurpose an existing field with a new unit. EEG `raw_signal` is in
microvolts, gaze screen coordinates are normalized, and persisted
`received_at` is UTC.

The dashboard role is essential. A dashboard command accidentally connected as
`vr` would be stored as a VR event. Use `/ws?role=dashboard`.

## Changing Session Data

Session metadata and raw files are a cross-version contract:

1. add any schema migration in `SessionRepository.initialize`;
2. preserve existing sessions and interrupted-session recovery;
3. keep NDJSON lines independently parseable;
4. update summary and archive generation;
5. update API/provider models;
6. add repository, service, endpoint, and frontend tests;
7. document the new field.

Avoid synchronous disk writes in the WebSocket receive loop. Stream records
must continue through `SessionService`.

## EEG Development

Test the SDK independently on the target Windows machine:

```powershell
cd backend
uv run python eeg_diagnostic.py --device "BA MINI 037" --duration 10
```

Then inspect:

- a sustained callback stream for the full duration;
- increasing sequence and sample positions;
- nonconstant values for all four channels;
- backend `/api/health` showing `eeg_status: streaming`;
- live frontend plots;
- `eeg.ndjson` growing during an active session.

The current implementation forwards raw values. Add signal processing only
with explicit algorithms, units, windowing, validation, and tests. Do not
populate placeholder metrics with plausible-looking values.

## Debugging

Health:

```shell
curl http://127.0.0.1:8080/api/health
```

Application log:

- Windows: `%LOCALAPPDATA%\NEXT\PanelVR\logs\panel-vr.log`
- macOS: `~/Library/Application Support/NEXT/PanelVR/logs/panel-vr.log`

Increase logs:

```shell
VRDASH_LOG_LEVEL=DEBUG uv run --project backend python backend/launcher.py
```

Use browser developer tools for Flutter HTTP/WebSocket failures. For Unity on
an Android headset, use `adb logcat`; filter on the development computer with
available shell tools rather than assuming utilities are installed in the
Android shell.

## Version Changes

Update:

1. `VERSION`;
2. `backend/pyproject.toml` project version;
3. `frontend/pubspec.yaml` version while choosing an incremented Flutter build
   number after `+`.

Regenerate the frontend bundle, run both suites, and build the Windows artifact.

## Git Hygiene

Release scripts require a clean worktree unless `-AllowDirty` is explicitly
used. A production artifact should identify a committed source revision and
have `git_dirty: false` in build and package manifests.
