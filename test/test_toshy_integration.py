import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SYNC = ROOT / "scripts/toshy-brew-sync.py"
SERVICES = (
    "toshy-cosmic-dbus.service",
    "toshy-kwin-dbus.service",
    "toshy-wlroots-dbus.service",
    "toshy-config.service",
    "toshy-session-monitor.service",
)


class ToshyIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.home = self.root / "home"
        self.source = self.root / "source"
        self.runtime = self.root / "runtime"
        self.bin = self.root / "bin"
        self.home.mkdir()
        self.bin.mkdir()
        self.make_source()
        self.make_runtime()
        systemctl = self.bin / "systemctl"
        systemctl.write_text(
            "#!/bin/sh\n"
            "case \"$*\" in\n"
            "  *is-active*|*is-enabled*) exit 1 ;;\n"
            "  *) exit 0 ;;\n"
            "esac\n"
        )
        systemctl.chmod(0o755)
        self.env = os.environ.copy()
        self.env.update(
            {
                "SYSTEMCTL_BIN": str(systemctl),
                "TOSHY_BREW_TEST_INPUT_OK": "1",
                "XDG_STATE_HOME": str(self.home / ".local/state"),
            }
        )

    def tearDown(self):
        self.temporary.cleanup()

    def make_source(self):
        files = {
            "setup_toshy.py": "__version__ = '20260804'\n",
            "scripts/toshy-runtime-env.sh": "TOSHY_RUNTIME_ENV_VERSION='20260727'\n",
            "vendors/xwaykeyz-main/src/xwaykeyz/version.py": '__version__ = "1.25.1"\n',
            "default-toshy-config/toshy_config.py": "# default config\n",
            "scripts/bin/toshy-status.sh": "#!/bin/sh\nexit 0\n",
            "desktop/Toshy_Import_Vars.desktop": "[Desktop Entry]\nName=Import\n",
            "desktop/app.toshy.preferences.desktop": "[Desktop Entry]\nExec=$HOME/.local/bin/toshy-gui\n",
            "desktop/Toshy_Tray.desktop": "[Desktop Entry]\nExec=$HOME/.local/bin/toshy-tray\n",
        }
        for service in SERVICES:
            files[f"systemd-user-service-units/{service}"] = f"[Unit]\nDescription={service}\n"
        for icon in (
            "toshy_app_icon_rainbow_inverse_grayscale.svg",
            "toshy_app_icon_rainbow_inverse.svg",
            "toshy_app_icon_rainbow.svg",
        ):
            files[f"assets/{icon}"] = "<svg/>\n"
        for relative, content in files.items():
            path = self.source / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content)

    def make_runtime(self):
        python = self.runtime / "bin/python"
        python.parent.mkdir(parents=True)
        python.write_text("#!/bin/sh\nexit 0\n")
        python.chmod(0o755)

    def command(self, command, *extra, env=None):
        return subprocess.run(
            [
                str(SYNC), command, "--home", str(self.home), "--source", str(self.source),
                "--runtime", str(self.runtime), *extra,
            ],
            env=env or self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def seed_user_config(self, setup_version=None):
        config = self.home / ".config/toshy"
        config.mkdir(parents=True)
        (config / "toshy_config.py").write_text("# custom config\n")
        (config / "toshy_user_preferences.sqlite").write_bytes(b"preferences")
        (config / "my-unrelated-file.txt").write_text("keep me\n")
        if setup_version:
            (config / "setup_toshy.py").write_text(f"__version__ = '{setup_version}'\n")

    def test_install_preserves_mutable_and_unrelated_files_then_uninstalls_managed_files(self):
        self.seed_user_config()
        result = self.command("install")
        self.assertEqual(result.returncode, 0, result.stderr)
        config = self.home / ".config/toshy"
        self.assertEqual((config / "toshy_config.py").read_text(), "# custom config\n")
        self.assertEqual((config / "toshy_user_preferences.sqlite").read_bytes(), b"preferences")
        self.assertEqual((config / "my-unrelated-file.txt").read_text(), "keep me\n")
        self.assertTrue((self.home / ".local/bin/toshy-status").is_symlink())
        runtime_link = self.home / ".local/state/toshy/runtime"
        self.assertEqual(runtime_link.resolve(), self.runtime.resolve())
        receipt = self.home / ".local/state/fedora-brew/integrations/toshy.json"
        self.assertEqual(json.loads(receipt.read_text())["release"], "26.08.0")

        result = self.command("uninstall")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.home / ".local/bin/toshy-status").exists())
        self.assertFalse(runtime_link.exists())
        self.assertEqual((config / "toshy_config.py").read_text(), "# custom config\n")
        self.assertTrue((config / "my-unrelated-file.txt").is_file())

    def test_dry_run_has_no_side_effects(self):
        self.seed_user_config()
        result = self.command("migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("no files or services were changed", result.stdout)
        self.assertFalse((self.home / ".local/state/fedora-brew").exists())

    def test_newer_manual_install_is_refused_without_changes(self):
        self.seed_user_config("20990101")
        result = self.command("migrate")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("newer than packaged", result.stdout)
        self.assertEqual((self.home / ".config/toshy/toshy_config.py").read_text(), "# custom config\n")

    def test_forced_failure_rolls_back_configuration_and_external_files(self):
        self.seed_user_config()
        env = self.env.copy()
        env["TOSHY_BREW_TEST_FAIL_AFTER_INSTALL"] = "1"
        result = self.command("install", env=env)
        self.assertNotEqual(result.returncode, 0)
        config = self.home / ".config/toshy"
        self.assertEqual((config / "toshy_config.py").read_text(), "# custom config\n")
        self.assertEqual((config / "my-unrelated-file.txt").read_text(), "keep me\n")
        self.assertFalse((self.home / ".local/bin/toshy-status").exists())
        self.assertFalse((self.home / ".local/state/toshy/runtime").exists())


if __name__ == "__main__":
    unittest.main()
