#!/usr/bin/env bash

setup_installer_fixture() {
  PROJECT_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." > /dev/null 2>&1 && pwd)"
  INSTALLER="${PROJECT_ROOT}/m-config-install.sh"
  TEST_HOME="${BATS_TEST_TMPDIR}/home"
  mkdir -p "${TEST_HOME}"

  export HOME="${TEST_HOME}"
  export DOTFILES_DIR="${TEST_HOME}/dotfiles"
  export DOTFILES_REPO_URL="https://example.invalid/dotfiles.git"

  # shellcheck source=/dev/null
  source "${INSTALLER}"
}
