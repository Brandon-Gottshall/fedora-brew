#!/usr/bin/env python3
"""Noninteractive Homebrew lifecycle integration for Toshy."""

from __future__ import annotations

import argparse
import fcntl
import grp
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path

RELEASE = "26.08.0"
SERVICES = (
    "toshy-cosmic-dbus.service",
    "toshy-kwin-dbus.service",
    "toshy-wlroots-dbus.service",
    "toshy-config.service",
    "toshy-session-monitor.service",
)
MUTABLE_CONFIG = ("toshy_config.py", "toshy_user_preferences.sqlite")
SOURCE_IGNORES = {
    ".git", ".git_hooks", ".github", ".gitignore", "CONTRIBUTING.md",
    "DO_NOT_USE_requirements.txt", "LICENSE", "README.md", "flake.lock",
    "flake.nix", "nix", "packages.json", "requirements.txt", "setup_toshy.py",
    "tests", "vendors",
}
DESKTOP_FILES = ("app.toshy.preferences.desktop", "Toshy_Tray.desktop")
ICON_FILES = (
    "toshy_app_icon_rainbow_inverse_grayscale.svg",
    "toshy_app_icon_rainbow_inverse.svg",
    "toshy_app_icon_rainbow.svg",
)
VERSION_PATTERNS = {
    "setup": ("setup_toshy.py", r"^__version__\s*=\s*['\"]([^'\"]+)"),
    "runtime-env": (
        "scripts/toshy-runtime-env.sh",
        r"^TOSHY_RUNTIME_ENV_VERSION=['\"]([^'\"]+)",
    ),
    "xwaykeyz": (
        "vendors/xwaykeyz-main/src/xwaykeyz/version.py",
        r"^__version__\s*=\s*['\"]([^'\"]+)",
    ),
}


class SyncError(RuntimeError):
    pass


@dataclass
class Context:
    home: Path
    source: Path
    runtime: Path
    dry_run: bool = False
    state_root: Path = field(init=False)
    config: Path = field(init=False)
    receipt: Path = field(init=False)
    runtime_link: Path = field(init=False)

    def __post_init__(self) -> None:
        self.home = self.home.resolve()
        self.source = self.source.resolve()
        self.runtime = self.runtime.resolve()
        self.state_root = Path(os.environ.get("XDG_STATE_HOME", self.home / ".local/state")) / "linux-formulas"
        self.config = self.home / ".config/toshy"
        self.receipt = self.state_root / "integrations/toshy.json"
        self.runtime_link = Path(os.environ.get("XDG_STATE_HOME", self.home / ".local/state")) / "toshy/runtime"


def run(command: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=check)


def systemctl(*args: str, check: bool = False) -> subprocess.CompletedProcess[str]:
    return run([os.environ.get("SYSTEMCTL_BIN", "systemctl"), "--user", *args], check=check)


def parse_version_file(root: Path, component: str) -> str | None:
    relative, pattern = VERSION_PATTERNS[component]
    path = root / relative
    if not path.is_file():
        return None
    match = re.search(pattern, path.read_text(errors="replace"), re.MULTILINE)
    return match.group(1) if match else None


def version_key(value: str) -> tuple[int, ...]:
    return tuple(int(part) for part in re.findall(r"\d+", value))


def installed_xwaykeyz_version(config: Path) -> str | None:
    python = config / ".venv/bin/python"
    if not python.is_file():
        return None
    result = run(
        [str(python), "-c", "from xwaykeyz.version import __version__; print(__version__)"],
        check=False,
    )
    return result.stdout.strip() if result.returncode == 0 else None


def runtime_import_check(runtime: Path) -> str | None:
    python = runtime / "bin/python"
    if not python.is_file() or not os.access(python, os.X_OK):
        return f"runtime interpreter is missing or not executable: {python}"
    imports = "import dbus, gi, psutil, watchdog, xkbcommon, systemd, xwaykeyz"
    result = run([str(python), "-c", imports], check=False)
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1] if result.stderr.strip() else "unknown import error"
        return f"runtime import check failed: {detail}"
    return None


def input_access_errors() -> list[str]:
    if os.environ.get("TOSHY_BREW_TEST_INPUT_OK") == "1":
        return []
    errors: list[str] = []
    try:
        input_group = grp.getgrnam("input")
        member = os.getegid() == input_group.gr_gid or input_group.gr_gid in os.getgroups()
    except KeyError:
        member = False
    if not member:
        errors.append("current user is not a member of the input group")
    uinput = Path(os.environ.get("TOSHY_BREW_UINPUT_PATH", "/dev/uinput"))
    if not uinput.exists() or not os.access(uinput, os.R_OK | os.W_OK):
        errors.append(f"uinput is unavailable to the current user: {uinput}")
    return errors


def writable_parent(path: Path) -> bool:
    candidate = path
    while not candidate.exists() and candidate != candidate.parent:
        candidate = candidate.parent
    return candidate.is_dir() and os.access(candidate, os.W_OK)


def load_receipt(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as error:
        raise SyncError(f"invalid Toshy integration receipt: {error}") from error
    if not isinstance(value, dict):
        raise SyncError("invalid Toshy integration receipt: expected an object")
    return value


def preflight(ctx: Context) -> list[str]:
    errors: list[str] = []
    if not ctx.source.is_dir():
        errors.append(f"Toshy source directory is missing: {ctx.source}")
        return errors

    packaged = {name: parse_version_file(ctx.source, name) for name in VERSION_PATTERNS}
    for name, value in packaged.items():
        if value is None:
            errors.append(f"packaged {name} component version is missing")

    if ctx.config.exists():
        installed = {
            "setup": parse_version_file(ctx.config, "setup"),
            "runtime-env": parse_version_file(ctx.config, "runtime-env"),
            "xwaykeyz": installed_xwaykeyz_version(ctx.config),
        }
        for name, current in installed.items():
            target = packaged.get(name)
            if current and target and version_key(current) > version_key(target):
                errors.append(f"installed {name} {current} is newer than packaged {target}")

    runtime_error = runtime_import_check(ctx.runtime)
    if runtime_error:
        errors.append(runtime_error)
    errors.extend(input_access_errors())
    if systemctl("show-environment").returncode != 0:
        errors.append("systemd user manager is unavailable")
    if not writable_parent(ctx.state_root):
        errors.append(f"backup state directory is not writable: {ctx.state_root}")
    if ctx.runtime_link.exists() and not ctx.runtime_link.is_symlink():
        errors.append(f"runtime path exists and is not a symlink: {ctx.runtime_link}")

    for path in managed_external_paths(ctx).values():
        try:
            path.relative_to(ctx.home)
        except ValueError:
            errors.append(f"managed path escapes the user home: {path}")
    return errors


def source_files(source: Path) -> list[Path]:
    files: list[Path] = []
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        if any(part in SOURCE_IGNORES or part == "__pycache__" for part in relative.parts):
            continue
        if path.is_file() or path.is_symlink():
            files.append(relative)
    return sorted(files)


def command_links(ctx: Context) -> dict[str, Path]:
    links: dict[str, Path] = {}
    scripts = ctx.source / "scripts/bin"
    if not scripts.is_dir():
        return links
    for script in sorted(scripts.glob("toshy-*.sh")):
        links[f"bin/{script.stem}"] = ctx.home / ".local/bin" / script.stem
    return links


def managed_external_paths(ctx: Context) -> dict[str, Path]:
    paths = {
        **{f"service/{name}": ctx.home / ".config/systemd/user" / name for name in SERVICES},
        "autostart/Toshy_Import_Vars.desktop": ctx.home / ".config/autostart/Toshy_Import_Vars.desktop",
        **{f"desktop/{name}": ctx.home / ".local/share/applications" / name for name in DESKTOP_FILES},
        **{
            f"icon/{name}": ctx.home / ".local/share/icons/hicolor/scalable/apps" / name
            for name in ICON_FILES
        },
    }
    paths.update(command_links(ctx))
    return paths


def file_digest(path: Path) -> str:
    if path.is_symlink():
        return "symlink:" + os.readlink(path)
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        while chunk := stream.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def service_state() -> dict[str, dict[str, bool]]:
    state: dict[str, dict[str, bool]] = {}
    for service in SERVICES:
        active = systemctl("is-active", "--quiet", service).returncode == 0
        enabled = systemctl("is-enabled", "--quiet", service).returncode == 0
        state[service] = {"active": active, "enabled": enabled}
    return state


def stop_active_services(state: dict[str, dict[str, bool]]) -> None:
    for service, flags in state.items():
        if flags["active"]:
            systemctl("stop", service, check=True)


def restore_service_state(state: dict[str, dict[str, bool]]) -> None:
    systemctl("daemon-reload", check=True)
    for service, flags in state.items():
        systemctl("enable" if flags["enabled"] else "disable", service, check=False)
        if flags["active"]:
            systemctl("start", service, check=True)


def backup_external(ctx: Context, backup: Path, paths: dict[str, Path]) -> dict[str, str]:
    present: dict[str, str] = {}
    for name, path in paths.items():
        if not path.exists() and not path.is_symlink():
            continue
        target = backup / "external" / path.relative_to(ctx.home)
        target.parent.mkdir(parents=True, exist_ok=True)
        if path.is_symlink():
            target.symlink_to(os.readlink(path))
        else:
            shutil.copy2(path, target)
        present[name] = str(target)
    return present


def install_external(ctx: Context, paths: dict[str, Path]) -> dict[str, str]:
    digests: dict[str, str] = {}
    for name, destination in paths.items():
        destination.parent.mkdir(parents=True, exist_ok=True)
        if name.startswith("service/"):
            source = ctx.config / "systemd-user-service-units" / destination.name
            shutil.copy2(source, destination)
        elif name.startswith("autostart/"):
            source = ctx.config / "desktop" / destination.name
            shutil.copy2(source, destination)
        elif name.startswith("desktop/"):
            source = ctx.config / "desktop" / destination.name
            destination.write_text(source.read_text().replace("$HOME", str(ctx.home)))
        elif name.startswith("icon/"):
            shutil.copy2(ctx.config / "assets" / destination.name, destination)
        elif name.startswith("bin/"):
            script = ctx.config / "scripts/bin" / f"{destination.name}.sh"
            if destination.exists() or destination.is_symlink():
                destination.unlink()
            destination.symlink_to(script)
        digests[str(destination)] = file_digest(destination)
    return digests


def stage_config(ctx: Context, old_receipt: dict) -> tuple[Path, list[str]]:
    ctx.config.parent.mkdir(parents=True, exist_ok=True)
    stage = Path(tempfile.mkdtemp(prefix=".toshy-linux-formulas-stage-", dir=ctx.config.parent))
    if ctx.config.is_dir():
        shutil.copytree(ctx.config, stage, symlinks=True, dirs_exist_ok=True)
    for relative in old_receipt.get("managed_config_paths", []):
        candidate = stage / relative
        if candidate.is_file() or candidate.is_symlink():
            candidate.unlink()
    preserved: dict[str, bytes] = {}
    for relative in MUTABLE_CONFIG:
        path = ctx.config / relative
        if path.is_file():
            preserved[relative] = path.read_bytes()
    legacy_venv = stage / ".venv"
    if legacy_venv.exists():
        shutil.rmtree(legacy_venv)

    managed = source_files(ctx.source)
    for relative in managed:
        source = ctx.source / relative
        destination = stage / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        if source.is_symlink():
            if destination.exists() or destination.is_symlink():
                destination.unlink()
            destination.symlink_to(os.readlink(source))
        else:
            shutil.copy2(source, destination)
    default_config = stage / "default-toshy-config/toshy_config.py"
    if "toshy_config.py" not in preserved and default_config.is_file():
        preserved["toshy_config.py"] = default_config.read_bytes()
    for relative, content in preserved.items():
        (stage / relative).write_bytes(content)
    return stage, [str(path) for path in managed if str(path) not in MUTABLE_CONFIG]


def install(ctx: Context) -> None:
    errors = preflight(ctx)
    print(f"Toshy {RELEASE} migration preflight")
    for error in errors:
        print(f"BLOCKED: {error}")
    if errors:
        raise SyncError(f"preflight failed with {len(errors)} blocker(s)")

    paths = managed_external_paths(ctx)
    print(f"Source: {ctx.source}")
    print(f"Runtime: {ctx.runtime}")
    print(f"Configuration: {ctx.config}")
    print(f"Managed external paths: {len(paths)}")
    if ctx.dry_run:
        print("Dry run complete; no files or services were changed.")
        return

    ctx.state_root.mkdir(parents=True, exist_ok=True)
    lock_path = ctx.state_root / "toshy.lock"
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        old_receipt = load_receipt(ctx.receipt)
        prior_states = service_state()
        target_states = prior_states
        if not ctx.config.exists():
            target_states = {service: {"active": True, "enabled": True} for service in SERVICES}
        timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        backup = ctx.state_root / "backups/toshy" / timestamp
        backup.mkdir(parents=True)
        stage, managed_config = stage_config(ctx, old_receipt)
        external_backup = backup_external(ctx, backup, paths)
        previous_runtime = os.readlink(ctx.runtime_link) if ctx.runtime_link.is_symlink() else None
        previous_config = backup / "config"

        try:
            stop_active_services(prior_states)
            if ctx.config.exists():
                os.replace(ctx.config, previous_config)
            os.replace(stage, ctx.config)

            ctx.runtime_link.parent.mkdir(parents=True, exist_ok=True)
            temporary_link = ctx.runtime_link.with_name(f"runtime.new-{os.getpid()}")
            temporary_link.symlink_to(ctx.runtime)
            os.replace(temporary_link, ctx.runtime_link)

            external_digests = install_external(ctx, paths)
            if os.environ.get("TOSHY_BREW_TEST_FAIL_AFTER_INSTALL") == "1":
                raise SyncError("forced lifecycle failure")
            restore_service_state(target_states)
            receipt = {
                "schema": 1,
                "release": RELEASE,
                "installed_at": datetime.now(timezone.utc).isoformat(),
                "source_versions": {name: parse_version_file(ctx.source, name) for name in VERSION_PATTERNS},
                "runtime_target": str(ctx.runtime),
                "backup": str(backup),
                "previous_runtime_target": previous_runtime,
                "prior_services": prior_states,
                "managed_config_paths": managed_config,
                "managed_external": external_digests,
                "external_backup": external_backup,
            }
            ctx.receipt.parent.mkdir(parents=True, exist_ok=True)
            temporary_receipt = ctx.receipt.with_suffix(".json.new")
            temporary_receipt.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
            os.replace(temporary_receipt, ctx.receipt)
        except Exception:
            if ctx.config.exists():
                failed = backup / "failed-config"
                os.replace(ctx.config, failed)
            if previous_config.exists():
                os.replace(previous_config, ctx.config)
            for destination in paths.values():
                if destination.exists() or destination.is_symlink():
                    destination.unlink()
            for name, backup_path in external_backup.items():
                destination = paths[name]
                saved = Path(backup_path)
                destination.parent.mkdir(parents=True, exist_ok=True)
                if saved.is_symlink():
                    destination.symlink_to(os.readlink(saved))
                else:
                    shutil.copy2(saved, destination)
            if previous_runtime is not None:
                replacement = ctx.runtime_link.with_name(f"runtime.rollback-{os.getpid()}")
                replacement.symlink_to(previous_runtime)
                os.replace(replacement, ctx.runtime_link)
            elif ctx.runtime_link.is_symlink():
                ctx.runtime_link.unlink()
            restore_service_state(prior_states)
            raise
    print(f"Toshy integration installed. Rollback snapshot: {backup}")


def uninstall(ctx: Context) -> None:
    receipt = load_receipt(ctx.receipt)
    if not receipt:
        print("No Homebrew Toshy integration receipt found; nothing removed.")
        return
    states = service_state()
    stop_active_services(states)
    for raw_path, digest in receipt.get("managed_external", {}).items():
        path = Path(raw_path)
        if not path.exists() and not path.is_symlink():
            continue
        if file_digest(path) != digest:
            print(f"Preserving modified managed file: {path}", file=sys.stderr)
            continue
        path.unlink()
    for relative in receipt.get("managed_config_paths", []):
        path = ctx.config / relative
        if path.is_file() or path.is_symlink():
            path.unlink()
    expected_runtime = receipt.get("runtime_target")
    if ctx.runtime_link.is_symlink() and str(ctx.runtime_link.resolve()) == expected_runtime:
        ctx.runtime_link.unlink()
    systemctl("daemon-reload", check=False)
    ctx.receipt.unlink()
    print("Removed Homebrew-managed Toshy integration; user configuration and backups were preserved.")


def doctor(ctx: Context) -> int:
    errors = preflight(ctx)
    if not ctx.config.joinpath("toshy_config.py").is_file():
        errors.append(f"user configuration is missing: {ctx.config / 'toshy_config.py'}")
    if not ctx.receipt.is_file():
        errors.append(f"integration receipt is missing: {ctx.receipt}")
    if not ctx.runtime_link.is_symlink() or ctx.runtime_link.resolve() != ctx.runtime:
        errors.append(f"runtime link does not select {ctx.runtime}")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Toshy {RELEASE} Homebrew integration is healthy.")
    return 0


def default_prefix() -> Path:
    executable = Path(sys.argv[0]).resolve()
    return executable.parent.parent


def main() -> int:
    invoked_as = Path(sys.argv[0]).name
    implicit_doctor = invoked_as == "toshy-brew-doctor"
    parser = argparse.ArgumentParser()
    parser.add_argument("command", nargs="?", choices=("install", "migrate", "uninstall", "doctor"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--source", type=Path, default=default_prefix() / "libexec/source")
    parser.add_argument("--runtime", type=Path, default=default_prefix() / "libexec/runtime")
    args = parser.parse_args()
    command = "doctor" if implicit_doctor and args.command is None else args.command
    if command is None:
        parser.error("a command is required")
    ctx = Context(args.home, args.source, args.runtime, args.dry_run or command == "migrate")
    if command in ("install", "migrate"):
        install(ctx)
        return 0
    if command == "uninstall":
        uninstall(ctx)
        return 0
    return doctor(ctx)


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, SyncError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
