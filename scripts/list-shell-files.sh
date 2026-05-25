#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
cd "${repo_root}"

find . \
  -path './.git' -prune -o \
  -type f \( -name '*.sh' -o -name '*.bash' -o -name '*.bats' \) \
  -print |
  sort
