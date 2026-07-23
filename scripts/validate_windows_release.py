#!/usr/bin/env python3
"""Validate platform-independent inputs for the Windows x64 release."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

from verify_frontend_build import read_release_version


ROOT = Path(__file__).resolve().parents[1]
INSTALLER_SCRIPT = ROOT / "installer" / "PanelVR.iss"
CLIENT_README = ROOT / "installer" / "README_PL.txt"
BUILD_INFO = ROOT / "backend" / "static" / "web" / "build-info.json"
BRAINACCESS_LIB = ROOT / "backend" / "brainaccess" / "lib"
REQUIRED_DLLS = ("babciconnect.dll", "bacore.dll", "simpleble.dll")
PE_MACHINE_AMD64 = 0x8664
PE32_PLUS_MAGIC = 0x20B


class WindowsReleaseValidationError(RuntimeError):
    """Raised when a Windows release input is missing or incompatible."""


def pe_headers(path: Path) -> tuple[int, int]:
    try:
        with path.open("rb") as executable:
            if executable.read(2) != b"MZ":
                raise WindowsReleaseValidationError(f"Not a PE file: {path}")
            executable.seek(0x3C)
            pe_offset_data = executable.read(4)
            if len(pe_offset_data) != 4:
                raise WindowsReleaseValidationError(f"Invalid DOS header: {path}")
            pe_offset = struct.unpack("<I", pe_offset_data)[0]
            executable.seek(pe_offset)
            if executable.read(4) != b"PE\0\0":
                raise WindowsReleaseValidationError(f"Invalid PE signature: {path}")
            machine_data = executable.read(2)
            executable.seek(pe_offset + 24)
            optional_magic_data = executable.read(2)
    except OSError as exc:
        raise WindowsReleaseValidationError(f"Cannot read {path}: {exc}") from exc

    if len(machine_data) != 2 or len(optional_magic_data) != 2:
        raise WindowsReleaseValidationError(f"Incomplete PE header: {path}")
    return (
        struct.unpack("<H", machine_data)[0],
        struct.unpack("<H", optional_magic_data)[0],
    )


def require_x64_pe(path: Path) -> None:
    machine, optional_magic = pe_headers(path)
    if machine != PE_MACHINE_AMD64 or optional_magic != PE32_PLUS_MAGIC:
        raise WindowsReleaseValidationError(
            f"{path} is not a Windows x64 PE32+ binary "
            f"(machine=0x{machine:04x}, magic=0x{optional_magic:04x})"
        )


def validate_installer_source(path: Path = INSTALLER_SCRIPT) -> None:
    try:
        source = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise WindowsReleaseValidationError(
            f"Cannot read installer source {path}: {exc}"
        ) from exc

    required_fragments = (
        "341A0DD0-9AF9-42E7-A828-6D9B1D0E44F6",
        "ArchitecturesAllowed=x64os",
        "ArchitecturesInstallIn64BitMode=x64os",
        'Source: "{#SourceDir}\\*"',
        "PanelVR.exe",
        "advfirewall firewall add rule",
        "advfirewall firewall delete rule",
    )
    missing = [fragment for fragment in required_fragments if fragment not in source]
    if missing:
        raise WindowsReleaseValidationError(
            f"Installer source is missing required declarations: {missing}"
        )


def validate_windows_release_sources(root: Path = ROOT) -> None:
    version = read_release_version(root)
    if not CLIENT_README.is_file():
        raise WindowsReleaseValidationError(
            f"Client instructions are missing: {CLIENT_README}"
        )

    try:
        build_info = json.loads(BUILD_INFO.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise WindowsReleaseValidationError(
            f"Cannot read frontend build metadata: {exc}"
        ) from exc
    if not isinstance(build_info, dict) or build_info.get("app_version") != version:
        raise WindowsReleaseValidationError(
            "Frontend build metadata does not match VERSION"
        )

    for dll_name in REQUIRED_DLLS:
        require_x64_pe(BRAINACCESS_LIB / dll_name)
    validate_installer_source()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    try:
        validate_windows_release_sources()
    except WindowsReleaseValidationError as exc:
        print(f"Windows release source validation failed: {exc}", file=sys.stderr)
        return 1
    print("Windows release source validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
