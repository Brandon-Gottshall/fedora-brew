#!/usr/bin/env bash
# test/test_app_manager.sh: Integration and unit tests for Fedora Brew App Manager

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_config_dir="$(mktemp -d "/tmp/fedora-brew-test-config.XXXXXX")"
trap 'rm -rf "$test_config_dir"' EXIT

export HOMEBREW_FEDORA_BREW_CONFIG_DIR="$test_config_dir"
export FEDORA_BREW_CONFIG_DIR="$test_config_dir"

printf "==> Testing catalog listing...\n"
output="$("$repo_root/scripts/brew-app" list)"
echo "$output" | grep -Fq "antigravity"
echo "$output" | grep -Fq "flare"
echo "$output" | grep -Fq "vicinae"
echo "$output" | grep -Fq "shadow-pc"
echo "$output" | grep -Fq "toshy"
echo "$output" | grep -Fq "claude-desktop"

printf "==> Testing package info output...\n"
info_output="$("$repo_root/scripts/brew-app" info antigravity)"
echo "$info_output" | grep -Fq "Google Antigravity"
echo "$info_output" | grep -Fq "[RPM]"
echo "$info_output" | grep -Fq "[FLATPAK]"
echo "$info_output" | grep -Fq "[BREW]"

printf "==> Testing backend flag resolution and dry-run...\n"

# 1. RPM dry run
rpm_dry="$("$repo_root/scripts/brew-app" install antigravity --rpm --dry-run)"
echo "$rpm_dry" | grep -Fq "sudo dnf install -y antigravity"
echo "$rpm_dry" | grep -Fq "Successfully installed Google Antigravity via RPM"

# 2. Flatpak dry run
flatpak_dry="$("$repo_root/scripts/brew-app" install antigravity --flatpak --dry-run)"
echo "$flatpak_dry" | grep -Fq "flatpak install -y --user flathub com.google.Antigravity"
echo "$flatpak_dry" | grep -Fq "Successfully installed Google Antigravity via FLATPAK"

# 3. Brew dry run
brew_dry="$("$repo_root/scripts/brew-app" install antigravity --brew --dry-run)"
echo "$brew_dry" | grep -Fq "brew install Brandon-Gottshall/fedora-brew/antigravity"
echo "$brew_dry" | grep -Fq "Successfully installed Google Antigravity via BREW"

# 4. Brew cask dry run
toshy_dry="$("$repo_root/scripts/brew-app" install toshy --brew --dry-run)"
echo "$toshy_dry" | grep -Fq "brew install --cask Brandon-Gottshall/fedora-brew/toshy"
echo "$toshy_dry" | grep -Fq "Successfully installed Toshy via BREW"

# 5. Synonym flags
native_dry="$("$repo_root/scripts/brew-app" install flare --native --dry-run)"
echo "$native_dry" | grep -Fq "sudo dnf install -y flare"

# 6. COPR enablement check
copr_dry="$("$repo_root/scripts/brew-app" install vicinae --rpm --dry-run)"
echo "$copr_dry" | grep -Fq "sudo dnf copr enable -y vicinaehq/vicinae"

printf "==> Testing configuration setting...\n"
"$repo_root/scripts/brew-app" config default_backend flatpak >/dev/null
cfg_out="$("$repo_root/scripts/brew-app" config)"
echo "$cfg_out" | grep -Fq '"default_backend": "flatpak"'

printf "==> Testing state persistence...\n"
# State should have recorded the last dry-run install in test_config_dir
[[ -f "$test_config_dir/installed.json" ]]
"$repo_root/scripts/brew-app" uninstall vicinae --dry-run >/dev/null

printf "==> All App Manager tests passed successfully!\n"
