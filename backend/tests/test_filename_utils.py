from __future__ import annotations

import unittest

from filename_utils import safe_filename_part


class FilenameUtilsTests(unittest.TestCase):
    def test_normalizes_unsafe_filename_characters(self) -> None:
        self.assertEqual(
            safe_filename_part('  patient/01: "test"  ', fallback="pacjent"),
            "patient_01_test",
        )

    def test_uses_fallback_for_an_empty_result(self) -> None:
        self.assertEqual(safe_filename_part("///", fallback="pacjent"), "pacjent")


if __name__ == "__main__":
    unittest.main()
