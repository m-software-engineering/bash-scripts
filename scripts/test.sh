#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
cd "${repo_root}"

"${repo_root}/scripts/check-tools.sh" bats

bats test "$@"
