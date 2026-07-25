#!/usr/bin/env python3
"""Assemble and verify the Windows installer and portable release archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import zipfile
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

from validate_windows_release import require_windows_pe, require_x64_pe
from verify_backend_package import (
    DEFAULT_PACKAGE,
    MANIFEST_NAME,
    package_file_manifest,
    verify_backend_package,
)
from verify_frontend_build import read_release_version


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_RELEASE_ROOT = ROOT / "release"
CLIENT_README = ROOT / "installer" / "README_PL.txt"


class WindowsReleaseAssemblyError(RuntimeError):
    """Raised when Windows release artifacts cannot be assembled or verified."""


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WindowsReleaseAssemblyError(f"Cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise WindowsReleaseAssemblyError(f"Expected a JSON object in {path}")
    return value


def zip_package(package_dir: Path, destination: Path) -> None:
    with zipfile.ZipFile(
        destination,
        mode="w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
    ) as archive:
        for path in sorted(package_dir.rglob("*")):
            if path.is_symlink():
                raise WindowsReleaseAssemblyError(
                    f"Windows package contains a symbolic link: {path}"
                )
            if path.is_file():
                relative = path.relative_to(package_dir).as_posix()
                archive.write(path, f"PanelVR/{relative}")
        archive.write(CLIENT_README, "PanelVR/README_PL.txt")


def verify_portable_zip(package_dir: Path, archive_path: Path) -> None:
    expected = package_file_manifest(package_dir)
    expected[MANIFEST_NAME] = sha256_file(package_dir / MANIFEST_NAME)
    expected["README_PL.txt"] = sha256_file(CLIENT_README)

    with zipfile.ZipFile(archive_path) as archive:
        actual: dict[str, str] = {}
        for member in archive.infolist():
            if member.is_dir():
                continue
            if not member.filename.startswith("PanelVR/"):
                raise WindowsReleaseAssemblyError(
                    f"Unexpected ZIP path: {member.filename}"
                )
            relative = member.filename.removeprefix("PanelVR/")
            actual[relative] = hashlib.sha256(archive.read(member)).hexdigest()
    if actual != expected:
        raise WindowsReleaseAssemblyError(
            "Portable ZIP does not exactly match the packaged application"
        )


def assemble_release(
    *,
    installer: Path,
    package_dir: Path,
    release_root: Path,
    signed: bool,
) -> Path:
    if sys.platform != "win32":
        raise WindowsReleaseAssemblyError(
            "Windows release artifacts must be assembled on Windows"
        )

    verify_backend_package(package_dir)
    executable = package_dir / "PanelVR.exe"
    require_x64_pe(executable)
    # Inno Setup 6 uses a PE32 bootstrapper while enforcing x64 installation
    # through ArchitecturesAllowed and ArchitecturesInstallIn64BitMode.
    require_windows_pe(installer)

    package_manifest = read_json(package_dir / MANIFEST_NAME)
    if package_manifest.get("platform") != "Windows":
        raise WindowsReleaseAssemblyError("Backend package was not built on Windows")
    if str(package_manifest.get("architecture", "")).lower() not in {
        "amd64",
        "x86_64",
    }:
        raise WindowsReleaseAssemblyError("Backend package is not Windows x64")

    version = read_release_version(ROOT)
    output_dir = release_root / version
    if output_dir.exists():
        shutil.rmtree(output_dir)
    output_dir.mkdir(parents=True)

    installer_name = f"PanelVR-Setup-{version}-win-x64.exe"
    archive_name = f"PanelVR-{version}-win-x64.zip"
    installer_output = output_dir / installer_name
    archive_output = output_dir / archive_name
    shutil.copy2(installer, installer_output)
    zip_package(package_dir, archive_output)
    verify_portable_zip(package_dir, archive_output)

    artifacts = {
        installer_name: {
            "sha256": sha256_file(installer_output),
            "size_bytes": installer_output.stat().st_size,
            "signed": signed,
        },
        archive_name: {
            "sha256": sha256_file(archive_output),
            "size_bytes": archive_output.stat().st_size,
            "signed": False,
        },
    }
    release_manifest = {
        "schema_version": 1,
        "app_version": version,
        "platform": "windows",
        "architecture": "x64",
        "git_commit": package_manifest.get("git_commit"),
        "git_dirty": package_manifest.get("git_dirty"),
        "built_at_utc": datetime.now(UTC).isoformat().replace("+00:00", "Z"),
        "package_executable_signed": signed,
        "package_manifest_sha256": sha256_file(package_dir / MANIFEST_NAME),
        "artifacts": artifacts,
    }
    (output_dir / "release-manifest.json").write_text(
        json.dumps(release_manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    checksum_lines = [
        f"{details['sha256']}  {name}" for name, details in sorted(artifacts.items())
    ]
    (output_dir / "SHA256SUMS.txt").write_text(
        "\n".join(checksum_lines) + "\n",
        encoding="ascii",
    )
    return output_dir


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--package", type=Path, default=DEFAULT_PACKAGE)
    parser.add_argument("--release-root", type=Path, default=DEFAULT_RELEASE_ROOT)
    parser.add_argument("--signed", action="store_true")
    args = parser.parse_args()
    try:
        output = assemble_release(
            installer=args.installer.resolve(),
            package_dir=args.package.resolve(),
            release_root=args.release_root.resolve(),
            signed=args.signed,
        )
    except (OSError, RuntimeError, zipfile.BadZipFile) as exc:
        print(f"Windows release assembly failed: {exc}", file=sys.stderr)
        return 1
    print(f"Windows release is ready: {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
