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

function script_path_resolves_macos_performance_beauty_script { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"

  run script_path "macos-performance-beauty.sh"

  [ "${status}" -eq 0 ]
  [ "${output}" = "${TEST_HOME}/dotfiles/scripts/scripts/macos-performance-beauty.sh" ]
}

function setup_context7_api_key_writes_owner_only_secret_without_echoing_it { #@test
  local api_key="ctx7sk-test_key-123"
  local env_file="${HOME}/.config/m-config/context7.env"

  run bash -c 'source "$1"; printf "y\n%s\n" "$2" | setup_context7_api_key' _ "${INSTALLER}" "${api_key}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"${api_key}"* ]]
  [ "$(cat "${env_file}")" = "export CONTEXT7_API_KEY=${api_key}" ]
  [ "$(stat -f '%Lp' "${env_file}")" = "600" ]
  [ "$(stat -f '%Lp' "$(dirname "${env_file}")")" = "700" ]
}

function setup_context7_api_key_does_not_leak_the_secret_under_xtrace { #@test
  local api_key="ctx7sk-xtrace_secret"
  local input_file="${BATS_TEST_TMPDIR}/context7-input"
  printf 'y\n%s\n' "${api_key}" > "${input_file}"

  run bash -x -c 'source "$1"; setup_context7_api_key' _ "${INSTALLER}" < "${input_file}"

  [ "${status}" -eq 0 ]
  [[ "${output}" != *"${api_key}"* ]]
}

function setup_context7_api_key_refuses_a_symlinked_secret_directory { #@test
  local api_key="ctx7sk-symlink_test"
  local redirected_dir="${BATS_TEST_TMPDIR}/redirected"
  mkdir -p "${HOME}/.config" "${redirected_dir}"
  ln -s "${redirected_dir}" "${HOME}/.config/m-config"

  run bash -c 'source "$1"; printf "y\n%s\n" "$2" | setup_context7_api_key' _ "${INSTALLER}" "${api_key}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Refusing to store"* ]]
  [ ! -e "${redirected_dir}/context7.env" ]
}

function setup_context7_api_key_does_not_follow_the_legacy_predictable_temp_symlink { #@test
  local api_key="ctx7sk-no_clobber"
  local victim_file="${BATS_TEST_TMPDIR}/victim"
  printf 'preserve-me\n' > "${victim_file}"

  run bash -c '
    source "$1"
    env_path="$(context7_env_path)"
    mkdir -p "$(dirname "${env_path}")"
    ln -s "$3" "${env_path}.tmp.$$"
    printf "y\n%s\n" "$2" | setup_context7_api_key
  ' _ "${INSTALLER}" "${api_key}" "${victim_file}"

  [ "${status}" -eq 0 ]
  [ "$(cat "${victim_file}")" = "preserve-me" ]
  [ "$(cat "${HOME}/.config/m-config/context7.env")" = "export CONTEXT7_API_KEY=${api_key}" ]
}

function setup_context7_api_key_replaces_atomically_without_duplicates { #@test
  local first_key="ctx7sk-first_key"
  local second_key="ctx7sk-second_key"
  local env_file="${HOME}/.config/m-config/context7.env"

  bash -c 'source "$1"; printf "y\n%s\n" "$2" | setup_context7_api_key' _ "${INSTALLER}" "${first_key}"
  run bash -c 'source "$1"; printf "y\n%s\n" "$2" | setup_context7_api_key' _ "${INSTALLER}" "${second_key}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Replace the existing Context7 API key"* ]]
  [ "$(cat "${env_file}")" = "export CONTEXT7_API_KEY=${second_key}" ]
  [ "$(wc -l < "${env_file}" | tr -d ' ')" -eq 1 ]
}

function setup_context7_api_key_rejects_invalid_input_without_changing_existing_secret { #@test
  local env_file="${HOME}/.config/m-config/context7.env"
  mkdir -p "$(dirname "${env_file}")"
  printf 'export CONTEXT7_API_KEY=ctx7sk-existing\n' > "${env_file}"

  run bash -c 'source "$1"; printf "y\nnot-a-context7-key\n" | setup_context7_api_key' _ "${INSTALLER}"

  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Invalid Context7 API key format"* ]]
  [[ "${output}" != *"not-a-context7-key"* ]]
  [ "$(cat "${env_file}")" = "export CONTEXT7_API_KEY=ctx7sk-existing" ]
}

function setup_context7_api_key_decline_preserves_existing_secret { #@test
  local env_file="${HOME}/.config/m-config/context7.env"
  mkdir -p "$(dirname "${env_file}")"
  printf 'export CONTEXT7_API_KEY=ctx7sk-existing\n' > "${env_file}"

  run bash -c 'source "$1"; printf "n\n" | setup_context7_api_key' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Leaving Context7 API key unchanged."* ]]
  [ "$(cat "${env_file}")" = "export CONTEXT7_API_KEY=ctx7sk-existing" ]
}

function brewfile_path_prefers_homebrew_package_brewfile { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/homebrew/.config/homebrew"
  touch "${TARGET_DIR}/Brewfile"
  touch "${TARGET_DIR}/homebrew/.config/homebrew/Brewfile"

  run brewfile_path

  [ "${status}" -eq 0 ]
  [ "${output}" = "${TARGET_DIR}/homebrew/.config/homebrew/Brewfile" ]
}

function brewfile_path_falls_back_to_legacy_root_brewfile { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}"
  touch "${TARGET_DIR}/Brewfile"

  run brewfile_path

  [ "${status}" -eq 0 ]
  [ "${output}" = "${TARGET_DIR}/Brewfile" ]
}

function install_brew_bundle_uses_canonical_homebrew_package_brewfile { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local brew_log="${BATS_TEST_TMPDIR}/brew.log"
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}/homebrew/.config/homebrew"

  cat > "${DOTFILES_DIR}/homebrew/.config/homebrew/Brewfile" << 'EOF'
brew "git"
EOF

  cat > "${bin_dir}/brew" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${BREW_CALL_LOG}"
EOF
  chmod +x "${bin_dir}/brew"

  cat > "${bin_dir}/sudo" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'sudo=%s\n' "$*" >> "${BREW_CALL_LOG}"
EOF
  chmod +x "${bin_dir}/sudo"

  export BREW_CALL_LOG="${brew_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\n" | install_brew_bundle' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 0 ]
  [[ "$(cat "${brew_log}")" == *"sudo=-v"* ]]
  [[ "$(cat "${brew_log}")" == *"args=bundle --file ${DOTFILES_DIR}/homebrew/.config/homebrew/Brewfile"* ]]
}

function setup_macos_performance_beauty_skips_when_script_is_missing { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"

  run setup_macos_performance_beauty

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"macOS performance and appearance script not found"* ]]
}

function setup_macos_performance_beauty_runs_after_confirmation { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  local scripts_dir="${TARGET_DIR}/scripts/scripts"
  local call_log="${BATS_TEST_TMPDIR}/macos-tuning.log"
  mkdir -p "${scripts_dir}"

  cat > "${scripts_dir}/macos-performance-beauty.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'DOTFILES_DIR=%s\n' "${DOTFILES_DIR:-}" > "${MACOS_TUNING_CALL_LOG}"
printf 'args=%s\n' "$*" >> "${MACOS_TUNING_CALL_LOG}"
EOF
  chmod +x "${scripts_dir}/macos-performance-beauty.sh"

  export MACOS_TUNING_CALL_LOG="${call_log}"
  run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\n" | setup_macos_performance_beauty' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Apply macOS performance and appearance defaults from dotfiles? [y/N]"* ]]
  [[ "$(cat "${call_log}")" == *"DOTFILES_DIR=${TARGET_DIR}"* ]]
  [[ "$(cat "${call_log}")" == *"args="* ]]
}

function setup_macos_performance_beauty_declines_cleanly { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  local scripts_dir="${TARGET_DIR}/scripts/scripts"
  local call_log="${BATS_TEST_TMPDIR}/macos-tuning.log"
  mkdir -p "${scripts_dir}"

  cat > "${scripts_dir}/macos-performance-beauty.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'called\n' > "${MACOS_TUNING_CALL_LOG}"
EOF
  chmod +x "${scripts_dir}/macos-performance-beauty.sh"

  export MACOS_TUNING_CALL_LOG="${call_log}"
  run bash -c 'source "$1"; TARGET_DIR="$2"; printf "n\n" | setup_macos_performance_beauty' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping macOS performance and appearance defaults."* ]]
  [ ! -f "${call_log}" ]
}

function bootstrap_neovim_skips_when_nvim_is_missing { #@test
  PATH="/usr/bin:/bin" run bootstrap_neovim

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"nvim not found. Skipping LazyVim plugin bootstrap."* ]]
}

function bootstrap_neovim_skips_when_lazyvim_spec_is_missing { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin_dir}/nvim"
  chmod +x "${bin_dir}/nvim"

  PATH="${bin_dir}:${PATH}" run bootstrap_neovim

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"LazyVim spec not found"* ]]
}

function bootstrap_neovim_declines_cleanly { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local nvim_log="${BATS_TEST_TMPDIR}/nvim.log"
  mkdir -p "${bin_dir}" "${HOME}/.config/nvim/lua/config"
  cat > "${bin_dir}/nvim" << 'EOF'
#!/usr/bin/env bash
printf 'called\n' >>"${NVIM_CALL_LOG}"
EOF
  chmod +x "${bin_dir}/nvim"
  printf 'return {}\n' > "${HOME}/.config/nvim/lua/config/lazy.lua"
  export NVIM_CALL_LOG="${nvim_log}"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "n\n" | bootstrap_neovim' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping LazyVim plugin bootstrap."* ]]
  [ ! -f "${nvim_log}" ]
}

function bootstrap_neovim_syncs_after_confirmation { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local nvim_log="${BATS_TEST_TMPDIR}/nvim.log"
  mkdir -p "${bin_dir}" "${HOME}/.config/nvim/lua/config"
  cat > "${bin_dir}/nvim" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >>"${NVIM_CALL_LOG}"
EOF
  chmod +x "${bin_dir}/nvim"
  printf 'return {}\n' > "${HOME}/.config/nvim/lua/config/lazy.lua"
  export NVIM_CALL_LOG="${nvim_log}"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "y\n" | bootstrap_neovim' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"LazyVim plugins synced."* ]]
  [ "$(cat "${nvim_log}")" = "args=--headless +Lazy! sync +qa" ]
}

function bootstrap_neovim_continues_when_sync_fails { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  mkdir -p "${bin_dir}" "${HOME}/.config/nvim/lua/config"
  printf '#!/usr/bin/env bash\nexit 9\n' > "${bin_dir}/nvim"
  chmod +x "${bin_dir}/nvim"
  printf 'return {}\n' > "${HOME}/.config/nvim/lua/config/lazy.lua"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "y\n" | bootstrap_neovim' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"LazyVim plugin bootstrap failed."* ]]
}

function install_vscodium_extensions_skips_when_script_is_missing { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"

  run install_vscodium_extensions

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"VSCodium extension installer not found"* ]]
}

function install_vscodium_extensions_skips_when_codium_is_missing { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/scripts/scripts"
  touch "${TARGET_DIR}/scripts/scripts/vscodium-install-extensions.sh"

  PATH="/usr/bin:/bin" run bash -c '
    source "$1"
    ensure_codium_on_path() { return 0; }
    TARGET_DIR="$2"
    install_vscodium_extensions
  ' _ "${INSTALLER}" "${TARGET_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"codium command not found. Skipping"* ]]
}

function install_vscodium_extensions_declines_cleanly { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local extensions_script="${DOTFILES_DIR}/scripts/scripts/vscodium-install-extensions.sh"
  local call_log="${BATS_TEST_TMPDIR}/vscodium.log"
  mkdir -p "${bin_dir}" "$(dirname "${extensions_script}")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin_dir}/codium"
  chmod +x "${bin_dir}/codium"
  cat > "${extensions_script}" << 'EOF'
#!/usr/bin/env bash
printf 'called\n' >"${VSCODIUM_CALL_LOG}"
EOF
  export VSCODIUM_CALL_LOG="${call_log}"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "n\n" | install_vscodium_extensions' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Install missing VSCodium extensions from dotfiles? [y/N]"* ]]
  [[ "${output}" == *"Skipping VSCodium extension install."* ]]
  [ ! -f "${call_log}" ]
}

function install_vscodium_extensions_forwards_target_and_supports_repeat_runs { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local extensions_script="${DOTFILES_DIR}/scripts/scripts/vscodium-install-extensions.sh"
  local call_log="${BATS_TEST_TMPDIR}/vscodium.log"
  mkdir -p "${bin_dir}" "$(dirname "${extensions_script}")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin_dir}/codium"
  chmod +x "${bin_dir}/codium"
  cat > "${extensions_script}" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'DOTFILES_DIR=%s\n' "${DOTFILES_DIR:-}" >>"${VSCODIUM_CALL_LOG}"
EOF
  export VSCODIUM_CALL_LOG="${call_log}"

  PATH="${bin_dir}:${PATH}" run bash -c '
    source "$1"
    TARGET_DIR="$2"
    printf "y\n" | install_vscodium_extensions
    printf "y\n" | install_vscodium_extensions
  ' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${call_log}" | tr -d ' ')" -eq 2 ]
  [ "$(sort -u "${call_log}")" = "DOTFILES_DIR=${DOTFILES_DIR}" ]
}

function install_vscodium_extensions_propagates_child_failures { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local extensions_script="${DOTFILES_DIR}/scripts/scripts/vscodium-install-extensions.sh"
  mkdir -p "${bin_dir}" "$(dirname "${extensions_script}")"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${bin_dir}/codium"
  chmod +x "${bin_dir}/codium"
  printf '#!/usr/bin/env bash\nexit 7\n' > "${extensions_script}"

  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\n" | install_vscodium_extensions' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 7 ]
}

function setup_homebrew_maintenance_skips_when_files_are_missing { #@test
  run setup_homebrew_maintenance

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Homebrew maintenance LaunchAgent or script not found"* ]]
}

function setup_homebrew_maintenance_bootstraps_after_confirmation { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local launchctl_log="${BATS_TEST_TMPDIR}/launchctl.log"
  local uid
  uid="$(id -u)"
  mkdir -p "${bin_dir}" "${HOME}/Library/LaunchAgents" "${HOME}/.config/homebrew"
  touch "${HOME}/Library/LaunchAgents/com.m-software-engineering.homebrew-maintenance.plist"
  touch "${HOME}/.config/homebrew/homebrew-maintenance.sh"

  cat > "${bin_dir}/launchctl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${LAUNCHCTL_CALL_LOG}"
if [[ "${1}" == "print" ]]; then
  exit 113
fi
EOF
  chmod +x "${bin_dir}/launchctl"

  export LAUNCHCTL_CALL_LOG="${launchctl_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "y\n" | setup_homebrew_maintenance' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Enable daily Homebrew maintenance LaunchAgent? [y/N]"* ]]
  grep -F "args=print gui/${uid}/com.m-software-engineering.homebrew-maintenance" "${launchctl_log}"
  grep -F "args=bootstrap gui/${uid} ${HOME}/Library/LaunchAgents/com.m-software-engineering.homebrew-maintenance.plist" "${launchctl_log}"
  grep -F "args=enable gui/${uid}/com.m-software-engineering.homebrew-maintenance" "${launchctl_log}"
}

function setup_homebrew_maintenance_declines_cleanly { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local launchctl_log="${BATS_TEST_TMPDIR}/launchctl.log"
  mkdir -p "${bin_dir}" "${HOME}/Library/LaunchAgents" "${HOME}/.config/homebrew"
  touch "${HOME}/Library/LaunchAgents/com.m-software-engineering.homebrew-maintenance.plist"
  touch "${HOME}/.config/homebrew/homebrew-maintenance.sh"

  cat > "${bin_dir}/launchctl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${LAUNCHCTL_CALL_LOG}"
if [[ "${1}" == "print" ]]; then
  exit 113
fi
EOF
  chmod +x "${bin_dir}/launchctl"

  export LAUNCHCTL_CALL_LOG="${launchctl_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; printf "n\n" | setup_homebrew_maintenance' _ "${INSTALLER}"

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Skipping scheduled Homebrew maintenance setup."* ]]
  [[ "$(cat "${launchctl_log}")" != *"args=bootstrap"* ]]
  [[ "$(cat "${launchctl_log}")" != *"args=enable"* ]]
}

function setup_homebrew_maintenance_skips_when_already_loaded { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local launchctl_log="${BATS_TEST_TMPDIR}/launchctl.log"
  mkdir -p "${bin_dir}" "${HOME}/Library/LaunchAgents" "${HOME}/.config/homebrew"
  touch "${HOME}/Library/LaunchAgents/com.m-software-engineering.homebrew-maintenance.plist"
  touch "${HOME}/.config/homebrew/homebrew-maintenance.sh"

  cat > "${bin_dir}/launchctl" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${LAUNCHCTL_CALL_LOG}"
if [[ "${1}" != "print" ]]; then
  exit 2
fi
EOF
  chmod +x "${bin_dir}/launchctl"

  export LAUNCHCTL_CALL_LOG="${launchctl_log}"
  PATH="${bin_dir}:${PATH}" run setup_homebrew_maintenance

  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Homebrew maintenance LaunchAgent is already loaded."* ]]
  [[ "$(cat "${launchctl_log}")" != *"args=bootstrap"* ]]
  [[ "$(cat "${launchctl_log}")" != *"args=enable"* ]]
}

function discover_stow_packages_skips_hidden_and_non_stow_directories { #@test
  TARGET_DIR="${TEST_HOME}/dotfiles"
  mkdir -p "${TARGET_DIR}/browser" "${TARGET_DIR}/test" "${TARGET_DIR}/claude" "${TARGET_DIR}/git" "${TARGET_DIR}/nvim" "${TARGET_DIR}/zsh" "${TARGET_DIR}/.hidden"
  touch "${TARGET_DIR}/README.md"

  run discover_stow_packages

  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = "git" ]
  [ "${lines[1]}" = "nvim" ]
  [ "${lines[2]}" = "zsh" ]
  [ "${#lines[@]}" -eq 3 ]
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

function stow_packages_passes_macos_metadata_ignore_patterns { #@test
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
  grep -F -- "--ignore=\\.DS_Store$" "${stow_log}"
  grep -F -- "--ignore=\\._[^/]+$" "${stow_log}"
}

function stow_packages_backs_up_symlink_conflicts_after_confirmation { #@test
  local bin_dir="${BATS_TEST_TMPDIR}/bin"
  local stow_log="${BATS_TEST_TMPDIR}/stow.log"
  local backup_link
  mkdir -p "${bin_dir}" "${DOTFILES_DIR}/scripts/scripts"
  touch "${DOTFILES_DIR}/scripts/scripts/tool.sh"
  ln -s old-dotfiles/scripts "${HOME}/scripts"

  cat > "${bin_dir}/stow" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s\n' "$*" >> "${STOW_CALL_LOG}"
if [[ " $* " == *" -n "* ]]; then
  printf 'WARNING! stowing scripts would cause conflicts:\n' >&2
  printf '  * existing target is not owned by stow: scripts\n' >&2
  exit 1
fi
EOF
  chmod +x "${bin_dir}/stow"

  export STOW_CALL_LOG="${stow_log}"
  PATH="${bin_dir}:${PATH}" run bash -c 'source "$1"; TARGET_DIR="$2"; printf "y\ny\n" | stow_packages' _ "${INSTALLER}" "${DOTFILES_DIR}"

  [ "${status}" -eq 0 ]
  [ ! -L "${HOME}/scripts" ]
  backup_link="$(find "${HOME}/.dotfiles-backup" -name scripts -type l -print | head -n 1)"
  [ -n "${backup_link}" ]
  grep -F -- "args=-v -d ${DOTFILES_DIR}" "${stow_log}"
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
