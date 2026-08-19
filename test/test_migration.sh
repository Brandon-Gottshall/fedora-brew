#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT

cat > "$fixture/antigravity.repo" <<'EOF'
[antigravity-rpm]
name=Antigravity RPM Repository
baseurl=https://us-central1-yum.pkg.dev/projects/antigravity-auto-updater-dev/antigravity-rpm
enabled=1
gpgcheck=0
EOF

cat > "$fixture/google-chrome.repo" <<'EOF'
[google-chrome]
name=Google Chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
EOF

output="$(ANTIGRAVITY_REPO_DIR="$fixture" "$repo_root/scripts/migrate-antigravity-v1-fedora")"
grep -Fq "Dedicated legacy repository files: 1" <<< "$output"
grep -Fq "$fixture/antigravity.repo" <<< "$output"
grep -Fq "Unrelated Google repository files preserved: 1" <<< "$output"
grep -Fq "$fixture/google-chrome.repo" <<< "$output"
grep -Fq "Dry run complete; no changes made." <<< "$output"
test -f "$fixture/antigravity.repo"
test -f "$fixture/google-chrome.repo"
