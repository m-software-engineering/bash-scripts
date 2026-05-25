#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -gt 0 ]]; then
  required_tools=("$@")
else
  required_tools=(bash bats shellcheck shfmt)
fi
missing_tools=()

for tool in "${required_tools[@]}"; do
  if ! command -v "${tool}" > /dev/null 2>&1; then
    missing_tools+=("${tool}")
  fi
done

if [[ "${#missing_tools[@]}" -eq 0 ]]; then
  exit 0
fi

printf 'Missing required tool(s): %s\n' "${missing_tools[*]}" >&2
if command -v brew > /dev/null 2>&1; then
  printf 'Install project tools with: brew bundle\n' >&2
else
  printf 'Install bats-core, shellcheck, and shfmt before running checks.\n' >&2
fi
exit 127
