#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formula="$repo_root/Formula/claude-desktop.rb"
manifest="$repo_root/packages/claude-desktop.yaml"

# Versions are bumped by scripts/update-claude-desktop.py; assert consistency, not a pinned value.
version="$(sed -nE 's/^[[:space:]]*version "([0-9.]+)"/\1/p' "$formula")"
[[ -n "$version" ]]
grep -Fq "claude-desktop_${version}_amd64.deb" "$formula"
grep -Eq '^[[:space:]]*sha256 "[0-9a-f]{64}"' "$formula"
grep -Fq 'downloads.claude.ai/claude-desktop/apt/stable/pool/' "$formula"
grep -Fq 'Exec=#{opt_bin}/claude-desktop' "$formula"
grep -Fq 'system "ar", "x", cached_download' "$formula"
! grep -Eq 'system .*(apt|dnf|flatpak|sudo|dpkg)' "$formula"
! grep -Eq '(postinst|postrm)' "$formula"

grep -Fq 'default: brew' "$manifest"
grep -Fq 'formula: Brandon-Gottshall/fedora-brew/claude-desktop' "$manifest"
