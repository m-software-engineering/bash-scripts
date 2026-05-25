#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
cd "${repo_root}"

"${repo_root}/scripts/check-tools.sh"
"${repo_root}/scripts/syntax.sh"
"${repo_root}/scripts/format.sh" --check
"${repo_root}/scripts/lint.sh"
"${repo_root}/scripts/test.sh"
