#!/usr/bin/env python3
"""Verify the structure, metadata, and hashes of a PyInstaller package."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import re
import sys
from pathlib import Path
from typing import Any

from verify_frontend_build import (
    VerificationError,
    read_release_version,
    verify_exact_copy,
)


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_PACKAGE = ROOT / "dist" / "PanelVR"
SOURCE_STATIC = ROOT / "backend" / "static" / "web"
MANIFEST_NAME = "package-manifest.json"
REQUIRED_DLLS = ("babciconnect.dll", "bacore.dll", "simpleble.dll")
REQUIRED_REPORT_FONTS = ("DejaVuSans.ttf", "DejaVuSans-Bold.ttf")
REQUIRED_ENV_KEYS = (
    "VRDASH_SUPABASE_URL",
    "VRDASH_SUPABASE_SERVICE_ROLE_KEY",
    "VRDASH_SUPABASE_BUCKET",
)


class PackageVerificationError(RuntimeError):
    """Raised when a packaged backend is incomplete or inconsistent."""


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PackageVerificationError(f"Cannot read valid JSON from {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PackageVerificationError(f"Expected a JSON object in {path}")
    return value


def find_executable(package_dir: Path) -> Path:
    candidates = (package_dir / "PanelVR.exe", package_dir / "PanelVR")
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise PackageVerificationError(f"PanelVR executable not found in {package_dir}")


def find_resource_root(package_dir: Path) -> Path:
    candidates = (package_dir / "_internal", package_dir)
    for candidate in candidates:
        if (candidate / "static" / "web" / "index.html").is_file():
            return candidate
    raise PackageVerificationError(
        f"Packaged Flutter resources not found in {package_dir}"
    )


def package_file_manifest(package_dir: Path) -> dict[str, str]:
    manifest: dict[str, str] = {}
    for path in sorted(package_dir.rglob("*")):
        relative_path = path.relative_to(package_dir).as_posix()
        if relative_path == MANIFEST_NAME:
            continue
        if path.is_symlink():
            manifest[relative_path] = f"symlink:{os.readlink(path)}"
        elif path.is_file():
            digest = hashlib.sha256()
            with path.open("rb") as packaged_file:
                for chunk in iter(lambda: packaged_file.read(1024 * 1024), b""):
                    digest.update(chunk)
            manifest[relative_path] = digest.hexdigest()
    return manifest


def write_package_manifest(
    package_dir: Path,
    *,
    app_version: str,
    git_commit: str,
    git_dirty: bool,
    built_at_utc: str,
) -> Path:
    executable = find_executable(package_dir)
    resource_root = find_resource_root(package_dir)
    payload = {
        "schema_version": 1,
        "app_version": app_version,
        "git_commit": git_commit,
        "git_dirty": git_dirty,
        "built_at_utc": built_at_utc,
        "platform": platform.system(),
        "architecture": platform.machine(),
        "executable": executable.relative_to(package_dir).as_posix(),
        "resource_root": resource_root.relative_to(package_dir).as_posix() or ".",
        "files": package_file_manifest(package_dir),
    }
    manifest_path = package_dir / MANIFEST_NAME
    manifest_path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest_path


def verify_backend_package(
    package_dir: Path = DEFAULT_PACKAGE,
    *,
    source_static: Path = SOURCE_STATIC,
) -> None:
    if not package_dir.is_dir():
        raise PackageVerificationError(
            f"PyInstaller package directory does not exist: {package_dir}"
        )

    executable = find_executable(package_dir)
    resource_root = find_resource_root(package_dir)
    packaged_static = resource_root / "static" / "web"
    try:
        verify_exact_copy(source_static, packaged_static)
    except VerificationError as exc:
        raise PackageVerificationError(str(exc)) from exc

    missing_dlls = [
        name
        for name in REQUIRED_DLLS
        if not (resource_root / "brainaccess" / "lib" / name).is_file()
    ]
    if missing_dlls:
        raise PackageVerificationError(
            f"Package is missing BrainAccess DLLs: {', '.join(missing_dlls)}"
        )

    missing_fonts = [
        name
        for name in REQUIRED_REPORT_FONTS
        if not (resource_root / "assets" / "fonts" / name).is_file()
    ]
    if missing_fonts:
        raise PackageVerificationError(
            f"Package is missing session report fonts: {', '.join(missing_fonts)}"
        )

    env_file = package_dir / ".env"
    if not env_file.is_file():
        raise PackageVerificationError("Package is missing the runtime .env file")
    configured_values = {}
    for line in env_file.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        configured_values[key.strip()] = value.strip()
    missing_env_keys = [
        key for key in REQUIRED_ENV_KEYS if not configured_values.get(key)
    ]
    if missing_env_keys:
        raise PackageVerificationError(
            "Package .env is missing values: " + ", ".join(missing_env_keys)
        )

    manifest = _read_json(package_dir / MANIFEST_NAME)
    expected_version = read_release_version(ROOT)
    if manifest.get("schema_version") != 1:
        raise PackageVerificationError("Unsupported package manifest schema")
    if manifest.get("app_version") != expected_version:
        raise PackageVerificationError(
            f"Package version {manifest.get('app_version')!r} "
            f"does not match {expected_version!r}"
        )
    if manifest.get("executable") != executable.relative_to(package_dir).as_posix():
        raise PackageVerificationError("Package manifest executable is incorrect")
    if not re.fullmatch(r"[0-9a-f]{40}", str(manifest.get("git_commit", ""))):
        raise PackageVerificationError("Package manifest Git commit is invalid")
    if not isinstance(manifest.get("git_dirty"), bool):
        raise PackageVerificationError("Package manifest git_dirty is invalid")
    if not isinstance(manifest.get("files"), dict):
        raise PackageVerificationError("Package manifest file map is invalid")

    actual_files = package_file_manifest(package_dir)
    if manifest["files"] != actual_files:
        raise PackageVerificationError(
            "Package files do not match package-manifest.json"
        )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE)
    args = parser.parse_args()
    try:
        verify_backend_package(args.package.resolve())
    except (OSError, PackageVerificationError, VerificationError) as exc:
        print(f"Backend package verification failed: {exc}", file=sys.stderr)
        return 1
    print(f"Backend package verification passed: {args.package.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
