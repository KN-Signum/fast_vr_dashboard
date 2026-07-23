#!/usr/bin/env python3
"""Refresh and verify package metadata after optional executable signing."""

from __future__ import annotations

import argparse
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

from verify_backend_package import (
    DEFAULT_PACKAGE,
    verify_backend_package,
    write_package_manifest,
)
from verify_frontend_build import read_release_version


ROOT = Path(__file__).resolve().parents[1]
GENERATED_PATH_PREFIXES = ("backend/static/web/",)


def git_output(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def source_worktree_dirty() -> bool:
    status = git_output("status", "--porcelain", "--untracked-files=normal")
    for line in status.splitlines():
        path = line[3:].strip().strip('"')
        if " -> " in path:
            path = path.rsplit(" -> ", maxsplit=1)[1].strip('"')
        if not any(path.startswith(prefix) for prefix in GENERATED_PATH_PREFIXES):
            return True
    return False


def finalize_package(package_dir: Path = DEFAULT_PACKAGE) -> None:
    write_package_manifest(
        package_dir,
        app_version=read_release_version(ROOT),
        git_commit=git_output("rev-parse", "HEAD"),
        git_dirty=source_worktree_dirty(),
        built_at_utc=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
    )
    verify_backend_package(package_dir)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE)
    args = parser.parse_args()
    try:
        finalize_package(args.package.resolve())
    except (OSError, RuntimeError, subprocess.CalledProcessError) as exc:
        print(f"Backend package finalization failed: {exc}", file=sys.stderr)
        return 1
    print(f"Backend package finalized: {args.package.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
