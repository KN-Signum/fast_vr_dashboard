#!/usr/bin/env python3
"""Build, annotate, verify, and mirror the Flutter web release."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import UTC, datetime
from pathlib import Path

from verify_frontend_build import (
    VerificationError,
    verify_build_directory,
    verify_exact_copy,
    verify_frontend_build,
    verify_source_versions,
)


ROOT = Path(__file__).resolve().parents[1]
FRONTEND = ROOT / "frontend"
BUILD_DIRECTORY = FRONTEND / "build" / "web"
SERVED_DIRECTORY = ROOT / "backend" / "static" / "web"


def run(command: list[str], *, cwd: Path) -> None:
    print(f"+ {' '.join(command)}", flush=True)
    subprocess.run(command, cwd=cwd, check=True)


def require_command(command: str) -> str:
    resolved = shutil.which(command)
    if resolved is None:
        raise RuntimeError(f"Required command is not available on PATH: {command}")
    return resolved


def git_output(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def write_build_info(version: str, build_number: str) -> None:
    commit = git_output("rev-parse", "HEAD")
    dirty = bool(git_output("status", "--porcelain", "--untracked-files=normal"))
    build_info = {
        "app_version": version,
        "build_number": build_number,
        "git_commit": commit,
        "git_dirty": dirty,
        "built_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    }
    (BUILD_DIRECTORY / "build-info.json").write_text(
        json.dumps(build_info, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )


def mirror_build() -> None:
    SERVED_DIRECTORY.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(
        tempfile.mkdtemp(prefix=".web-staging-", dir=SERVED_DIRECTORY.parent)
    )
    backup: Path | None = None
    try:
        shutil.copytree(BUILD_DIRECTORY, staging, dirs_exist_ok=True)
        verify_exact_copy(BUILD_DIRECTORY, staging)

        if SERVED_DIRECTORY.exists():
            backup = SERVED_DIRECTORY.with_name(
                f".web-backup-{os.getpid()}-{datetime.now(UTC).timestamp():.0f}"
            )
            SERVED_DIRECTORY.rename(backup)
        staging.rename(SERVED_DIRECTORY)

        try:
            verify_exact_copy(BUILD_DIRECTORY, SERVED_DIRECTORY)
        except Exception:
            shutil.rmtree(SERVED_DIRECTORY, ignore_errors=True)
            if backup is not None:
                backup.rename(SERVED_DIRECTORY)
            raise

        if backup is not None:
            shutil.rmtree(backup)
    finally:
        shutil.rmtree(staging, ignore_errors=True)
        if backup is not None and backup.exists():
            if not SERVED_DIRECTORY.exists():
                backup.rename(SERVED_DIRECTORY)
            else:
                shutil.rmtree(backup)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-checks",
        action="store_true",
        help="Skip format, analyzer, and test gates; intended only for local iteration.",
    )
    args = parser.parse_args()

    try:
        flutter = require_command("flutter")
        dart = require_command("dart")
        require_command("git")
        version, build_number = verify_source_versions(ROOT)

        run([flutter, "pub", "get"], cwd=FRONTEND)
        if not args.skip_checks:
            run(
                [
                    dart,
                    "format",
                    "--output=none",
                    "--set-exit-if-changed",
                    "lib",
                    "test",
                ],
                cwd=FRONTEND,
            )
            run([flutter, "analyze"], cwd=FRONTEND)
            run([flutter, "test"], cwd=FRONTEND)

        run([flutter, "build", "web", "--release"], cwd=FRONTEND)
        write_build_info(version, build_number)
        verify_build_directory(
            BUILD_DIRECTORY,
            expected_version=version,
            expected_build_number=build_number,
        )
        mirror_build()
        verify_frontend_build(BUILD_DIRECTORY, SERVED_DIRECTORY, ROOT)
    except (
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        VerificationError,
    ) as exc:
        print(f"Frontend release build failed: {exc}", file=sys.stderr)
        return 1

    print(f"Frontend {version}+{build_number} is ready in {SERVED_DIRECTORY}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
