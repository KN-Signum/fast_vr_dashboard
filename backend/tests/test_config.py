from __future__ import annotations

import unittest
from pathlib import Path

from config import AppSettings


class AppSettingsTests(unittest.TestCase):
    def test_development_defaults_use_mock_streams(self) -> None:
        settings = AppSettings.from_env(environ={})

        self.assertEqual(settings.environment, "development")
        self.assertEqual(settings.eeg_mode, "mock")
        self.assertEqual(settings.eeg_device_name, "BA MINI 037")
        self.assertEqual(settings.et_mode, "mock")
        self.assertFalse(settings.open_browser)

    def test_production_defaults_use_real_sources(self) -> None:
        settings = AppSettings.from_env(
            default_environment="production",
            environ={},
        )

        self.assertEqual(settings.environment, "production")
        self.assertEqual(settings.eeg_mode, "real")
        self.assertEqual(settings.et_mode, "vr")
        self.assertTrue(settings.open_browser)

    def test_environment_overrides_are_parsed(self) -> None:
        settings = AppSettings.from_env(
            environ={
                "VRDASH_ENV": "test",
                "VRDASH_HOST": "127.0.0.1",
                "VRDASH_PORT": "9000",
                "VRDASH_EEG_MODE": "off",
                "VRDASH_EEG_DEVICE": "BA MINI TEST",
                "VRDASH_ET_MODE": "vr",
                "VRDASH_BEACON_ENABLED": "false",
                "VRDASH_OPEN_BROWSER": "yes",
                "VRDASH_DATA_DIR": "/tmp/panel-vr-data",
                "VRDASH_STATIC_DIR": "/tmp/panel-vr-static",
                "VRDASH_LOG_LEVEL": "debug",
                "VRDASH_VERSION": "1.2.3",
            }
        )

        self.assertEqual(settings.host, "127.0.0.1")
        self.assertEqual(settings.port, 9000)
        self.assertEqual(settings.eeg_mode, "off")
        self.assertEqual(settings.eeg_device_name, "BA MINI TEST")
        self.assertEqual(settings.et_mode, "vr")
        self.assertFalse(settings.beacon_enabled)
        self.assertTrue(settings.open_browser)
        self.assertEqual(settings.data_dir, Path("/tmp/panel-vr-data"))
        self.assertEqual(settings.static_dir, Path("/tmp/panel-vr-static"))
        self.assertEqual(settings.log_level, "DEBUG")
        self.assertEqual(settings.app_version, "1.2.3")

    def test_invalid_values_are_rejected(self) -> None:
        invalid_environments = [
            {"VRDASH_PORT": "invalid"},
            {"VRDASH_PORT": "70000"},
            {"VRDASH_EEG_MODE": "sometimes"},
            {"VRDASH_EEG_DEVICE": "  "},
            {"VRDASH_ET_MODE": "sensor"},
            {"VRDASH_BEACON_ENABLED": "maybe"},
        ]

        for environ in invalid_environments:
            with self.subTest(environ=environ), self.assertRaises(ValueError):
                AppSettings.from_env(environ=environ)


if __name__ == "__main__":
    unittest.main()
