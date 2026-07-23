#!/usr/bin/env python3
"""Validate the Flutter web build and its copy served by the backend."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_SOURCE = ROOT / "frontend" / "build" / "web"
DEFAULT_SERVED = ROOT / "backend" / "static" / "web"
REQUIRED_BUILD_FILES = (
    "index.html",
    "main.dart.js",
    "version.json",
    "build-info.json",
)


class VerificationError(RuntimeError):
    """Raised when a release input or generated artifact is inconsistent."""


def read_release_version(root: Path = ROOT) -> str:
    version = (root / "VERSION").read_text(encoding="utf-8").strip()
    if not re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?", version):
        raise VerificationError(f"Invalid release version in VERSION: {version!r}")
    return version


def read_frontend_version(root: Path = ROOT) -> tuple[str, str]:
    pubspec = (root / "frontend" / "pubspec.yaml").read_text(encoding="utf-8")
    match = re.search(
        r"^version:\s*([0-9A-Za-z.-]+)(?:\+([0-9A-Za-z.-]+))?\s*$",
        pubspec,
        flags=re.MULTILINE,
    )
    if match is None:
        raise VerificationError("Could not read version from frontend/pubspec.yaml")
    return match.group(1), match.group(2) or ""


def read_backend_version(root: Path = ROOT) -> str:
    pyproject = (root / "backend" / "pyproject.toml").read_text(encoding="utf-8")
    project_section = re.search(
        r"^\[project\]\s*$([\s\S]*?)(?=^\[|\Z)",
        pyproject,
        flags=re.MULTILINE,
    )
    if project_section is None:
        raise VerificationError("Could not find [project] in backend/pyproject.toml")
    match = re.search(
        r'^version\s*=\s*"([^"]+)"\s*$',
        project_section.group(1),
        flags=re.MULTILINE,
    )
    if match is None:
        raise VerificationError("Could not read backend project version")
    return match.group(1)


def verify_source_versions(root: Path = ROOT) -> tuple[str, str]:
    release_version = read_release_version(root)
    frontend_version, build_number = read_frontend_version(root)
    backend_version = read_backend_version(root)
    mismatches = []
    if frontend_version != release_version:
        mismatches.append(
            f"frontend/pubspec.yaml has {frontend_version}, expected {release_version}"
        )
    if backend_version != release_version:
        mismatches.append(
            f"backend/pyproject.toml has {backend_version}, expected {release_version}"
        )
    if mismatches:
        raise VerificationError("Version mismatch: " + "; ".join(mismatches))
    return release_version, build_number


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VerificationError(f"Cannot read valid JSON from {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise VerificationError(f"Expected a JSON object in {path}")
    return value


def verify_build_directory(
    directory: Path,
    *,
    expected_version: str,
    expected_build_number: str,
) -> None:
    if not directory.is_dir():
        raise VerificationError(f"Build directory does not exist: {directory}")

    missing = [name for name in REQUIRED_BUILD_FILES if not (directory / name).is_file()]
    if missing:
        raise VerificationError(
            f"Build directory {directory} is missing: {', '.join(missing)}"
        )

    flutter_version = _read_json(directory / "version.json")
    if flutter_version.get("version") != expected_version:
        raise VerificationError(
            f"{directory / 'version.json'} contains version "
            f"{flutter_version.get('version')!r}, expected {expected_version!r}"
        )
    if str(flutter_version.get("build_number", "")) != expected_build_number:
        raise VerificationError(
            f"{directory / 'version.json'} contains build number "
            f"{flutter_version.get('build_number')!r}, "
            f"expected {expected_build_number!r}"
        )

    build_info = _read_json(directory / "build-info.json")
    if build_info.get("app_version") != expected_version:
        raise VerificationError(
            f"{directory / 'build-info.json'} has the wrong app_version"
        )
    if str(build_info.get("build_number", "")) != expected_build_number:
        raise VerificationError(
            f"{directory / 'build-info.json'} has the wrong build_number"
        )
    if not re.fullmatch(r"[0-9a-f]{40}", str(build_info.get("git_commit", ""))):
        raise VerificationError(
            f"{directory / 'build-info.json'} has an invalid git_commit"
        )
    if not isinstance(build_info.get("git_dirty"), bool):
        raise VerificationError(
            f"{directory / 'build-info.json'} has an invalid git_dirty value"
        )
    timestamp = str(build_info.get("built_at_utc", ""))
    if not re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z", timestamp
    ):
        raise VerificationError(
            f"{directory / 'build-info.json'} has an invalid built_at_utc"
        )


def file_manifest(directory: Path) -> dict[str, str]:
    manifest: dict[str, str] = {}
    for path in sorted(directory.rglob("*")):
        if path.is_symlink():
            raise VerificationError(f"Build contains a symbolic link: {path}")
        if path.is_file():
            relative_path = path.relative_to(directory).as_posix()
            manifest[relative_path] = hashlib.sha256(path.read_bytes()).hexdigest()
    return manifest


def verify_exact_copy(source: Path, served: Path) -> None:
    source_manifest = file_manifest(source)
    served_manifest = file_manifest(served)
    if source_manifest == served_manifest:
        return

    source_files = set(source_manifest)
    served_files = set(served_manifest)
    missing = sorted(source_files - served_files)
    extra = sorted(served_files - source_files)
    changed = sorted(
        path
        for path in source_files & served_files
        if source_manifest[path] != served_manifest[path]
    )
    details = []
    if missing:
        details.append(f"missing from served bundle: {', '.join(missing[:10])}")
    if extra:
        details.append(f"stale served files: {', '.join(extra[:10])}")
    if changed:
        details.append(f"content differs: {', '.join(changed[:10])}")
    raise VerificationError("Frontend bundles differ; " + "; ".join(details))


def verify_frontend_build(
    source: Path = DEFAULT_SOURCE,
    served: Path = DEFAULT_SERVED,
    root: Path = ROOT,
) -> None:
    version, build_number = verify_source_versions(root)
    verify_build_directory(
        source,
        expected_version=version,
        expected_build_number=build_number,
    )
    verify_build_directory(
        served,
        expected_version=version,
        expected_build_number=build_number,
    )
    verify_exact_copy(source, served)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--served", type=Path, default=DEFAULT_SERVED)
    args = parser.parse_args()
    try:
        verify_frontend_build(args.source.resolve(), args.served.resolve())
    except VerificationError as exc:
        print(f"Frontend verification failed: {exc}", file=sys.stderr)
        return 1
    print(
        "Frontend verification passed: generated and served bundles are identical."
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
