#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin"

cat > "$fixture/bin/brew" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == --prefix ]]; then
  printf '/opt/homebrew-test\n'
  exit 0
fi
exit 1
EOF
chmod +x "$fixture/bin/brew"

export HOME="$fixture/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/usr/share"
export PATH="$fixture/bin:$PATH"
export LINUX_FORMULAS_TESTING=1

"$repo_root/scripts/bootstrap-desktop"

environment_file="$XDG_CONFIG_HOME/environment.d/60-linux-formulas-xdg-data.conf"
plasma_file="$XDG_CONFIG_HOME/plasma-workspace/env/60-linux-formulas-xdg-data.sh"
test -f "$environment_file"
test -f "$plasma_file"
grep -Fqx '# Managed by linux-formulas bootstrap.' "$environment_file"
grep -Fqx '# Managed by linux-formulas bootstrap.' "$plasma_file"
grep -Fqx "XDG_DATA_DIRS=/opt/homebrew-test/share:$XDG_DATA_DIRS" "$environment_file"
! grep -Fq 'restart plasma-plasmashell' "$repo_root/scripts/bootstrap-desktop"

session_dirs="$(
  XDG_DATA_DIRS="$HOME/.local/share/flatpak/exports/share:/usr/share"
  source "$plasma_file"
  source "$plasma_file"
  printf '%s' "$XDG_DATA_DIRS"
)"
test "$session_dirs" = "/opt/homebrew-test/share:$HOME/.local/share/flatpak/exports/share:/usr/share"

"$repo_root/scripts/bootstrap-desktop" --remove
test ! -e "$environment_file"
test ! -e "$plasma_file"

# Existing releases must be removable, including without a new install first.
legacy_environment="$XDG_CONFIG_HOME/environment.d/60-fedora-brew-xdg-data.conf"
legacy_plasma="$XDG_CONFIG_HOME/plasma-workspace/env/60-fedora-brew-xdg-data.sh"
printf '# Managed by fedora-brew bootstrap.\nXDG_DATA_DIRS=/old/share:/usr/share\n' > "$legacy_environment"
printf '# Managed by fedora-brew bootstrap.\n' > "$legacy_plasma"
"$repo_root/scripts/bootstrap-desktop" --remove
test ! -e "$legacy_environment"
test ! -e "$legacy_plasma"
printf '# user-owned config\n' > "$legacy_environment"
"$repo_root/scripts/bootstrap-desktop"
test -f "$legacy_environment"
