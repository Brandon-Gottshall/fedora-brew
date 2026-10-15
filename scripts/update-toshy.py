#!/usr/bin/env python3
"""Update Toshy runtime formula and cask as one release unit."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

API_URL = "https://api.github.com/repos/RedBearAK/toshy/releases/latest"
TAG_RE = re.compile(r"^Toshy_v(?P<version>\d+(?:\.\d+)+)$")


@dataclass(frozen=True)
class Release:
    version: str
    tag: str
    archive_url: str


def fetch_json(url: str) -> dict:
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json", "User-Agent": "fedora-brew-updater/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


def discover(payload: dict) -> Release:
    tag = payload.get("tag_name", "")
    match = TAG_RE.fullmatch(tag)
    if match is None or payload.get("draft") or payload.get("prerelease"):
        raise ValueError(f"latest GitHub release is not a stable Toshy tag: {tag!r}")
    return Release(
        match.group("version"), tag,
        f"https://github.com/RedBearAK/toshy/archive/refs/tags/{tag}.tar.gz",
    )


def sha256(url: str) -> str:
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "fedora-brew-updater/1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def current_pin(text: str) -> tuple[str, str]:
    version = re.search(r'  version "([^"]+)"', text)
    digest = re.search(r'  sha256 "([0-9a-f]{64})"', text)
    if version is None or digest is None:
        raise ValueError("package definition is missing its version or primary checksum")
    return version.group(1), digest.group(1)


def update_definition(text: str, release: Release, digest: str, *, formula: bool) -> str:
    updated, version_count = re.subn(r'  version "[^"]+"', f'  version "{release.version}"', text, count=1)
    updated, hash_count = re.subn(r'  sha256 "[0-9a-f]{64}"', f'  sha256 "{digest}"', updated, count=1)
    if formula:
        updated, url_count = re.subn(
            r'  url "https://github\.com/RedBearAK/toshy/archive/refs/tags/Toshy_v[^"/]+\.tar\.gz"',
            f'  url "{release.archive_url}"', updated, count=1,
        )
    else:
        url_count = 1
    if (version_count, hash_count, url_count) != (1, 1, 1):
        raise ValueError("package definition shape changed; refusing partial update")
    return updated


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--formula", type=Path, default=root / "Formula/toshy-runtime.rb")
    parser.add_argument("--cask", type=Path, default=root / "Casks/toshy.rb")
    parser.add_argument("--release-json", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    formula_text = args.formula.read_text()
    cask_text = args.cask.read_text()
    formula_pin = current_pin(formula_text)
    cask_pin = current_pin(cask_text)
    if formula_pin != cask_pin:
        raise ValueError(f"Toshy formula/cask pins differ: {formula_pin} != {cask_pin}")

    payload = json.loads(args.release_json.read_text()) if args.release_json else fetch_json(API_URL)
    release = discover(payload)
    print(f"official={release.version} current={formula_pin[0]}")
    if args.check or release.version == formula_pin[0]:
        return 0
    digest = sha256(release.archive_url)
    args.formula.write_text(update_definition(formula_text, release, digest, formula=True))
    args.cask.write_text(update_definition(cask_text, release, digest, formula=False))
    print(f"updated=true sha256={digest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
