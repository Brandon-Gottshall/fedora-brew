#!/usr/bin/env bash
# Integration check: run against a tap containing this checkout's current files.
# Override JUMP_DESKTOP_TEST_TAP to test a separate disposable tap.
set -euo pipefail
export HOMEBREW_NO_AUTO_UPDATE=1

tap="${JUMP_DESKTOP_TEST_TAP:-Brandon-Gottshall/fedora-brew}"
command -v brew >/dev/null
command -v node >/dev/null

assert_formula() {
  node -e '
    const assert = require("node:assert/strict");
    const info = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
    assert.equal(info.formulae.length, 1);
    assert.equal(info.formulae[0].name, "jump-desktop");
    assert.equal(info.casks.length, 0);
  '
}
assert_cask() {
  node -e '
    const assert = require("node:assert/strict");
    const info = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
    assert.equal(info.formulae.length, 0);
    assert.equal(info.casks.length, 1);
    assert.equal(info.casks[0].token, "jump-desktop-mac");
  '
}

# Do not test unqualified jump-desktop: Homebrew core's macOS cask owns that
# token and takes precedence over third-party formulae even on Linux.
brew info --json=v2 --formula "$tap/jump-desktop" | assert_formula
brew info --json=v2 "$tap/jump-desktop" | assert_formula
brew info --json=v2 --cask "$tap/jump-desktop-mac" | assert_cask
# Existing macOS cask requests must migrate without renaming the Linux formula.
brew info --json=v2 --cask "$tap/jump-desktop" | assert_cask
printf 'Jump Desktop Homebrew resolution tests passed.\n'
