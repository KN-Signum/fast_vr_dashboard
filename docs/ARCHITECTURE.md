# System Architecture

## Scope

Panel VR is a local, single-operator application for observing and recording a
supervised VR session. The backend is the source of truth for session lifecycle
and data persistence. The browser dashboard is a live control and visualization
client. The Unity application is the source of VR frames, VR state, and
eye-tracking data. The BrainAccess sensor is read directly by the backend.

The current design permits one active session at a time and assumes that all
components are on a trusted local computer or private local network.

## Components

### FastAPI Runtime

`backend/main.py` creates and coordinates:

- the static Flutter web host;
- the REST API;
- the WebSocket broker;
- the BrainAccess EEG service;
- optional mock EEG and ET streams;
- the UDP discovery beacon;
- the session repository and asynchronous writer.

Startup is intentionally tolerant of optional-device failures. An EEG or
beacon error is exposed through `/api/health` and logs without taking down the
dashboard.

### Flutter Dashboard

The browser application under `frontend/` uses Provider for state management.
`AppShell` owns the top-level lifecycle and chooses the setup, live, or summary
screen according to `SessionProvider`.

The live screen has three primary areas:

- left: backend/device state, Unity scene controls, and end-session action;
- center: VR JPEG preview, optional ET point, timeline, and event reporting;
- right: independent rolling raw EEG plots for each channel.

### Unity VR Client

The Unity client connects as a WebSocket peer. It:

- receives dashboard commands;
- sends state updates and action results as JSON;
- sends VR preview frames as binary JPEG packets;
- sends `eye_tracking` JSON with world-space and normalized screen data.

The Unity project is maintained separately from this repository. Its
`UnityNetworkClient.cs` and eye-tracking streamer must follow the contracts
below.

### BrainAccess EEG

`backend/eeg_stream.py` wraps the vendored BrainAccess Python SDK and native
Windows DLLs. The current stream:

- connects to the configured BLE device;
- acquires `F3`, `F4`, `C3`, `C4`, `P3`, `P4`, `O1`, and `O2` at 250 Hz;
- enables all eight measurement channels as bias-feedback contributors;
- copies callback chunks into a thread-safe buffer;
- broadcasts each fresh chunk as raw microvolt values;
- detects missing callbacks and lets the service reconnect.

Alpha power and ERD use non-overlapping one-second windows in the 8-13 Hz band.
Creating a session starts a baseline made from 30 accepted one-second windows.
Clipped, flat, or otherwise implausible windows are excluded, so collecting the
baseline can take longer than 30 wall-clock seconds. ERD is emitted after that
baseline is ready; `focus_index` remains `0.0`.

### Session Storage

`SessionService` accepts stream records without blocking WebSocket delivery. It
places records in a bounded queue and writes batches through
`SessionRepository`. SQLite stores session metadata and counters; append-only
NDJSON files store raw records.

## Runtime Data Flow

```text
BrainAccess sensor
  -> BrainAccess SDK callback
  -> BrainAccessStream raw EEG payload
  -> ConnectionManager
  -> SessionService queue (only while a session is active)
  -> all WebSocket peers, including dashboard

Unity headset
  -> UDP beacon discovery
  -> WebSocket /ws (role=vr by default)
  -> JSON or JPEG binary
  -> ConnectionManager
  -> SessionService queue (only while active)
  -> dashboard

Flutter dashboard
  -> REST /api/sessions/... for lifecycle, observations, and exports
  -> WebSocket /ws?role=dashboard for live data and Unity commands
```

`ConnectionManager` broadcasts an incoming message to every peer except its
sender. Recording observers receive the sender role:

- backend `eeg_data` is recorded as EEG;
- any `eye_tracking` message is recorded as ET;
- other JSON from a non-dashboard source is recorded as a VR event;
- binary data from a non-dashboard source is recorded as VR frame metadata;
- dashboard control JSON is relayed but not persisted as a VR event.

## Network Contracts

### Server Addresses

| Interface | Default |
| --- | --- |
| Dashboard HTTP | `http://127.0.0.1:8080` |
| WebSocket | `ws://<server-lan-ip>:8080/ws` |
| Dashboard WebSocket | `/ws?role=dashboard` |
| UDP discovery broadcast | `255.255.255.255:15000` once per second |

The discovery payload is:

```json
{
  "service": "hrv-biofeedback",
  "ws_url": "ws://192.168.1.20:8080/ws"
}
```

`BEACON_HOST` can override automatic LAN address detection.

### WebSocket Roles

The optional `role` query parameter accepts `dashboard`, `vr`, or `unknown`.
Omitting it selects `vr`. New clients should always identify their role
explicitly where practical.

### EEG Message

```json
{
  "type": "eeg_data",
  "sampling_rate": 250,
  "channels": ["F3", "F4", "C3", "C4", "P3", "P4", "O1", "O2"],
  "raw_signal": {
    "F3": [12.3, 12.6],
    "F4": [8.1, 8.0],
    "C3": [2.1, 2.0],
    "C4": [1.8, 1.9],
    "P3": [-1.2, -1.0],
    "P4": [-2.2, -2.0],
    "O1": [-3.2, -3.0],
    "O2": [-4.1, -4.3]
  },
  "data_uv": [12.6, 8.0, 2.0, 1.9, -1.0, -2.0, -3.0, -4.3],
  "band_power": {"alpha": [1.0, 1.1, 0.9, 1.2, 1.0, 0.8, 1.3, 1.4]},
  "erd": {"alpha": [2.0, -1.0, 4.0, 3.0, 1.0, 5.0, -2.0, 2.0]},
  "erd_conventional": {
    "alpha": [4.1, -2.0, 8.3, 6.2, 2.0, 10.5, -3.9, 4.1]
  },
  "erd_status": "ready",
  "erd_baseline_seconds": 30,
  "erd_baseline_target_seconds": 30,
  "focus_index": 0.0,
  "sequence": 10,
  "sample_start": 500,
  "sample_count": 2,
  "timestamp_ms": 1785400000000
}
```

`raw_signal` is the canonical plotted and exported signal. `sample_start` is a
monotonic sample cursor within the current sensor connection, and
`sample_count` is the number of values per channel in this message.
Before a session, `erd_status` is `waiting`. During baseline collection it is
`collecting`, the elapsed seconds increase to 30, and `band_power`/`erd` remain
empty. Only finite, non-flat, non-clipped windows below the artifact threshold
advance the baseline. The baseline is the median of 30 accepted one-second
windows. Current alpha power is the median of the latest five accepted windows.

`erd.alpha` is the bounded normalized alpha-power change used by the dashboard:

```text
100 * (baseline - current) / (baseline + current)
```

It remains between `-100%` and `+100%`. `erd_conventional.alpha` preserves the
standard, unbounded percentage:

```text
100 * (baseline - current) / baseline
```

Raw EEG remains unchanged regardless of whether a window is accepted for the
alpha calculation.

### Eye-Tracking Message

The dashboard expects:

```json
{
  "type": "eye_tracking",
  "player_position": {"x": 0.0, "y": 1.6, "z": 0.0},
  "eyes_position": {"x": 0.0, "y": 1.65, "z": 0.05},
  "eyes_transform": {
    "x_axis": {"x": 1.0, "y": 0.0, "z": 0.0},
    "y_axis": {"x": 0.0, "y": 1.0, "z": 0.0},
    "z_axis": {"x": 0.0, "y": 0.0, "z": 1.0},
    "origin": {"x": 0.0, "y": 1.65, "z": 0.05}
  },
  "gaze_screen_x": 0.52,
  "gaze_screen_y": 0.61
}
```

`gaze_screen_x` and `gaze_screen_y` are optional but must be finite normalized
coordinates in `[0, 1]`. The dashboard maps X directly and flips Y for Flutter
canvas coordinates. If the headset cannot project gaze into the streamed
camera image, it should omit these fields instead of clamping an invalid point
to an edge.

In production, `VRDASH_ET_MODE=vr` means the backend waits for Unity ET
messages. It does not open a separate ET device connection.

### VR Binary Frames

The dashboard accepts:

- a standard JPEG whose first byte is `0xFF`; or
- a JPEG prefixed by one custom byte `0x01`.

The dashboard removes `0x01` before decoding. During a session, the backend
stores only `received_at` and `byte_length`, not the JPEG bytes. This keeps
recordings bounded while preserving frame timing and volume statistics.

### Unity State and Commands

The dashboard sends this immediately after connecting:

```json
{"type": "command", "action": "request_state"}
```

Unity describes the current controls with:

```json
{
  "type": "state_update",
  "current_view": "painting",
  "available_actions": [
    {"action": "clear_palette", "label": "Wyczysc"}
  ]
}
```

The dashboard relays selected actions as command JSON. Unity may answer with
`action_completed`. A `canvas_image` message, or an action result containing
`image_base64`, can trigger a browser download.

## REST API

### Health

`GET /api/health`

Returns application/version/environment, configured EEG and ET modes, device
name, subsystem status/errors, beacon state, active session ID, and session
writer error.

### Create a Session

`POST /api/sessions`

```json
{
  "patient_id": "P-001",
  "preferred_hand": "right",
  "notes": "Optional session notes"
}
```

`patient_id` is required. `preferred_hand` is one of `not_specified`, `left`,
`right`, or `ambidextrous`. A second active session returns HTTP `409`.

### Read Session State

- `GET /api/sessions/active`
- `GET /api/sessions/recovered`
- `GET /api/sessions/{session_id}/summary`

The recovered endpoint returns an interrupted session once so the dashboard can
show its summary after an unexpected stop.

### Add an Observation

`POST /api/sessions/{session_id}/events`

```json
{
  "label": "Dyskomfort",
  "category": "patient_behavior",
  "note": "Optional detail"
}
```

The backend supplies `occurred_at`, elapsed milliseconds from session start,
and source. Events may only be added to the active session.

### End and Export

- `POST /api/sessions/{session_id}/end`
- `GET /api/sessions/{session_id}/download/summary`
- `GET /api/sessions/{session_id}/download/raw`

Ending or exporting the active session first drains pending writes. The summary
download is JSON. Raw download is a ZIP containing the summary and all NDJSON
streams.

## Session Lifecycle and Recovery

Session states are:

- `active`: receives stream records and observations;
- `completed`: ended by the operator;
- `interrupted`: finalized during graceful shutdown or recovered after an
  unexpected stop.

At startup, any stale `active` row is changed to `interrupted`. Counts are
reconciled against NDJSON files so a shutdown between append and SQLite counter
update does not lose summary accuracy.

The write queue holds up to 10,000 records and writes batches of up to 256. If
the queue fills or a batch fails, the loss is reflected by `dropped_records`,
and the live error is exposed as `session_recording_error`.

## Stored Data

SQLite stores session identity, timestamps, state, duration, per-stream counts,
event rows, dropped-record count, and recovery flags.

Each NDJSON line is an independent JSON object:

- EEG/ET/VR JSON: `{"payload": {...}, "received_at": "..."}`
- frame metadata: `{"byte_length": 12345, "received_at": "..."}`
- clinician event: event identity, label, category, note, absolute timestamp,
  elapsed time, and source.

Summary shape:

```json
{
  "session_id": "uuid",
  "patient_id": "P-001",
  "preferred_hand": "right",
  "notes": "",
  "status": "completed",
  "started_at": "2026-07-30T10:00:00Z",
  "ended_at": "2026-07-30T10:10:00Z",
  "duration_seconds": 600.0,
  "counts": {
    "eeg_records": 1000,
    "eye_tracking_records": 8000,
    "vr_events": 12,
    "vr_frames": 9000,
    "session_events": 3
  },
  "dropped_records": 0,
  "session_events": []
}
```

Timestamps are generated by the backend in UTC for persistence. Device payloads
may also contain source timestamps; `received_at` remains the authoritative
arrival time.

## Security Boundaries

The API currently has no authentication or transport encryption and CORS allows
all origins. This is appropriate only for a controlled private network. Do not
expose port `8080` or the UDP beacon to the public internet.

Patient identifiers, notes, and signals are stored without application-level
encryption. Operating-system account controls and the deployment's data
governance policy must protect the application data directory.
