from __future__ import annotations

import json
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Mapping


_VALID_ENVIRONMENTS = {"development", "production", "test"}
_VALID_EEG_MODES = {"real", "mock", "off"}
_VALID_ET_MODES = {"vr", "mock", "off"}
_VALID_LOG_LEVELS = {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}


def _bundled_app_version() -> str:
    build_info = (
        Path(__file__).resolve().parent / "static" / "web" / "build-info.json"
    )
    try:
        payload = json.loads(build_info.read_text(encoding="utf-8"))
        version = payload.get("app_version") if isinstance(payload, dict) else None
        if isinstance(version, str) and version.strip():
            return version.strip()
    except (OSError, ValueError):
        pass
    return "0.0.0-dev"


def _parse_bool(value: str | None, default: bool) -> bool:
    if value is None:
        return default

    normalized = value.strip().lower()
    if normalized in {"1", "true", "yes", "on"}:
        return True
    if normalized in {"0", "false", "no", "off"}:
        return False
    raise ValueError(f"Invalid boolean value: {value!r}")


def _optional_path(value: str | None) -> Path | None:
    if value is None or not value.strip():
        return None
    return Path(value).expanduser()


@dataclass(frozen=True, slots=True)
class AppSettings:
    environment: str
    host: str
    port: int
    eeg_mode: str
    eeg_device_name: str
    et_mode: str
    beacon_enabled: bool
    open_browser: bool
    data_dir: Path | None
    static_dir: Path | None
    log_level: str
    app_version: str
    supabase_url: str | None
    supabase_service_role_key: str | None
    supabase_bucket: str | None

    @classmethod
    def from_env(
        cls,
        *,
        default_environment: str = "development",
        environ: Mapping[str, str] | None = None,
    ) -> AppSettings:
        env = os.environ if environ is None else environ
        environment = env.get("VRDASH_ENV", default_environment).strip().lower()
        if environment not in _VALID_ENVIRONMENTS:
            raise ValueError(
                "VRDASH_ENV must be one of: "
                f"{', '.join(sorted(_VALID_ENVIRONMENTS))}"
            )

        production = environment == "production"
        host = env.get("VRDASH_HOST", "0.0.0.0").strip()
        if not host:
            raise ValueError("VRDASH_HOST cannot be empty")

        try:
            port = int(env.get("VRDASH_PORT", "8080"))
        except ValueError as error:
            raise ValueError("VRDASH_PORT must be an integer") from error
        if not 1 <= port <= 65535:
            raise ValueError("VRDASH_PORT must be between 1 and 65535")

        eeg_mode = env.get(
            "VRDASH_EEG_MODE",
            "real" if production else "mock",
        ).strip().lower()
        if eeg_mode not in _VALID_EEG_MODES:
            raise ValueError(
                f"VRDASH_EEG_MODE must be one of: {', '.join(sorted(_VALID_EEG_MODES))}"
            )
        eeg_device_name = env.get("VRDASH_EEG_DEVICE", "BA MINI 037").strip()
        if not eeg_device_name:
            raise ValueError("VRDASH_EEG_DEVICE cannot be empty")

        et_mode = env.get(
            "VRDASH_ET_MODE",
            "vr" if production else "mock",
        ).strip().lower()
        if et_mode not in _VALID_ET_MODES:
            raise ValueError(
                f"VRDASH_ET_MODE must be one of: {', '.join(sorted(_VALID_ET_MODES))}"
            )

        log_level = env.get("VRDASH_LOG_LEVEL", "INFO").strip().upper()
        if log_level not in _VALID_LOG_LEVELS:
            raise ValueError(
                "VRDASH_LOG_LEVEL must be one of: "
                f"{', '.join(sorted(_VALID_LOG_LEVELS))}"
            )
        default_app_version = _bundled_app_version()

        return cls(
            environment=environment,
            host=host,
            port=port,
            eeg_mode=eeg_mode,
            eeg_device_name=eeg_device_name,
            et_mode=et_mode,
            beacon_enabled=_parse_bool(
                env.get("VRDASH_BEACON_ENABLED"),
                default=True,
            ),
            open_browser=_parse_bool(
                env.get("VRDASH_OPEN_BROWSER"),
                default=production,
            ),
            data_dir=_optional_path(env.get("VRDASH_DATA_DIR")),
            static_dir=_optional_path(env.get("VRDASH_STATIC_DIR")),
            log_level=log_level,
            app_version=env.get("VRDASH_VERSION", default_app_version).strip()
            or default_app_version,
            supabase_url=env.get("VRDASH_SUPABASE_URL", "").strip() or None,
            supabase_service_role_key=(
                env.get("VRDASH_SUPABASE_SERVICE_ROLE_KEY", "").strip() or None
            ),
            supabase_bucket=env.get("VRDASH_SUPABASE_BUCKET", "").strip() or None,
        )
