## Development

Run the backend from this directory:

```shell
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Development mode uses mock EEG and eye-tracking streams by default. The
dashboard is served from `static/web`.

The served dashboard is generated from the Flutter project. From the repository
root, refresh it with:

```shell
uv run --project backend python scripts/build_frontend.py
```

Do not copy individual Flutter artifacts into `static/web`; the build script
uses an exact verified mirror so stale files are removed.

## Runtime configuration

The packaged launcher uses production defaults: real EEG, eye tracking from
the VR client, the UDP beacon enabled, and automatic browser startup.

Supported environment variables:

- `VRDASH_ENV`: `development`, `production`, or `test`
- `VRDASH_HOST`: server bind address, default `0.0.0.0`
- `VRDASH_PORT`: HTTP, WebSocket, and advertised port, default `8080`
- `VRDASH_EEG_MODE`: `real`, `mock`, or `off`
- `VRDASH_EEG_DEVICE`: BrainAccess Bluetooth name, default `BA MINI 037`
- `VRDASH_ET_MODE`: `vr`, `mock`, or `off`
- `VRDASH_BEACON_ENABLED`: boolean
- `VRDASH_OPEN_BROWSER`: boolean
- `VRDASH_DATA_DIR`: writable application data directory
- `VRDASH_STATIC_DIR`: compiled Flutter web directory
- `VRDASH_LOG_LEVEL`: Python logging level
- `VRDASH_VERSION`: release version shown by the health endpoint

The runtime health endpoint is available at `GET /api/health`.

## Launcher

Run the production-style launcher from this directory:

```shell
uv run python launcher.py
```

Useful development options:

```shell
uv run python launcher.py --mock-eeg --mock-et
uv run python launcher.py --no-browser
uv run python launcher.py --eeg-device "BA MINI 037"
```

The launcher detects an existing Panel VR instance, reports port conflicts,
opens the dashboard when the server is ready, and writes rotating logs below
the application data directory.

## BrainAccess EEG

The real EEG service is loaded lazily and is supported by the vendored SDK on
Windows x64. A missing sensor or Bluetooth error changes `eeg_status` to
`error` without stopping the dashboard.

Run the hardware diagnostic on the target Windows computer before packaging:

```shell
uv run python eeg_diagnostic.py --device "BA MINI 037" --duration 10
```

The target computer needs the Microsoft Visual C++ x64 runtime required by
`bacore.dll` and `simpleble.dll`. Confirm that the BrainAccess SDK licence
permits redistribution of these DLLs before delivering the installer.

## Tests

Run the backend test suite with:

```shell
uv run python -m unittest discover -s tests -v
```

Install all development and packaging dependencies with:

```shell
uv sync --all-groups
```
