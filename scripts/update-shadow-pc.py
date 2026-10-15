#!/usr/bin/env python3
"""Discover and pin the official Shadow PC Linux AppImage."""

from __future__ import annotations

import argparse
import hashlib
import re
import stat
import subprocess
import sys
import tempfile
import urllib.request
from dataclasses import dataclass
from pathlib import Path

DOWNLOAD_URL = "https://update.shadow.tech/launcher/prod/linux/ubuntu_18.04/ShadowPC.AppImage"
VERSION_RE = re.compile(r"^X-AppImage-Version=(\S+)$", re.MULTILINE)


@dataclass(frozen=True)
class Release:
    version: str
    digest: str


def download(url: str, destination: Path) -> str:
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "linux-formulas-updater/1"})
    with urllib.request.urlopen(request, timeout=180) as response, destination.open("wb") as output:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
            output.write(chunk)
    destination.chmod(destination.stat().st_mode | stat.S_IXUSR)
    return digest.hexdigest()


def extract_version(appimage: Path, working_dir: Path) -> str:
    subprocess.run(
        [str(appimage), "--appimage-extract"],
        cwd=working_dir,
        check=True,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
    )
    desktop = (working_dir / "squashfs-root/shadow-launcher.desktop").read_text()
    match = VERSION_RE.search(desktop)
    if match is None:
        raise ValueError("AppImage desktop file has no X-AppImage-Version")
    return match.group(1)


def update_formula(path: Path, release: Release) -> bool:
    original = path.read_text()
    updated, version_count = re.subn(
        r'  version "[^"]+"', f'  version "{release.version}"', original, count=1
    )
    updated, hash_count = re.subn(
        r'  sha256 "[0-9a-f]{64}"', f'  sha256 "{release.digest}"', updated, count=1
    )
    if (version_count, hash_count) != (1, 1):
        raise ValueError("formula shape changed; refusing partial update")
    if updated == original:
        return False
    path.write_text(updated)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--formula",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "Formula/shadow-pc.rb",
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--appimage", type=Path, help="use an existing AppImage")
    args = parser.parse_args()

    with tempfile.TemporaryDirectory(prefix="shadow-update-") as temporary:
        work = Path(temporary)
        artifact = args.appimage or work / "ShadowPC.AppImage"
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest() if args.appimage else download(DOWNLOAD_URL, artifact)
        release = Release(extract_version(artifact, work), digest)

    current = re.search(r'  version "([^"]+)"', args.formula.read_text())
    if current is None:
        raise ValueError("formula version is missing")
    print(f"official={release.version} current={current.group(1)} sha256={release.digest}")
    if args.check:
        return 0
    print(f"updated={update_formula(args.formula, release)}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
