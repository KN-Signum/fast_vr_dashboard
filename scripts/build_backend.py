#!/usr/bin/env python3
"""Build and verify the one-directory Panel VR backend package."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from datetime import UTC, datetime
from pathlib import Path

from smoke_test_package import smoke_test
from verify_backend_package import (
    DEFAULT_PACKAGE,
    verify_backend_package,
    write_package_manifest,
)
from verify_frontend_build import (
    VerificationError,
    verify_build_directory,
    verify_source_versions,
)


ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
SPEC = BACKEND / "panel_vr.spec"
SOURCE_STATIC = BACKEND / "static" / "web"
DIST_ROOT = ROOT / "dist"
WORK_ROOT = ROOT / "build" / "pyinstaller"


def git_output(*arguments: str) -> str:
    return subprocess.run(
        ["git", *arguments],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()


def require_pyinstaller() -> None:
    try:
        import PyInstaller  # noqa: F401
    except ImportError as exc:
        raise RuntimeError(
            "PyInstaller is not installed. Run this script through the "
            "backend package dependency group."
        ) from exc


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--skip-smoke",
        action="store_true",
        help="Build and verify files without starting the frozen server.",
    )
    args = parser.parse_args()

    try:
        require_pyinstaller()
        version, build_number = verify_source_versions(ROOT)
        verify_build_directory(
            SOURCE_STATIC,
            expected_version=version,
            expected_build_number=build_number,
        )

        environment = os.environ.copy()
        cache_dir = WORK_ROOT / "cache"
        cache_dir.mkdir(parents=True, exist_ok=True)
        environment["MPLCONFIGDIR"] = str(cache_dir / "matplotlib")
        environment["PYINSTALLER_CONFIG_DIR"] = str(cache_dir / "pyinstaller")
        environment["XDG_CACHE_HOME"] = str(cache_dir)

        command = [
            sys.executable,
            "-m",
            "PyInstaller",
            "--noconfirm",
            "--clean",
            "--log-level",
            "WARN",
            "--distpath",
            str(DIST_ROOT),
            "--workpath",
            str(WORK_ROOT),
            str(SPEC),
        ]
        print(f"+ {' '.join(command)}", flush=True)
        subprocess.run(command, cwd=ROOT, env=environment, check=True)

        commit = git_output("rev-parse", "HEAD")
        dirty = bool(git_output("status", "--porcelain", "--untracked-files=normal"))
        write_package_manifest(
            DEFAULT_PACKAGE,
            app_version=version,
            git_commit=commit,
            git_dirty=dirty,
            built_at_utc=datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        )
        verify_backend_package(DEFAULT_PACKAGE)
        if not args.skip_smoke:
            smoke_test(DEFAULT_PACKAGE)
    except (
        OSError,
        RuntimeError,
        subprocess.CalledProcessError,
        VerificationError,
    ) as exc:
        print(f"Backend package build failed: {exc}", file=sys.stderr)
        return 1

    package_size = sum(
        path.stat().st_size for path in DEFAULT_PACKAGE.rglob("*") if path.is_file()
    )
    print(
        f"Panel VR {version} package is ready in {DEFAULT_PACKAGE} "
        f"({package_size / 1024 / 1024:.1f} MiB)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
