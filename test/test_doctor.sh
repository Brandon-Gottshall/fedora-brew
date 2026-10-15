#!/usr/bin/env bash
# test/test_doctor.sh: Test scripts/doctor behavior

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Run doctor in repo root - should exit with 0
"$repo_root/scripts/doctor" >/dev/null

printf "Doctor test passed.\n"
