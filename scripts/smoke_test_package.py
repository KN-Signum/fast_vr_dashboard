#!/usr/bin/env python3
"""Start the frozen Panel VR server and validate its HTTP runtime."""

from __future__ import annotations

import argparse
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

from verify_backend_package import DEFAULT_PACKAGE, find_executable
from verify_frontend_build import read_release_version


def available_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


def get_json(url: str, *, timeout: float = 1.0) -> dict:
    with urllib.request.urlopen(url, timeout=timeout) as response:
        value = json.load(response)
    if not isinstance(value, dict):
        raise RuntimeError(f"Expected a JSON object from {url}")
    return value


def wait_for_health(port: int, process: subprocess.Popen, timeout: float) -> dict:
    url = f"http://127.0.0.1:{port}/api/health"
    deadline = time.monotonic() + timeout
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(
                f"Packaged server exited early with code {process.returncode}"
            )
        try:
            return get_json(url)
        except (OSError, ValueError, urllib.error.URLError) as exc:
            last_error = exc
            time.sleep(0.2)
    raise RuntimeError(f"Packaged server did not become healthy: {last_error}")


def smoke_test(package_dir: Path, *, timeout: float = 45.0) -> None:
    executable = find_executable(package_dir)
    port = available_port()
    version = read_release_version()
    with tempfile.TemporaryDirectory(prefix="panel-vr-smoke-") as data_dir:
        environment = os.environ.copy()
        environment["VRDASH_BEACON_ENABLED"] = "false"
        process = subprocess.Popen(
            [
                str(executable),
                "--port",
                str(port),
                "--data-dir",
                data_dir,
                "--mock-eeg",
                "--mock-et",
                "--no-browser",
            ],
            cwd=package_dir,
            env=environment,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        try:
            health = wait_for_health(port, process, timeout)
            if health.get("application") != "panel-vr":
                raise RuntimeError(f"Unexpected health response: {health}")
            if health.get("version") != version:
                raise RuntimeError(
                    f"Packaged server reports version {health.get('version')!r}, "
                    f"expected {version!r}"
                )
            if health.get("eeg_mode") != "mock" or health.get("et_mode") != "mock":
                raise RuntimeError(f"Mock modes were not applied: {health}")

            with urllib.request.urlopen(
                f"http://127.0.0.1:{port}/",
                timeout=2.0,
            ) as response:
                index = response.read()
            if b"flutter_bootstrap.js" not in index:
                raise RuntimeError("Packaged server did not serve the Flutter index")
        except Exception:
            process.terminate()
            output, _ = process.communicate(timeout=10)
            if output:
                print(output, file=sys.stderr)
            raise
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument("--timeout", type=float, default=45.0)
    args = parser.parse_args()
    try:
        smoke_test(args.package.resolve(), timeout=args.timeout)
    except (OSError, RuntimeError, subprocess.SubprocessError) as exc:
        print(f"Packaged backend smoke test failed: {exc}", file=sys.stderr)
        return 1
    print(f"Packaged backend smoke test passed: {args.package.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
