import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("update_toshy", ROOT / "scripts/update-toshy.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ToshyUpdaterTests(unittest.TestCase):
    def test_discovers_only_stable_release(self):
        release = MODULE.discover({"tag_name": "Toshy_v26.09.0", "draft": False, "prerelease": False})
        self.assertEqual(release.version, "26.09.0")
        with self.assertRaises(ValueError):
            MODULE.discover({"tag_name": "main", "draft": False, "prerelease": False})

    def test_updates_formula_and_cask_pins(self):
        release = MODULE.Release("26.09.0", "Toshy_v26.09.0", "https://github.com/RedBearAK/toshy/archive/refs/tags/Toshy_v26.09.0.tar.gz")
        formula = '  url "https://github.com/RedBearAK/toshy/archive/refs/tags/Toshy_v26.08.0.tar.gz"\n  version "26.08.0"\n  sha256 "' + "0" * 64 + '"\n'
        cask = '  version "26.08.0"\n  sha256 "' + "0" * 64 + '"\n'
        self.assertIn("Toshy_v26.09.0.tar.gz", MODULE.update_definition(formula, release, "a" * 64, formula=True))
        self.assertIn('version "26.09.0"', MODULE.update_definition(cask, release, "a" * 64, formula=False))

    def test_detects_mismatched_pin_shape(self):
        with self.assertRaises(ValueError):
            MODULE.current_pin('version "26.08.0"\n')


if __name__ == "__main__":
    unittest.main()
