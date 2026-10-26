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

expect "bare upgrade upgrades everything through brew app" brew upgrade -y <<'OUT'
brew app upgrade -y
OUT

expect "dry-run upgrade only previews" brew upgrade --dry-run <<'OUT'
brew app upgrade --dry-run
OUT

expect "Homebrew-only upgrade options stay with Homebrew" brew upgrade --greedy <<'OUT'
brew upgrade --greedy
OUT

expect "named upgrade goes through brew app" brew upgrade moonlight kwin <<'OUT'
brew app upgrade moonlight
brew app upgrade kwin
OUT

expect "uninstall and its aliases route by owner" brew rm moonlight <<'OUT'
brew app uninstall moonlight
OUT

expect "list and outdated cover every manager" brew list <<'OUT'
brew app list
OUT

expect "outdated covers every manager" brew outdated <<'OUT'
brew app outdated
OUT

expect "list with a name stays with Homebrew" brew list gh <<'OUT'
brew list gh
OUT

expect "info and search go through brew app" brew info ark <<'OUT'
brew app info ark
OUT

expect "search goes through brew app" brew search moonlight <<'OUT'
brew app search moonlight
OUT

expect "Homebrew JSON info stays with Homebrew" brew info --json=v2 gh <<'OUT'
brew info --json=v2 gh
OUT

expect "other subcommands pass through" brew doctor <<'OUT'
brew doctor
OUT

printf '==> All brew wrapper tests passed.\n'
