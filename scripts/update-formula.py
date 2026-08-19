#!/usr/bin/env python3
"""Discover and pin the current official Antigravity 2.x Linux x64 release."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import re
import sys
import urllib.request
from dataclasses import dataclass
from pathlib import Path

DOWNLOAD_PAGE = "https://antigravity.google/download"
ARTIFACT_RE = re.compile(
    r"https://storage\.googleapis\.com/antigravity-public/antigravity-hub/"
    r"(?P<version>2\.\d+\.\d+)-(?P<build>\d+)/linux-x64/Antigravity\.tar\.gz"
)


@dataclass(frozen=True)
class Release:
    version: str
    build: str
    url: str


def fetch(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"Accept-Encoding": "gzip", "User-Agent": "fedora-brew-updater/1"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        body = response.read()
        if response.headers.get("Content-Encoding") == "gzip":
            body = gzip.decompress(body)
        return body


def discover(html: str) -> Release:
    matches = {
        (match.group("version"), match.group("build"), match.group(0))
        for match in ARTIFACT_RE.finditer(html)
    }
    if len(matches) != 1:
        raise ValueError(
            f"expected exactly one Antigravity 2.x Linux x64 artifact, found {len(matches)}"
        )
    version, build, url = matches.pop()
    return Release(version=version, build=build, url=url)


def sha256(url: str) -> str:
    digest = hashlib.sha256()
    request = urllib.request.Request(url, headers={"User-Agent": "fedora-brew-updater/1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        while chunk := response.read(1024 * 1024):
            digest.update(chunk)
    return digest.hexdigest()


def update_formula(path: Path, release: Release, digest: str) -> bool:
    original = path.read_text()
    updated, url_count = re.subn(
        r'  url "https://storage\.googleapis\.com/antigravity-public/'
        r'antigravity-hub/2\.\d+\.\d+-\d+/linux-x64/Antigravity\.tar\.gz"',
        f'  url "{release.url}"',
        original,
    )
    updated, hash_count = re.subn(
        r'  sha256 "[0-9a-f]{64}"',
        f'  sha256 "{digest}"',
        updated,
        count=1,
    )
    if (url_count, hash_count) != (1, 1):
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
        default=Path(__file__).resolve().parents[1] / "Formula/antigravity.rb",
    )
    parser.add_argument("--check", action="store_true", help="report only; do not edit")
    parser.add_argument("--html-file", type=Path, help="use a local page fixture")
    args = parser.parse_args()

    page = args.html_file.read_text() if args.html_file else fetch(DOWNLOAD_PAGE).decode()
    release = discover(page)
    formula = args.formula.read_text()
    current = re.search(r"/antigravity-hub/(2\.\d+\.\d+)-\d+/linux-x64/", formula)
    if current is None:
        raise ValueError("formula artifact version is missing")
    print(f"official={release.version} build={release.build} current={current.group(1)}")
    if args.check or current.group(1) == release.version:
        return 0

    digest = sha256(release.url)
    changed = update_formula(args.formula, release, digest)
    print(f"updated={changed} sha256={digest}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
