# Panel VR Frontend

The frontend is a Polish-language Flutter web dashboard. It does not own
session data. It creates, updates, ends, and downloads backend sessions through
HTTP and uses WebSocket traffic only for live data and VR controls.

## Run

Start the backend on port `8080`, then:

```shell
flutter pub get
flutter run -d chrome --web-hostname 127.0.0.1 --web-port 5173
```

In Flutter debug mode the HTTP and WebSocket clients use `127.0.0.1:8080`.
When the compiled dashboard is served by FastAPI, they derive the backend from
the page origin and use same-origin `/api/...` and `/ws?role=dashboard`.

## Application Flow

`AppShell` registers live-data callbacks once, connects the dashboard to the
backend at startup, restores an active or interrupted session, and switches
between:

- `SessionSetupScreen`: patient metadata and connection activity;
- `HomeScreen`: controls, VR/ET preview, event timeline, and EEG plots;
- `SessionSummaryScreen`: metadata, counts, observations, and downloads.

Ending a session immediately stops and flushes recording, then opens a modal
for optional post-session notes. Notes entered before and after the session are
kept out of the patient card and included in the final PDF report.

For completed sessions, the summary shows a descriptive ET heatmap based on
valid normalized gaze projections, together with valid-data coverage and
horizontal, vertical, and 3-by-3 regional percentages. Mock ET includes a
moving projected gaze point so this view can be exercised without a headset.

State is separated into providers:

| Provider | Responsibility |
| --- | --- |
| `WebSocketProvider` | Connection, VR frames, message timestamps, EEG/ET callbacks |
| `GameProvider` | Unity state and available control actions |
| `EyeTrackingProvider` | ET parsing, freshness, visibility, and gaze projection |
| `EegProvider` | Per-channel 30-second raw and filtered display buffers |
| `SessionProvider` | REST-backed session lifecycle, events, summary, downloads |

Backend, EEG, VR, and ET indicators are activity indicators. Live data is
considered stale after three seconds.

The EEG panel retains 30 seconds per channel and always uses a display-only
1-40 Hz filter. Recorded `raw_signal` values are never replaced. Channel badges
warn about clipping,
flat data, and unusually high filtered amplitude. Creating a session starts the
30-second ERD baseline.

## Checks

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Build and mirror the verified release bundle from the repository root:

```shell
uv run --project backend python scripts/build_frontend.py
```

Do not manually copy individual files into `backend/static/web`; the script
performs an exact replacement and writes `build-info.json`.

For message formats and backend responsibilities, see
[the architecture document](../docs/ARCHITECTURE.md). For the complete local
workflow, see [the development guide](../docs/DEVELOPMENT.md).
