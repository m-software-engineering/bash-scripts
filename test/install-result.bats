#!/usr/bin/env bats
# shellcheck disable=SC2154

setup() {
  load "test_helper/common.bash"
  setup_installer_fixture
}

function clean_run_reports_no_failed_steps { #@test
  run report_install_result

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Setup finished with no failed steps."* ]]
}

function recorded_failure_is_listed_and_exits_nonzero { #@test
  record_failure "Brewfile install"

  run report_install_result

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Failed: Brewfile install"* ]]
  [[ "${output}" == *"  - Brewfile install"* ]]
}

function declined_step_is_not_a_failure { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/scripts/scripts"
  printf '#!/bin/bash\nexit 1\n' > "${TARGET_DIR}/scripts/scripts/macos-performance-beauty.sh"
  chmod +x "${TARGET_DIR}/scripts/scripts/macos-performance-beauty.sh"

  run bash -c 'source "$1"; TARGET_DIR="$2"; setup_macos_performance_beauty <<< "n"; report_install_result' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping macOS performance and appearance defaults."* ]]
  [[ "${output}" == *"no failed steps"* ]]
}

function accepted_step_failure_continues_and_is_reported { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/scripts/scripts"
  printf '#!/bin/bash\nexit 1\n' > "${TARGET_DIR}/scripts/scripts/macos-performance-beauty.sh"
  chmod +x "${TARGET_DIR}/scripts/scripts/macos-performance-beauty.sh"

  run bash -c 'source "$1"; TARGET_DIR="$2"; setup_macos_performance_beauty <<< "y"; echo NEXT_STEP_RAN; report_install_result' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"NEXT_STEP_RAN"* ]]
  [[ "${output}" == *"Failed: macOS performance and appearance defaults"* ]]
  [[ "${output}" == *"  - macOS performance and appearance defaults"* ]]
}

function brewfile_failure_is_recorded_without_aborting_the_caller { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}/homebrew/.config/homebrew"
  printf 'brew "git"\n' > "${DOTFILES_DIR}/homebrew/.config/homebrew/Brewfile"

  cat > "${bin_dir}/brew" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "bundle" ]]; then
  exit 1
fi
exit 0
EOF
  cat > "${bin_dir}/sudo" << 'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${bin_dir}/brew" "${bin_dir}/sudo"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; install_brew_bundle <<< "y"; echo NEXT_STEP_RAN; report_install_result' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"NEXT_STEP_RAN"* ]]
  [[ "${output}" == *"Failed: Brewfile install"* ]]
}

function node_setup_skips_work_that_is_already_done { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local mise_log="${BATS_TEST_TMPDIR}/mise.log"
  mkdir -p "${bin_dir}"

  cat > "${bin_dir}/brew" << 'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "${bin_dir}/mise" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${MISE_CALL_LOG}"
if [[ "${1:-}" == "ls" && "${2:-}" == "--global" && "${3:-}" == "node" ]]; then
  printf 'node 22.14.0\n'
  exit 0
fi
if [[ "${1:-}" == "settings" && "${2:-}" == "get" ]]; then
  printf 'node\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${bin_dir}/brew" "${bin_dir}/mise"

  export MISE_CALL_LOG="${mise_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "y\ny\n" | setup_node_runtime' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Node.js is already installed with mise. Skipping Node.js LTS install."* ]]
  [[ "${output}" == *"mise already reads .nvmrc and .node-version. Skipping."* ]]
  [[ "${output}" != *"Install Node.js LTS"* ]]
  ! grep -q 'use --global' "${mise_log}"
}

function stow_skips_when_packages_are_already_linked { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local stow_log="${BATS_TEST_TMPDIR}/stow.log"
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}/git"

  cat > "${bin_dir}/stow" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${STOW_CALL_LOG}"
EOF
  chmod +x "${bin_dir}/stow"

  export STOW_CALL_LOG="${stow_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\ny\n" | stow_packages' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stow packages are already linked. Skipping."* ]]
  [[ "$(grep -c . "${stow_log}")" -eq 1 ]]
  [[ "$(cat "${stow_log}")" == *"-n -v"* ]]
}

function wallpaper_skips_apply_when_cloud_jpg_is_already_set { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local swift_log="${BATS_TEST_TMPDIR}/swift.log"
  mkdir -p "${TARGET_DIR}/images/images" "${bin_dir}"
  printf 'jpeg\n' > "${TARGET_DIR}/images/images/cloud.jpg"

  cat > "${bin_dir}/swift" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${SWIFT_CALL_LOG}"
script="${1}"
mode="${2}"
if [[ "${script}" == *.swift && "${mode}" == "status" ]]; then
  printf 'wallpaper-already-set\n'
  exit 0
fi
exit 1
EOF
  chmod +x "${bin_dir}/swift"

  export SWIFT_CALL_LOG="${swift_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\n" | setup_desktop_wallpaper' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Desktop wallpaper is already cloud.jpg. Skipping."* ]]
  [[ "$(cat "${swift_log}")" == *"status ${TARGET_DIR}/images/images/cloud.jpg"* ]]
  [[ "$(cat "${swift_log}")" != *"apply "* ]]
}
