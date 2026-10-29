import contextlib
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("branch_parity", ROOT / "scripts/branch-parity.py")
MODULE = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

GIT_ENV = {
    "GIT_AUTHOR_NAME": "Parity Test",
    "GIT_AUTHOR_EMAIL": "parity@example.com",
    "GIT_COMMITTER_NAME": "Parity Test",
    "GIT_COMMITTER_EMAIL": "parity@example.com",
    "GIT_CONFIG_GLOBAL": os.devnull,
    "GIT_CONFIG_NOSYSTEM": "1",
}
IDENTITIES = {"alpha": {"tap": "alpha-tap"}, "beta": {"tap": "beta-tap"}}


class BranchParityTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        environment = mock.patch.dict(os.environ, GIT_ENV)
        environment.start()
        self.addCleanup(environment.stop)
        self.root = Path(temporary.name)
        self.clock = 1_700_000_000
        self.git("init", "-q", "-b", "alpha")
        self.git("commit", "-q", "--allow-empty", "-m", "root")
        self.git("branch", "beta")
        self.git("switch", "-q", "--detach")

    def git(self, *args):
        return subprocess.run(["git", "-C", str(self.root), *args], check=True,
                              capture_output=True, text=True).stdout

    def commit(self, branch, files):
        """Commit files to branch with strictly increasing timestamps."""
        self.clock += 60
        repo = MODULE.Repo(self.root)
        with mock.patch.dict(os.environ, {"GIT_COMMITTER_DATE": f"{self.clock} +0000"}):
            repo.commit(branch, files, "test commit")

    def show(self, branch, path):
        return MODULE.Repo(self.root).read(branch, path)

    def config(self, packages, identities=IDENTITIES):
        path = self.root / "branch-parity.json"
        path.write_text(json.dumps({"branches": identities, "packages": packages}))
        return path

    def run_cli(self, *args):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = MODULE.main(["--repo", str(self.root), *args])
        return code, output.getvalue()

    def test_full_sync_rewrites_identity_and_reaches_parity(self):
        self.config({"Formula/x.rb": "full"})
        self.commit("beta", {"Formula/x.rb": '  version "1"\n  # see beta-tap/x\n'})
        self.commit("alpha", {"Formula/x.rb": '  version "2"\n  # see alpha-tap/x\n'})

        self.assertEqual(self.run_cli("check")[0], 1)
        code, output = self.run_cli("sync")
        self.assertEqual(code, 0, output)
        self.assertEqual(self.show("beta", "Formula/x.rb"), '  version "2"\n  # see beta-tap/x\n')
        self.assertEqual(self.run_cli("check")[0], 0)
        self.assertIn("Sync Formula/x.rb from alpha", self.git("log", "-1", "--format=%B", "beta"))

    def test_full_sync_creates_missing_file(self):
        self.config({"Casks/y.rb": "full"})
        self.commit("alpha", {"Casks/y.rb": "cask \"y\"\n"})
        self.assertEqual(self.run_cli("sync")[0], 0)
        self.assertEqual(self.show("beta", "Casks/y.rb"), "cask \"y\"\n")

    def test_partial_sync_updates_only_listed_stanzas(self):
        self.config({"Formula/x.rb": {"mode": "partial", "fields": ["url", "version", "sha256"]}})
        self.commit("beta", {"Formula/x.rb":
                             '  desc "Beta flavour"\n  url "https://e.x/1.zip"\n  version "1"\n'
                             '  sha256 "aa"\n  depends_on "beta-only"\n'})
        self.commit("alpha", {"Formula/x.rb":
                              '  desc "Alpha flavour"\n  url "https://e.x/2.zip"\n  version "2"\n  sha256 "bb"\n'})

        code, output = self.run_cli("sync")
        self.assertEqual(code, 0, output)
        self.assertIn("beta: url, version, sha256 <- alpha", output)
        self.assertEqual(self.show("beta", "Formula/x.rb"),
                         '  desc "Beta flavour"\n  url "https://e.x/2.zip"\n  version "2"\n'
                         '  sha256 "bb"\n  depends_on "beta-only"\n')

    def test_partial_stanza_includes_continuation_lines(self):
        self.config({"Casks/c.rb": {"mode": "partial", "fields": ["url"]}})
        self.commit("beta", {"Casks/c.rb": '  url "https://old",\n      verified: "old"\n  name "C"\n'})
        self.commit("alpha", {"Casks/c.rb": '  url "https://new",\n      verified: "new"\n  name "C!"\n'})
        self.assertEqual(self.run_cli("sync")[0], 0)
        self.assertEqual(self.show("beta", "Casks/c.rb"), '  url "https://new",\n      verified: "new"\n  name "C"\n')

    def test_partial_field_on_one_side_only_is_an_error(self):
        self.config({"Formula/x.rb": {"mode": "partial", "fields": ["version", "sha256"]}})
        self.commit("beta", {"Formula/x.rb": '  sha256 "aa"\n'})
        self.commit("alpha", {"Formula/x.rb": '  version "2"\n  sha256 "bb"\n'})

        code, output = self.run_cli("sync")
        self.assertEqual(code, 1)
        self.assertIn("beta: top-level `version` exists on alpha only", output)
        self.assertEqual(self.show("beta", "Formula/x.rb"), '  sha256 "aa"\n')

    def test_ambiguous_identity_rewrite_is_refused(self):
        self.config({"Formula/x.rb": "full"})
        self.commit("beta", {"Formula/x.rb": "old\n"})
        self.commit("alpha", {"Formula/x.rb": "alpha-tap and beta-tap\n"})
        code, output = self.run_cli("sync")
        self.assertEqual(code, 1)
        self.assertIn("ambiguous", output)
        self.assertEqual(self.show("beta", "Formula/x.rb"), "old\n")

    def test_rewrite_false_copies_verbatim(self):
        self.config({"scripts/s.py": {"mode": "full", "rewrite": False}})
        self.commit("beta", {"scripts/s.py": "old\n"})
        self.commit("alpha", {"scripts/s.py": "alpha-tap and beta-tap\n"})
        self.assertEqual(self.run_cli("sync")[0], 0)
        self.assertEqual(self.show("beta", "scripts/s.py"), "alpha-tap and beta-tap\n")

    def test_from_overrides_latest_commit(self):
        self.config({"Formula/x.rb": "full"})
        self.commit("beta", {"Formula/x.rb": "older beta-tap\n"})
        self.commit("alpha", {"Formula/x.rb": "newer alpha-tap\n"})
        self.assertEqual(self.run_cli("sync", "--from", "beta")[0], 0)
        self.assertEqual(self.show("alpha", "Formula/x.rb"), "older alpha-tap\n")

    def test_branch_subset_leaves_other_branches_alone(self):
        identities = {**IDENTITIES, "gamma": {"tap": "gamma-tap"}}
        self.git("branch", "gamma", "alpha")
        self.config({"Formula/x.rb": {"mode": "full", "branches": ["alpha", "beta"]}}, identities)
        self.commit("gamma", {"Formula/x.rb": "gamma's own\n"})
        self.commit("alpha", {"Formula/x.rb": "shared\n"})
        self.assertEqual(self.run_cli("sync")[0], 0)
        self.assertEqual(self.show("beta", "Formula/x.rb"), "shared\n")
        self.assertEqual(self.show("gamma", "Formula/x.rb"), "gamma's own\n")

    def test_checked_out_branch_gets_working_tree_refreshed(self):
        self.config({"Formula/x.rb": "full"})
        self.commit("beta", {"Formula/x.rb": "old\n"})
        self.commit("alpha", {"Formula/x.rb": "new\n"})
        self.git("switch", "-q", "beta")
        (self.root / "branch-parity.json").rename(self.root / ".git/parity.json")

        code, _ = self.run_cli("--config", str(self.root / ".git/parity.json"), "sync")
        self.assertEqual(code, 0)
        self.assertEqual((self.root / "Formula/x.rb").read_text(), "new\n")
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_local_changes_on_checked_out_branch_abort_sync(self):
        config = self.config({"Formula/x.rb": "full"})
        config.rename(self.root / ".git/parity.json")
        self.commit("beta", {"Formula/x.rb": "old\n"})
        self.commit("alpha", {"Formula/x.rb": "new\n"})
        self.git("switch", "-q", "beta")
        (self.root / "Formula/x.rb").write_text("edited\n")
        tip = self.git("rev-parse", "beta")

        with self.assertRaises(MODULE.ParityError):
            self.run_cli("--config", str(self.root / ".git/parity.json"), "sync")
        self.assertEqual(self.git("rev-parse", "beta"), tip)
        self.assertEqual((self.root / "Formula/x.rb").read_text(), "edited\n")

    def test_suggest_classifies_full_and_partial(self):
        path = self.config({})
        self.commit("alpha", {"Formula/same.rb": "x alpha-tap\n",
                              "Formula/diff.rb": '  desc "A"\n  version "1"\n  sha256 "aa"\n'})
        self.commit("beta", {"Formula/same.rb": "x beta-tap\n",
                             "Formula/diff.rb": '  desc "B"\n  version "1"\n  sha256 "aa"\n'})
        packages = MODULE.suggest(MODULE.Repo(self.root), path, ["Formula"])["packages"]
        self.assertEqual(packages["Formula/same.rb"], "full")
        self.assertEqual(packages["Formula/diff.rb"], {"mode": "partial", "fields": ["version", "sha256"]})

    def test_config_validation(self):
        with self.assertRaises(MODULE.ParityError):
            MODULE.load_config(self.config({"x": {"mode": "full", "fields": ["url"]}}))
        with self.assertRaises(MODULE.ParityError):
            MODULE.load_config(self.config({"x": {"mode": "full", "branches": ["alpha", "nope"]}}))
        with self.assertRaises(MODULE.ParityError):
            MODULE.load_config(self.config({}, {"alpha": {"tap": "a"}, "beta": {"name": "b"}}))


if __name__ == "__main__":
    unittest.main()
