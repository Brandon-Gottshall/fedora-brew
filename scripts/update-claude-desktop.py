#!/usr/bin/env python3
"""Discover and pin Anthropic's latest official Claude Desktop Linux package."""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path

INDEX_URL = (
    "https://downloads.claude.ai/claude-desktop/apt/stable/"
    "dists/stable/main/binary-amd64/Packages"
)
REPOSITORY_URL = "https://downloads.claude.ai/claude-desktop/apt/stable/"
POOL_PREFIX = "pool/main/c/claude-desktop/claude-desktop_"


@dataclass(frozen=True)
class Release:
    version: str
    filename: str
    digest: str

    @property
    def url(self) -> str:
        return urllib.parse.urljoin(REPOSITORY_URL, self.filename)


def version_key(version: str) -> tuple[int, ...]:
    if re.fullmatch(r"\d+(?:\.\d+)+", version) is None:
        raise ValueError(f"unexpected Claude Desktop version: {version}")
    return tuple(int(part) for part in version.split("."))


def parse_index(contents: str) -> Release:
    releases: list[Release] = []
    for stanza in re.split(r"\n\s*\n", contents.strip()):
        fields: dict[str, str] = {}
        for line in stanza.splitlines():
            if ": " in line:
                key, value = line.split(": ", 1)
                fields[key] = value
        if fields.get("Package") != "claude-desktop" or fields.get("Architecture") != "amd64":
            continue
        version = fields.get("Version", "")
        filename = fields.get("Filename", "")
        digest = fields.get("SHA256", "")
        version_key(version)
        expected_filename = f"{POOL_PREFIX}{version}_amd64.deb"
        if filename != expected_filename:
            raise ValueError(f"unexpected artifact path for {version}: {filename}")
        if re.fullmatch(r"[0-9a-f]{64}", digest) is None:
            raise ValueError(f"invalid SHA-256 for {version}")
        releases.append(Release(version, filename, digest))
    if not releases:
        raise ValueError("official index contains no amd64 claude-desktop release")
    return max(releases, key=lambda release: version_key(release.version))


def fetch_text(url: str) -> str:
    request = urllib.request.Request(url, headers={"User-Agent": "linux-formulas-updater/1"})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode("utf-8")


def verify_artifact(release: Release, artifact: Path | None = None) -> None:
    digest = hashlib.sha256()
    if artifact is not None:
        with artifact.open("rb") as source:
            while chunk := source.read(1024 * 1024):
                digest.update(chunk)
    else:
        request = urllib.request.Request(
            release.url, headers={"User-Agent": "linux-formulas-updater/1"}
        )
        with urllib.request.urlopen(request, timeout=180) as response:
            while chunk := response.read(1024 * 1024):
                digest.update(chunk)
    if digest.hexdigest() != release.digest:
        raise ValueError("artifact SHA-256 does not match Anthropic's package index")


def update_formula(path: Path, release: Release) -> bool:
    original = path.read_text()
    updated, url_count = re.subn(
        r'  url "[^"]+"', f'  url "{release.url}"', original, count=1
    )
    updated, version_count = re.subn(
        r'  version "[^"]+"', f'  version "{release.version}"', updated, count=1
    )
    updated, hash_count = re.subn(
        r'  sha256 "[0-9a-f]{64}"', f'  sha256 "{release.digest}"', updated, count=1
    )
    if (url_count, version_count, hash_count) != (1, 1, 1):
        raise ValueError("formula shape changed; refusing partial update")
    previous_version = re.search(r'^  version "([^"\n]+)"', original, re.MULTILINE)
    if previous_version and previous_version.group(1) != release.version:
        updated = re.sub(r'^  revision \d+\n', '', updated, flags=re.MULTILINE)
    if updated == original:
        return False
    path.write_text(updated)
    return True


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--formula",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "Formula/claude-desktop.rb",
    )
    parser.add_argument("--packages", type=Path, help="use an existing Packages index")
    parser.add_argument("--artifact", type=Path, help="use an existing package for verification")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    index = args.packages.read_text() if args.packages else fetch_text(INDEX_URL)
    release = parse_index(index)
    verify_artifact(release, args.artifact)

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
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
