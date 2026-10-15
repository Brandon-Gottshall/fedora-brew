import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("update_shadow", ROOT / "scripts/update-shadow-pc.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ShadowUpdaterTests(unittest.TestCase):
    def test_updates_only_version_and_primary_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            formula = Path(temporary) / "shadow.rb"
            formula.write_text('  version "1.0"\n  sha256 "' + "0" * 64 + '"\n')
            changed = MODULE.update_formula(formula, MODULE.Release("2.0", "a" * 64))
            self.assertTrue(changed)
            self.assertIn('version "2.0"', formula.read_text())
            self.assertIn('sha256 "' + "a" * 64 + '"', formula.read_text())

    def test_requires_known_formula_shape(self):
        with tempfile.TemporaryDirectory() as temporary:
            formula = Path(temporary) / "shadow.rb"
            formula.write_text("class ShadowPc; end\n")
            with self.assertRaises(ValueError):
                MODULE.update_formula(formula, MODULE.Release("2.0", "a" * 64))


if __name__ == "__main__":
    unittest.main()
