#!/usr/bin/env bats
# shellcheck disable=SC2154

setup() {
  load "test_helper/common.bash"
  setup_installer_fixture
}

function help_exits_before_macos_and_tty_checks { #@test
  run bash "${INSTALLER}" --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: m-config-install.sh [options]"* ]]
  [[ "${output}" != *"macOS-only"* ]]
  [[ "${output}" != *"interactive terminal"* ]]
}

function help_works_with_documented_bash_c_execution { #@test
  run bash -c "$(cat "${INSTALLER}")" bash --help
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Usage: m-config-install.sh [options]"* ]]
}

function confirm_accepts_yes_answers { #@test
  local answer
  for answer in y Y yes YES YeS; do
    run bash -c 'source "$1"; printf "%s\n" "$2" | confirm "Proceed?"' _ "${INSTALLER}" "${answer}"
    [ "${status}" -eq 0 ]
    [ "${output}" = "Proceed? [y/N] " ]
  done
}

function confirm_rejects_empty_and_no_answers { #@test
  local answer
  for answer in "" n N no NO anything; do
    run bash -c 'source "$1"; printf "%s\n" "$2" | confirm "Proceed?"' _ "${INSTALLER}" "${answer}"
    [ "${status}" -eq 1 ]
    [ "${output}" = "Proceed? [y/N] " ]
  done
}

function confirm_suffix_is_rendered_once { #@test
  run bash -c 'source "$1"; printf "n\n" | confirm "Clone dotfiles repo?"' _ "${INSTALLER}"
  [ "${status}" -eq 1 ]
  [ "${output}" = "Clone dotfiles repo? [y/N] " ]
  [[ "${output}" != *"[y/N]  [y/N]"* ]]
}

function parse_args_accepts_supported_overrides { #@test
  parse_args --dotfiles-dir "${TEST_HOME}/custom-dotfiles" --repo-url "https://example.invalid/custom.git"

  [ "${TARGET_DIR}" = "${TEST_HOME}/custom-dotfiles" ]
  [ "${REPO_URL}" = "https://example.invalid/custom.git" ]
}

function parse_args_rejects_unknown_options { #@test
  run bash -c 'source "$1"; parse_args --wat' _ "${INSTALLER}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Unknown option: --wat"* ]]
}

function script_path_resolves_dotfiles_script_package_paths { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"

  run script_path "macos-set-default-apps.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" = "${TEST_HOME}/dotfiles/scripts/scripts/macos-set-default-apps.sh" ]
}

function discover_stow_packages_skips_hidden_and_non_stow_directories { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/browser" "${TARGET_DIR}/git" "${TARGET_DIR}/zsh" "${TARGET_DIR}/.hidden"
  touch "${TARGET_DIR}/README.md"

  run discover_stow_packages

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "zsh" ]
  [ "${#lines[@]}" -eq 2 ]
}

function require_interactive_tty_fails_without_tty { #@test
  run bash -c 'source "$1"; require_interactive_tty' _ "${INSTALLER}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"This installer requires an interactive terminal (TTY)."* ]]
  [[ "${output}" == *"bash -c \"\$(curl -fsSL"* ]]
}

function clone_repo_skips_existing_git_repo { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/.git"

  run clone_repo

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Repo already exists. Skipping clone."* ]]
}

function clone_repo_rejects_existing_non_git_path { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}"

  run bash -c 'source "$1"; TARGET_DIR="$2"; clone_repo' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"exists but is not a git repo"* ]]
}

function append_words_adds_missing_words_without_duplicates { #@test
  run append_words "alpha beta" beta gamma alpha delta

  [ "${status}" -eq 0 ]
  [ "${output}" = "alpha beta gamma delta" ]
}

function run_brew_bundle_skips_stale_taps_and_installs_migrated_codex_cask { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local brew_log="${BATS_TEST_TMPDIR}/brew.log"
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}"

  cat > "${DOTFILES_DIR}/Brewfile" << 'EOF'
tap "homebrew/bundle"
tap "homebrew/cask"
tap "homebrew/cask-fonts"
tap "homebrew/core"
brew "git"
brew "codex"
cask "wezterm"
EOF

  cat > "${bin_dir}/brew" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'args=%s\n' "$*" >> "${BREW_CALL_LOG}"
if [[ "${1}" == "bundle" ]]; then
  printf 'tap_skip=%s\n' "${HOMEBREW_BUNDLE_TAP_SKIP:-}" >> "${BREW_CALL_LOG}"
  printf 'brew_skip=%s\n' "${HOMEBREW_BUNDLE_BREW_SKIP:-}" >> "${BREW_CALL_LOG}"
elif [[ "${1}" == "install" && "${2}" == "--cask" && "${3}" == "codex" ]]; then
  printf 'installed_codex_cask=true\n' >> "${BREW_CALL_LOG}"
else
  exit 2
fi
EOF
  chmod +x "${bin_dir}/brew"

  export BREW_CALL_LOG="${brew_log}"
  PATH="${bin_dir}:${PATH}" run run_brew_bundle "${DOTFILES_DIR}/Brewfile"

  [ "${status}" -eq 0 ]
  [[ "$(cat "${brew_log}")" == *"args=bundle --file ${DOTFILES_DIR}/Brewfile"* ]]
  [[ "$(cat "${brew_log}")" == *"tap_skip=homebrew/bundle homebrew/cask homebrew/cask-fonts homebrew/core"* ]]
  [[ "$(cat "${brew_log}")" == *"brew_skip=codex"* ]]
  [[ "$(cat "${brew_log}")" == *"args=install --cask codex"* ]]
  [[ "$(cat "${brew_log}")" == *"installed_codex_cask=true"* ]]
}

function run_brew_bundle_does_not_reinstall_codex_when_cask_entry_exists { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local brew_log="${BATS_TEST_TMPDIR}/brew.log"
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}"

  cat > "${DOTFILES_DIR}/Brewfile" << 'EOF'
brew "codex"
cask "codex"
EOF

  cat > "${bin_dir}/brew" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf 'args=%s\n' "$*" >> "${BREW_CALL_LOG}"
if [[ "${1}" != "bundle" ]]; then
  exit 2
fi
EOF
  chmod +x "${bin_dir}/brew"

  export BREW_CALL_LOG="${brew_log}"
  PATH="${bin_dir}:${PATH}" run run_brew_bundle "${DOTFILES_DIR}/Brewfile"

  [ "${status}" -eq 0 ]
  [[ "$(cat "${brew_log}")" == *"args=bundle --file ${DOTFILES_DIR}/Brewfile"* ]]
  [[ "$(cat "${brew_log}")" != *"args=install --cask codex"* ]]
}
