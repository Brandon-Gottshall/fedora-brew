#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formula="$repo_root/Formula/antigravity.rb"

grep -Fq 'version "2.8.1"' "$formula"
grep -Fq 'depends_on arch: :x86_64' "$formula"
grep -Fq 'depends_on :linux' "$formula"
grep -Fq 'DISABLE_AUTO_UPDATE: "1"' "$formula"
grep -Fq 'Exec=#{opt_bin}/antigravity %U' "$formula"
grep -Fq 'Terminal=false' "$formula"
! grep -Eq 'system .*(dnf|flatpak|sudo)' "$formula"
