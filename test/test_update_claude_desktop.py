import hashlib
import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/update-claude-desktop.py"
SPEC = importlib.util.spec_from_file_location("update_claude_desktop", SCRIPT)
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)


class UpdateClaudeDesktopTests(unittest.TestCase):
    def release_stanza(self, version: str, artifact: bytes = b"deb") -> str:
        digest = hashlib.sha256(artifact).hexdigest()
        return "\n".join(
            [
                "Package: claude-desktop",
                f"Version: {version}",
                "Architecture: amd64",
                f"Filename: pool/main/c/claude-desktop/claude-desktop_{version}_amd64.deb",
                f"SHA256: {digest}",
            ]
        )

    def test_parse_index_selects_highest_version(self):
        index = self.release_stanza("1.99.9") + "\n\n" + self.release_stanza("1.100.0")
        release = MODULE.parse_index(index)
        self.assertEqual(release.version, "1.100.0")
        self.assertTrue(release.url.endswith("claude-desktop_1.100.0_amd64.deb"))

    def test_parse_index_rejects_unexpected_pool_path(self):
        index = self.release_stanza("1.2.3").replace(
            "pool/main/c/claude-desktop/", "pool/untrusted/"
        )
        with self.assertRaises(ValueError):
            MODULE.parse_index(index)

    def test_verify_artifact_rejects_checksum_mismatch(self):
        release = MODULE.parse_index(self.release_stanza("1.2.3", b"expected"))
        with tempfile.TemporaryDirectory() as temporary:
            artifact = Path(temporary) / "claude.deb"
            artifact.write_bytes(b"different")
            with self.assertRaises(ValueError):
                MODULE.verify_artifact(release, artifact)

    def test_update_formula_updates_all_pins(self):
        release = MODULE.parse_index(self.release_stanza("2.3.4", b"payload"))
        with tempfile.TemporaryDirectory() as temporary:
            formula = Path(temporary) / "claude-desktop.rb"
            formula.write_text(
                '  url "https://example.invalid/old.deb"\n'
                '  version "1.0.0"\n'
                f'  sha256 "{"0" * 64}"\n'
            )
            self.assertTrue(MODULE.update_formula(formula, release))
            updated = formula.read_text()
            self.assertIn(f'url "{release.url}"', updated)
            self.assertIn('version "2.3.4"', updated)
            self.assertIn(f'sha256 "{release.digest}"', updated)


if __name__ == "__main__":
    unittest.main()
