#!/usr/bin/env bash
# test/test_brew_wrapper.sh: routing tests for scripts/shell/brew.bash using
# stub brew and flatpak executables that log their arguments.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d "/tmp/linux-formulas-wrapper.XXXXXX")"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
for tool in brew flatpak; do
    printf '#!/bin/sh\necho "%s $*" >> "%s/calls"\n' "$tool" "$work" > "$work/bin/$tool"
    chmod +x "$work/bin/$tool"
done
export PATH="$work/bin:$PATH"
# shellcheck source=../scripts/shell/brew.bash
. "$repo_root/scripts/shell/brew.bash"

expect() {
    local description="$1"; shift
    : > "$work/calls"
    "$@"
    local expected actual
    expected="$(cat)"
    actual="$(cat "$work/calls")"
    if [[ "$actual" != "$expected" ]]; then
        printf 'FAIL %s\n--- expected\n%s\n--- actual\n%s\n' "$description" "$expected" "$actual" >&2
        exit 1
    fi
    printf 'PASS %s\n' "$description"
}

expect "install routes plain names through brew app" brew install claude moonlight <<'OUT'
brew app install claude
brew app install moonlight
OUT

expect "install passes brew app options along" brew install tool --flatpak -y <<'OUT'
brew app install tool --flatpak -y
OUT

expect "Homebrew-only options and tap names go to Homebrew" brew install --cask firefox <<'OUT'
brew install --cask firefox
OUT

expect "tap-qualified names go to Homebrew" brew install owner/tap/tool <<'OUT'
brew install owner/tap/tool
OUT

expect "bare upgrade updates Homebrew, Flatpak and brew app" brew upgrade -y <<'OUT'
brew upgrade
flatpak update -y
brew app upgrade
OUT

expect "dry-run upgrade only previews" brew upgrade --dry-run <<'OUT'
brew upgrade --dry-run
flatpak remote-ls --updates
brew app upgrade --dry-run
OUT

expect "named upgrade goes through brew app" brew upgrade moonlight <<'OUT'
brew app upgrade moonlight
OUT

expect "other subcommands pass through" brew info gh <<'OUT'
brew info gh
OUT

printf '==> All brew wrapper tests passed.\n'
