#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." > /dev/null 2>&1 && pwd)"
cd "${repo_root}"

"${repo_root}/scripts/check-tools.sh" shfmt

mode="write"
if [[ "${1:-}" == "--check" ]]; then
  mode="check"
  shift
fi
if [[ "$#" -gt 0 ]]; then
  printf 'Usage: %s [--check]\n' "${0}" >&2
  exit 2
fi

shell_files=()
while IFS= read -r shell_file; do
  shell_files+=("${shell_file}")
done < <("./scripts/list-shell-files.sh")
if [[ "${#shell_files[@]}" -eq 0 ]]; then
  exit 0
fi

if [[ "${mode}" == "check" ]]; then
  shfmt -ln bash -i 2 -ci -sr -d "${shell_files[@]}"
else
  shfmt -ln bash -i 2 -ci -sr -w "${shell_files[@]}"
fi
