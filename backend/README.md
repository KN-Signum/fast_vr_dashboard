# Panel VR Backend

The backend is the authoritative runtime for device streams and sessions. It
hosts the compiled Flutter application, brokers WebSocket traffic between the
dashboard and Unity, reads the BrainAccess EEG stream, advertises itself through
UDP, persists session data, and exposes exports through REST.

Read [the architecture document](../docs/ARCHITECTURE.md) before changing
protocol or persistence behavior.

## Run

Install dependencies:

```shell
uv sync --all-groups
```

Run the development server with default mock EEG and ET:

```shell
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Run the production-style launcher:

```shell
uv run python launcher.py
```

Useful launcher options:

```shell
uv run python launcher.py --mock-eeg --mock-et
uv run python launcher.py --no-browser
uv run python launcher.py --port 8081
uv run python launcher.py --eeg-device "BA MINI 037"
uv run python launcher.py --data-dir ./local-data
```

The launcher detects another Panel VR instance, rejects an unrelated port
conflict, opens the browser after the health endpoint responds, and configures
rotating file logs.

## Runtime Configuration

Production defaults are real EEG, ET from the VR client, an enabled discovery
beacon, and automatic browser opening. Development defaults use mock EEG and ET.

| Variable | Values/default |
| --- | --- |
| `VRDASH_ENV` | `development`, `production`, or `test` |
| `VRDASH_HOST` | Bind address; default `0.0.0.0` |
| `VRDASH_PORT` | HTTP, WebSocket, and advertised port; default `8080` |
| `VRDASH_EEG_MODE` | `real`, `mock`, or `off` |
| `VRDASH_EEG_DEVICE` | Sensor BLE name; default `BA MINI 037` |
| `VRDASH_ET_MODE` | `vr`, `mock`, or `off` |
| `VRDASH_BEACON_ENABLED` | Boolean; production default `true` |
| `VRDASH_OPEN_BROWSER` | Boolean; production default `true` |
| `VRDASH_DATA_DIR` | Writable database, sessions, exports, and logs root |
| `VRDASH_STATIC_DIR` | Compiled Flutter web directory |
| `VRDASH_LOG_LEVEL` | `DEBUG`, `INFO`, `WARNING`, `ERROR`, or `CRITICAL` |
| `VRDASH_VERSION` | Version exposed by `/api/health` |
| `VRDASH_SUPABASE_URL` | Supabase project URL; optional |
| `VRDASH_SUPABASE_SERVICE_ROLE_KEY` | Backend-only service-role key; optional |
| `VRDASH_SUPABASE_BUCKET` | Existing private Storage bucket; optional |
| `BEACON_HOST` | Optional LAN address advertised instead of auto-detection |

Example real-device development run:

```shell
VRDASH_EEG_MODE=real \
VRDASH_ET_MODE=vr \
uv run uvicorn main:app --host 0.0.0.0 --port 8080
```

## Manual Supabase Upload

The session summary can manually upload the raw-data ZIP to Supabase Storage.
Create a private bucket and configure all three `VRDASH_SUPABASE_*` variables
before starting Panel VR. The backend uploads only the generated ZIP file to
the bucket root. It does not create a Supabase table or send a separate
metadata record.

For local development, copy `.env.example` to `.env` in the `backend`
directory and fill in the three values. The launcher reads this file without
overriding variables already defined by the operating system. In a packaged
installation, place `.env` beside the Panel VR executable. Never commit the
real `.env` file. Production build scripts copy this ignored file beside the
executable, and fail instead of creating a release without Supabase settings.

The service-role key is used only by the backend and must not be included in
the Flutter web build. If the integration is not configured, the manual upload
returns a clear configuration error and local downloads continue to work.

## Health and Diagnostics

`GET /api/health` reports configuration, EEG state/error, ET state/error,
beacon state, active session ID, and any persistence queue error.

Run the direct BrainAccess diagnostic on the target Windows computer:

```shell
uv run python eeg_diagnostic.py --device "BA MINI 037" --duration 10
```

Use the BrainAccess USB BLE adapter for the supported deployment. Close
BrainAccess Board first; only one process can own the sensor.

Logs are written to `logs/panel-vr.log` inside the application data directory.
The active file is limited to 5 MiB and five rotated backups are retained.

## Tests

```shell
uv run --group dev pytest
```

The suite covers configuration, paths, logging, EEG service/stream behavior,
session persistence/recovery, API endpoints, and WebSocket recording.

## Packaging

From the repository root:

```powershell
.\scripts\build_backend.ps1
```

The one-directory result is `dist\PanelVR`. `PanelVR.exe` depends on the
adjacent files and must not be moved out of that directory.

The PyInstaller specification is `panel_vr.spec`. It includes the compiled
Flutter bundle, Python dependencies, and BrainAccess native DLLs. Package
verification checks file hashes and architecture, and the smoke test runs the
frozen server in mock mode and exercises health, static files, sessions, and
exports.

See [Windows deployment](../docs/DEPLOYMENT.md) for the complete release
pipeline.
