#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
formula="$repo_root/Formula/shadow-pc.rb"
migration="$repo_root/scripts/migrate-shadow-pc"
test_root="$(mktemp -d /tmp/linux-formulas-shadow-test.XXXXXX)"
trap 'rm -rf "$test_root"' EXIT

grep -Fq 'version "9.9.10457.17055"' "$formula"
grep -Fq 'sha256 "5dc931780f2b58fe12b5b4f8d59adb13b838ced352ddb6cc361edbba102aab11"' "$formula"
grep -Fq -- '--no-sandbox "$@"' "$formula"
grep -Fq 'export APPDIR="#{opt_libexec}"' "$formula"
grep -Fq 'resources/app-update.yml' "$formula"
! grep -Eq 'system .*(dnf|flatpak|sudo)' "$formula"

artifact="$test_root/ShadowPC.appimage"
printf 'known test artifact\n' > "$artifact"
digest="$(sha256sum "$artifact" | awk '{print $1}')"

HOME="$test_root/home" \
SHADOW_PC_EXPECTED_SHA256="$digest" \
"$migration" --dry-run --source "$artifact" | grep -Fq 'no files or packages were changed'
[[ -f "$artifact" ]]

if HOME="$test_root/home" SHADOW_PC_EXPECTED_SHA256="$(printf '0%.0s' {1..64})" \
  "$migration" --dry-run --source "$artifact" >/dev/null 2>&1; then
  printf 'migration accepted an unknown checksum\n' >&2
  exit 1
fi
[[ -f "$artifact" ]]
