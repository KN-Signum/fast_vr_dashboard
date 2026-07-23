## Development

Run the backend from this directory:

```shell
uv run uvicorn main:app --host 0.0.0.0 --port 8080 --reload
```

Development mode uses mock EEG and eye-tracking streams by default. The
dashboard is served from `static/web`.

## Runtime configuration

The packaged launcher uses production defaults: real EEG, eye tracking from
the VR client, the UDP beacon enabled, and automatic browser startup.

Supported environment variables:

- `VRDASH_ENV`: `development`, `production`, or `test`
- `VRDASH_HOST`: server bind address, default `0.0.0.0`
- `VRDASH_PORT`: HTTP, WebSocket, and advertised port, default `8080`
- `VRDASH_EEG_MODE`: `real`, `mock`, or `off`
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
```

The launcher detects an existing Panel VR instance, reports port conflicts,
opens the dashboard when the server is ready, and writes rotating logs below
the application data directory.

## Tests

Stage-one tests use only the Python standard library:

```shell
uv run python -m unittest discover -s tests -v
```
