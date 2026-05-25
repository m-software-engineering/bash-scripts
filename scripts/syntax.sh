#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
cd "${repo_root}"

shell_files=()
while IFS= read -r shell_file; do
  shell_files+=("${shell_file}")
done < <("./scripts/list-shell-files.sh")
if [[ "${#shell_files[@]}" -eq 0 ]]; then
  exit 0
fi

bash -n "${shell_files[@]}"
