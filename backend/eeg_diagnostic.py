from __future__ import annotations

import argparse
import sys
import time

from config import AppSettings


def _parse_args() -> argparse.Namespace:
    settings = AppSettings.from_env(default_environment="production")
    parser = argparse.ArgumentParser(
        description="Connect to a BrainAccess sensor and validate EEG payloads"
    )
    parser.add_argument(
        "--device",
        default=settings.eeg_device_name,
        help="BrainAccess Bluetooth device name",
    )
    parser.add_argument(
        "--duration",
        type=float,
        default=5.0,
        help="Diagnostic duration in seconds",
    )
    return parser.parse_args()


def main() -> int:
    args = _parse_args()
    if sys.platform != "win32":
        print("BrainAccess diagnostics require Windows x64.", file=sys.stderr)
        return 2
    if args.duration <= 0:
        print("Duration must be greater than zero.", file=sys.stderr)
        return 2

    from eeg_stream import BrainAccessStream

    stream = BrainAccessStream(device_name=args.device)
    payload_count = 0
    deadline = time.monotonic() + args.duration
    try:
        print(f"Connecting to {args.device}...")
        stream.start()
        while time.monotonic() < deadline:
            payload = stream.build_payload()
            if payload is None:
                time.sleep(0.1)
                continue
            channels = payload.get("channels", [])
            raw_signal = payload.get("raw_signal", {})
            if not channels or not raw_signal:
                raise RuntimeError("EEG payload does not contain channel data")
            payload_count += 1
            time.sleep(0.1)
    except Exception as error:
        print(f"EEG diagnostic failed: {error}", file=sys.stderr)
        return 1
    finally:
        stream.close()

    if payload_count == 0:
        print("EEG diagnostic failed: no fresh samples received.", file=sys.stderr)
        return 1

    print(f"EEG diagnostic passed with {payload_count} payloads.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
