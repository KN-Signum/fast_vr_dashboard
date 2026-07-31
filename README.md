# Panel VR

Panel VR is a local research dashboard for supervised VR sessions. It combines:

- a FastAPI HTTP and WebSocket server;
- a Flutter web dashboard served by that server;
- live VR image and eye-tracking data from a Unity headset client;
- live raw EEG data from a BrainAccess MINI sensor;
- server-owned session recording, observations, summaries, and raw-data exports;
- a Windows x64 installer and portable package.

The production application runs on the operator's Windows computer and opens the
dashboard in a browser. The computer and headset communicate over the local
network. The client does not need Python, Flutter, or a terminal.

> Panel VR currently displays and records research signals. It is not a
> validated medical device and does not calculate diagnostic EEG metrics.

## Documentation

- [System architecture](docs/ARCHITECTURE.md): components, data flow,
  WebSocket messages, REST API, and storage.
- [Development guide](docs/DEVELOPMENT.md): local setup, commands, tests, and
  source layout.
- [Windows deployment and operation](docs/DEPLOYMENT.md): release builds,
  installation, hardware setup, acceptance checks, and troubleshooting.
- [Backend reference](backend/README.md): backend-specific configuration and
  commands.
- [Frontend reference](frontend/README.md): Flutter structure, connection
  behavior, and frontend checks.

## Production Topology

```text
BrainAccess MINI
       |
       | Bluetooth Low Energy through BrainAccess USB adapter
       v
+------------------------ Windows operator computer -------------------------+
| PanelVR.exe                                                               |
|   BrainAccess SDK -> EEG service ----+                                     |
|                                      |                                     |
|   FastAPI + WebSocket broker --------+----> Flutter dashboard in browser   |
|        ^                             |          - session controls          |
|        |                             +--------> - VR preview + ET overlay   |
|        |                                        - raw EEG plots            |
|        +---- UDP discovery + WebSocket ---- VR headset / Unity client      |
|                                                                            |
| Session database, NDJSON streams, exports, and logs in LOCALAPPDATA        |
+----------------------------------------------------------------------------+
```

The server listens on `0.0.0.0:8080`. The dashboard uses same-origin HTTP and
`/ws?role=dashboard`. The Unity client discovers the server from a UDP beacon on
port `15000` and connects to `/ws`, whose default role is `vr`.

## Operator Workflow

1. Connect the BrainAccess USB BLE adapter to the Windows computer.
2. Start the BrainAccess MINI and make sure it is not charging.
3. Put the operator computer and VR headset on the same private network.
4. Start **Panel VR**. The dashboard opens at `http://127.0.0.1:8080`.
5. Start the VR application. The headset should discover the server
   automatically.
6. On the setup screen, verify backend, EEG, VR, and ET activity. If the
   examination does not use EEG, turn it off with the switch in the EEG row;
   this stops device discovery and automatic reconnection attempts.
7. Enter the patient identifier, preferred hand, and optional notes, then create
   the session.
8. During the session, use the left-side controls, watch the VR/ET preview and
   EEG plots, and report observed events below the timeline.
9. End the session and download the PDF report and raw-data ZIP.

Only one session can be active at a time. If the application is stopped during a
session, the backend marks that session as `interrupted` on the next startup and
offers its recovered summary.

## Hardware

The tested EEG path is:

- BrainAccess MINI, default advertised name `BA MINI 037`;
- BrainAccess USB BLE adapter;
- Windows x64;
- Microsoft Visual C++ Redistributable x64 required by the BrainAccess DLLs.

Use the supplied USB adapter for production sessions. The previously observed
short or stalled streams disappeared after replacing an older integrated laptop
Bluetooth adapter. When a computer has both adapters, disable the integrated
Bluetooth adapter if device selection is inconsistent. Close BrainAccess Board
before starting Panel VR because the sensor connection is exclusive.

## Quick Development Start

Requirements:

- Python 3.13 and [uv](https://docs.astral.sh/uv/);
- Flutter 3.41.2 or another compatible stable release;
- Chrome or another Flutter-supported browser.

Start the backend from one terminal:


```shell
cd backend
uv sync --all-groups
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Development mode uses mock EEG and mock eye tracking by default. Start Flutter
from another terminal:

```shell
cd frontend
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173
```

A Flutter debug build always calls the backend at `http://127.0.0.1:8080` and
`ws://127.0.0.1:8080/ws?role=dashboard`.

Run the main checks:

```shell
cd backend
uv run --group dev pytest
```

```shell
cd frontend
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

See [the development guide](docs/DEVELOPMENT.md) for real-device modes,
generated frontend assets, protocol changes, and packaging checks.

## Data and Privacy

Session data is stored outside the installation directory:

| Platform | Default directory                               |
| -------- | ----------------------------------------------- |
| Windows  | `%LOCALAPPDATA%\NEXT\PanelVR`                   |
| macOS    | `~/Library/Application Support/NEXT/PanelVR`    |
| Linux    | `${XDG_DATA_HOME:-~/.local/share}/next/panelvr` |

The directory contains:

```text
logs/panel-vr.log
sessions.sqlite3
sessions/<session_id>/session.json
sessions/<session_id>/eeg.ndjson
sessions/<session_id>/eye_tracking.ndjson
sessions/<session_id>/vr_events.ndjson
sessions/<session_id>/vr_frames.ndjson
sessions/<session_id>/session_events.ndjson
exports/
```

Patient identifiers and notes are stored unencrypted. Access control, backups,
retention, secure transfer, and deletion are deployment responsibilities.
Uninstalling the Windows application does not remove this data.

## Windows Release

The final build must be produced on Windows x64. The release pipeline compiles
Flutter, tests both applications, freezes the backend with PyInstaller, performs
a packaged-server smoke test, builds an Inno Setup installer, and creates a
portable ZIP and SHA-256 checksums.

Local Windows build:

```powershell
.\scripts\build_release.ps1 -ConfirmBrainAccessRedistribution
```

GitHub Actions build:

1. Open **Actions** in GitHub.
2. Select **Build Windows Release**.
3. Select **Run workflow** on the intended branch.
4. Confirm BrainAccess redistribution and choose whether to sign the build.
5. Download `PanelVR-<version>-windows-x64` from the completed run.

BrainAccess DLL redistribution rights must be reviewed before every delivered
release. Unsigned builds are suitable for controlled testing but may trigger
Microsoft Defender SmartScreen. Full prerequisites and acceptance checks are in
[the deployment guide](docs/DEPLOYMENT.md).

## Versioning

The release version must match in:

- `VERSION`;
- `backend/pyproject.toml`;
- `frontend/pubspec.yaml` (before the `+` build number).

Build scripts reject mismatches. Generated Flutter files in
`backend/static/web` are tracked and must be refreshed with the repository build
script rather than copied manually.
