import tempfile
import unittest
import sys
from importlib.util import module_from_spec, spec_from_file_location
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "scripts/update-formula.py"
SPEC = spec_from_file_location("update_formula", SCRIPT)
MODULE = module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class ReleaseDiscoveryTest(unittest.TestCase):
    def test_discovers_exact_2x_linux_x64_artifact(self):
        url = (
            "https://storage.googleapis.com/antigravity-public/antigravity-hub/"
            "2.8.1-6512087774658560/linux-x64/Antigravity.tar.gz"
        )
        release = MODULE.discover(f'<a href="{url}">Download</a>')
        self.assertEqual("2.8.1", release.version)
        self.assertEqual("6512087774658560", release.build)
        self.assertEqual(url, release.url)

    def test_rejects_legacy_1x_artifact(self):
        html = (
            "https://edgedl.me.gvt1.com/edgedl/release2/j0qc3/antigravity/"
            "stable/1.23.2-123/linux-x64/Antigravity.tar.gz"
        )
        with self.assertRaises(ValueError):
            MODULE.discover(html)

    def test_rejects_ambiguous_2x_artifacts(self):
        first = (
            "https://storage.googleapis.com/antigravity-public/antigravity-hub/"
            "2.8.1-111/linux-x64/Antigravity.tar.gz"
        )
        second = (
            "https://storage.googleapis.com/antigravity-public/antigravity-hub/"
            "2.8.2-222/linux-x64/Antigravity.tar.gz"
        )
        with self.assertRaises(ValueError):
            MODULE.discover(first + second)

    def test_updates_formula_atomically_by_shape(self):
        formula = """class Antigravity < Formula
  url "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.0-1/linux-x64/Antigravity.tar.gz"
  version "2.8.0"
  sha256 "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
end
"""
        release = MODULE.Release(
            "2.8.1",
            "2",
            "https://storage.googleapis.com/antigravity-public/antigravity-hub/2.8.1-2/linux-x64/Antigravity.tar.gz",
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "antigravity.rb"
            path.write_text(formula)
            self.assertTrue(MODULE.update_formula(path, release, "b" * 64))
            updated = path.read_text()
            self.assertIn('version "2.8.1"', updated)
            self.assertIn('sha256 "' + "b" * 64 + '"', updated)


if __name__ == "__main__":
    unittest.main()
