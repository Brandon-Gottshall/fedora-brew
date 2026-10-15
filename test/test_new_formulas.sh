#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# These two products have unrelated namesakes: keep the catalog identities aligned.
grep -Fq 'https://mobile.schmidhuberj.de/flare' "$repo_root/Formula/flare.rb"
grep -Fq 'de.schmidhuberj.Flare.desktop' "$repo_root/Formula/flare.rb"
grep -Fq 'formula: Brandon-Gottshall/linux-formulas/flare' "$repo_root/packages/flare.yaml"
grep -Fq 'https://github.com/vicinaehq/vicinae/releases/download/' "$repo_root/Formula/vicinae.rb"
grep -Fq 'formula: Brandon-Gottshall/linux-formulas/vicinae' "$repo_root/packages/vicinae.yaml"

# Source builds must use the vendored release, not a network-dependent repository archive.
grep -Fq 'packages/generic/flare/' "$repo_root/Formula/flare.rb"
grep -Fq 'ENV["CARGO_NET_OFFLINE"] = "true"' "$repo_root/Formula/flare.rb"
grep -Fq 'ENV["SQLX_OFFLINE"] = "true"' "$repo_root/Formula/flare.rb"
grep -Eq 'sha256 "[0-9a-f]{64}"' "$repo_root/Formula/flare.rb"

# Each supported architecture needs its own pinned artifact; all launcher actions use opt_bin.
[[ "$(grep -Ec 'sha256 "[0-9a-f]{64}"' "$repo_root/Formula/vicinae.rb")" == 2 ]]
grep -Fq 'Vicinae-x86_64.AppImage' "$repo_root/Formula/vicinae.rb"
grep -Fq 'Vicinae-aarch64.AppImage' "$repo_root/Formula/vicinae.rb"
grep -Fq 'system cached_download, "--appimage-extract"' "$repo_root/Formula/vicinae.rb"
grep -Fq '"Exec=#{opt_bin}/vicinae"' "$repo_root/Formula/vicinae.rb"
! grep -Eq 'system .*"(sudo|pacman|dnf|flatpak)"' "$repo_root/Formula/flare.rb" "$repo_root/Formula/vicinae.rb"
