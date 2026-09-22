#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/m-software-engineering/dotfiles.git"
DEFAULT_TARGET_DIR="${HOME}/dotfiles"
SAFE_CURL_URL="https://raw.githubusercontent.com/m-software-engineering/bash-scripts/refs/heads/main/m-config-install.sh"
# shellcheck disable=SC2016
BREW_INSTALL_CMD='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
# shellcheck disable=SC2016
OMZ_INSTALL_CMD='sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
CLT_TIMEOUT_SECONDS=1800
CLT_POLL_INTERVAL_SECONDS=15
NON_STOW_PACKAGES=(browser test claude)
STOW_IGNORE_PATTERNS=(
  "\\.DS_Store$"
  "\\._[^/]+$"
)
HOMEBREW_MAINTENANCE_LABEL="com.m-software-engineering.homebrew-maintenance"
CHROMIUM_BROWSER_APPS=(
  "Helium|/Applications/Helium.app"
  "Google Chrome|/Applications/Google Chrome.app"
  "Microsoft Edge|/Applications/Microsoft Edge.app"
)
BREW_BUNDLE_DEPRECATED_TAPS=(
  homebrew/bundle
  homebrew/cask
  homebrew/cask-fonts
  homebrew/core
)
BREW_BUNDLE_MIGRATED_FORMULAE_TO_CASKS=(
  codex
)
AI_MEMORY_RELEASE_BASE="https://github.com/akitaonrails/ai-memory/releases/latest/download"
AI_MEMORY_LAUNCHD_LABEL="com.github.akitaonrails.ai-memory"
LOCAL_BIN_PATH_EXPORT="export PATH=\"\$HOME/.local/bin:\$PATH\""
HERMES_SKILL_IDENTIFIERS=(
  "ayghri/i-have-adhd/skills/i-have-adhd"
  "mattpocock/skills/skills/productivity/teach"
)
HERMES_SKILL_NAMES=(
  "i-have-adhd"
  "teach"
)

REPO_URL="${DOTFILES_REPO_URL:-${DEFAULT_REPO_URL}}"
TARGET_DIR="${DOTFILES_DIR:-${DEFAULT_TARGET_DIR}}"

usage() {
  cat << EOF
Usage: m-config-install.sh [options]

Options:
  --dotfiles-dir <path>  Override target dotfiles path (default: ${DEFAULT_TARGET_DIR})
  --repo-url <url>       Override dotfiles repo URL (default: ${DEFAULT_REPO_URL})
  -h, --help             Show this help message

Environment overrides:
  DOTFILES_DIR
  DOTFILES_REPO_URL
EOF
}

log() {
  printf '\n==> %s\n' "$1"
}

confirm() {
  local prompt="${1:-Continue?}"
  local reply
  printf '%s [y/N] ' "${prompt}"
  if ! read -r reply; then
    printf '\n'
    return 1
  fi
  case "${reply}" in
    [yY] | [yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

contains_word() {
  local words="${1}"
  local needle="${2}"
  case " ${words} " in
    *" ${needle} "*) return 0 ;;
    *) return 1 ;;
  esac
}

append_words() {
  local words="${1}"
  shift
  local word
  for word in "$@"; do
    if ! contains_word "${words}" "${word}"; then
      words="${words:+${words} }${word}"
    fi
  done
  printf '%s\n' "${words}"
}

array_contains() {
  local needle="${1}"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

require_sudo() {
  log "Requesting sudo for the next step."
  sudo -v
}

is_non_stow_package() {
  local package_name="${1}"
  local non_stow_package
  for non_stow_package in "${NON_STOW_PACKAGES[@]}"; do
    if [[ "${package_name}" == "${non_stow_package}" ]]; then
      return 0
    fi
  done
  return 1
}

discover_stow_packages() {
  local dir
  for dir in "${TARGET_DIR}"/*; do
    [[ -d "${dir}" ]] || continue
    local name
    name="$(basename "${dir}")"
    [[ "${name}" == .* ]] && continue
    is_non_stow_package "${name}" && continue
    printf '%s\n' "${name}"
  done
}

script_path() {
  printf '%s/scripts/scripts/%s\n' "${TARGET_DIR}" "${1}"
}

brewfile_path() {
  local canonical_brewfile="${TARGET_DIR}/homebrew/.config/homebrew/Brewfile"
  local legacy_brewfile="${TARGET_DIR}/Brewfile"

  if [[ -f "${canonical_brewfile}" ]]; then
    printf '%s\n' "${canonical_brewfile}"
    return 0
  fi

  if [[ -f "${legacy_brewfile}" ]]; then
    printf '%s\n' "${legacy_brewfile}"
    return 0
  fi

  return 1
}

homebrew_maintenance_plist_path() {
  printf '%s/Library/LaunchAgents/%s.plist\n' "${HOME}" "${HOMEBREW_MAINTENANCE_LABEL}"
}

homebrew_maintenance_script_path() {
  printf '%s/.config/homebrew/homebrew-maintenance.sh\n' "${HOME}"
}

context7_env_path() {
  printf '%s\n' "${CONTEXT7_ENV_FILE:-${HOME}/.config/m-config/context7.env}"
}

is_valid_context7_api_key() {
  local api_key="${1}"
  [[ "${api_key}" =~ ^ctx7sk[-_][A-Za-z0-9._-]+$ ]]
}

# Stores the Context7 credential outside the dotfiles repository for both AI harnesses.
setup_context7_api_key() {
  local env_path
  env_path="$(context7_env_path)"

  local prompt="Configure the Context7 API key for Codex and OpenCode?"
  if [[ -f "${env_path}" ]]; then
    prompt="Replace the existing Context7 API key for Codex and OpenCode?"
  fi

  if ! confirm "${prompt}"; then
    log "Leaving Context7 API key unchanged."
    return 0
  fi

  local xtrace_was_enabled=0
  if [[ "${-}" == *x* ]]; then
    xtrace_was_enabled=1
    set +x
  fi

  local api_key
  printf 'Context7 API key (input hidden): '
  if ! IFS= read -r -s api_key; then
    printf '\n'
    unset api_key
    if [[ "${xtrace_was_enabled}" -eq 1 ]]; then
      set -x
    fi
    log "Unable to read the Context7 API key."
    return 1
  fi
  printf '\n'

  if ! is_valid_context7_api_key "${api_key}"; then
    unset api_key
    if [[ "${xtrace_was_enabled}" -eq 1 ]]; then
      set -x
    fi
    log "Invalid Context7 API key format; expected a key beginning with ctx7sk- or ctx7sk_."
    return 1
  fi

  local env_dir
  env_dir="$(dirname "${env_path}")"
  if [[ -L "${env_dir}" ]]; then
    unset api_key
    if [[ "${xtrace_was_enabled}" -eq 1 ]]; then
      set -x
    fi
    log "Refusing to store the Context7 API key in a symlinked directory: ${env_dir}"
    return 1
  fi

  (
    umask 077
    mkdir -p "${env_dir}"
    chmod 700 "${env_dir}"

    local temp_path
    temp_path="$(mktemp "${env_dir}/.context7.env.XXXXXX")"
    trap 'rm -f "${temp_path}"' EXIT
    if [[ ! -f "${temp_path}" || -L "${temp_path}" ]]; then
      exit 1
    fi

    printf 'export CONTEXT7_API_KEY=%s\n' "${api_key}" > "${temp_path}"
    chmod 600 "${temp_path}"
    mv -f "${temp_path}" "${env_path}"
    trap - EXIT
  )
  unset api_key
  if [[ "${xtrace_was_enabled}" -eq 1 ]]; then
    set -x
  fi

  log "Context7 API key stored in ${env_path} with owner-only permissions. Restart the shell before using the MCP servers."
}

ensure_codium_on_path() {
  if command -v codium > /dev/null 2>&1; then
    return 0
  fi

  local codium_bin_dir="/Applications/VSCodium.app/Contents/Resources/app/bin"
  if [[ -x "${codium_bin_dir}/codium" ]]; then
    export PATH="${codium_bin_dir}:${PATH}"
  fi
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dotfiles-dir)
        [[ "$#" -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        TARGET_DIR="$2"
        shift 2
        ;;
      --repo-url)
        [[ "$#" -ge 2 ]] || {
          printf 'Missing value for %s\n' "$1" >&2
          exit 1
        }
        REPO_URL="$2"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

require_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'This installer is macOS-only.\n' >&2
    exit 1
  fi
}

require_interactive_tty() {
  if [[ ! -t 0 || ! -t 1 ]]; then
    cat << EOF >&2
This installer requires an interactive terminal (TTY).

Do not run:
  curl ... | bash

Run instead:
  bash -c "\$(curl -fsSL ${SAFE_CURL_URL})"
EOF
    exit 1
  fi
}

print_banner() {
  printf '\033[0;31m'
  cat << "EOF"
 Yb  dP .d88b. 8    8       db    888b. 8888    8    8 .d88b. 888 8b  8 .d88b  
  YbdP  8P  Y8 8    8      dPYb   8  .8 8www    8    8 YPwww.  8  8Ybm8 8P www 
   YP   8b  d8 8b..d8     dPwwYb  8wwK' 8       8b..d8     d8  8  8  "8 8b  d8 
   88   `Y88P' `Y88P'    dP    Yb 8  Yb 8888    `Y88P' `Y88P' 888 8   8 `Y88P' 
                                                                              
        ███▄ ▄███▓    ▄████▄    ▒█████    ███▄    █    █████▒ ██▓   ▄████ 
       ▓██▒▀█▀ ██▒   ▒██▀ ▀█   ▒██▒  ██▒  ██ ▀█   █  ▓██   ▒ ▓██▒  ██▒ ▀█▒
       ▓██    ▓██░   ▒▓█    ▄  ▒██░  ██▒▓ ██  ▀█ ██▒ ▒████ ░ ▒██▒▒ ██░▄▄▄░
       ▒██    ▒██    ▒▓▓▄ ▄██ ▒▒██   ██░▓ ██▒  ▐▌██▒ ░▓█▒  ░ ░██░░ ▓█  ██▓
       ▒██▒   ░██▒   ▒ ▓███▀  ░░ ████▓▒░▒ ██░   ▓██░ ░▒█░    ░██░░ ▒▓███▀▒
       ░ ▒░   ░  ░   ░ ░▒ ▒   ░░ ▒░▒░▒░ ░  ▒░   ▒ ▒   ▒ ░    ░▓    ░▒   ▒ 
       ░  ░      ░     ░  ▒      ░ ▒ ▒░ ░  ░░   ░ ▒░  ░       ▒ ░   ░   ░ 
       ░      ░      ░         ░ ░ ░ ▒      ░   ░ ░   ░ ░     ▒ ░░  ░   ░ 
              ░      ░ ░           ░ ░           ░           ░         ░ 
                     ░                                                               
EOF
  printf '\033[0m'
}

ensure_brew_on_path() {
  if command -v brew > /dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

has_clt() {
  xcode-select -p > /dev/null 2>&1 && xcrun --find clang > /dev/null 2>&1
}

repair_developer_dir_if_broken() {
  local current_dir
  current_dir="$(xcode-select -p 2> /dev/null || true)"

  if [[ -n "${current_dir}" && -d "${current_dir}" ]]; then
    return 0
  fi
  if [[ ! -d /Library/Developer/CommandLineTools ]]; then
    return 0
  fi

  log "Found Command Line Tools at /Library/Developer/CommandLineTools, but xcode-select is not pointing to a valid developer directory."
  if confirm "Switch xcode-select to /Library/Developer/CommandLineTools?"; then
    require_sudo
    sudo xcode-select --switch /Library/Developer/CommandLineTools
  else
    log "Cannot continue with an invalid xcode-select developer directory."
    exit 1
  fi
}

wait_for_clt_install() {
  local timeout_seconds="${1}"
  local elapsed=0

  while ((elapsed < timeout_seconds)); do
    if has_clt; then
      return 0
    fi
    sleep "${CLT_POLL_INTERVAL_SECONDS}"
    elapsed=$((elapsed + CLT_POLL_INTERVAL_SECONDS))
  done
  return 1
}

install_clt_if_missing() {
  if has_clt; then
    log "Xcode Command Line Tools already installed."
    return 0
  fi

  log "Xcode Command Line Tools are required for this installer."
  if ! confirm "Install Xcode Command Line Tools now?"; then
    log "Xcode Command Line Tools are required. Exiting."
    exit 1
  fi

  log "Launching Xcode Command Line Tools installer."
  if ! xcode-select --install > /dev/null 2>&1; then
    log "xcode-select --install returned a non-zero status. If the installer is already running, waiting for completion."
  fi

  log "Waiting for Command Line Tools installation to complete."
  if ! wait_for_clt_install "${CLT_TIMEOUT_SECONDS}"; then
    log "Timed out waiting for Command Line Tools installation."
    log "Finish the installation from the macOS prompt, then rerun this script."
    exit 1
  fi
}

validate_clt() {
  if ! has_clt; then
    log "Xcode Command Line Tools validation failed."
    exit 1
  fi

  local dev_dir
  local clang_path
  dev_dir="$(xcode-select -p)"
  clang_path="$(xcrun --find clang)"
  log "Command Line Tools ready. Developer dir: ${dev_dir}"
  log "clang found at: ${clang_path}"

  if ! git --version > /dev/null 2>&1; then
    log "git command not available after CLT setup."
    exit 1
  fi
}

ensure_xcode_clt() {
  repair_developer_dir_if_broken
  install_clt_if_missing
  validate_clt
}

clone_repo() {
  log "Checking for dotfiles repo at ${TARGET_DIR}."
  if [[ -d "${TARGET_DIR}/.git" ]]; then
    log "Repo already exists. Skipping clone."
    return 0
  fi
  if [[ -e "${TARGET_DIR}" ]]; then
    log "Path ${TARGET_DIR} exists but is not a git repo. Please move it aside."
    exit 1
  fi
  if confirm "Clone dotfiles repo (${REPO_URL}) to ${TARGET_DIR}?"; then
    git clone "${REPO_URL}" "${TARGET_DIR}"
  else
    log "Skipping clone."
  fi
}

install_homebrew() {
  ensure_brew_on_path
  if command -v brew > /dev/null 2>&1; then
    log "Homebrew already installed. Skipping."
    return 0
  fi
  if confirm "Install Homebrew?"; then
    require_sudo
    eval "${BREW_INSTALL_CMD}"
    ensure_brew_on_path
  else
    log "Skipping Homebrew install."
  fi
}

install_oh_my_zsh() {
  if [[ -d "${HOME}/.oh-my-zsh" ]]; then
    log "Oh-My-Zsh already installed. Skipping."
    return 0
  fi
  if confirm "Install Oh-My-Zsh?"; then
    RUNZSH=no CHSH=no KEEP_ZSHRC=yes eval "${OMZ_INSTALL_CMD}"
  else
    log "Skipping Oh-My-Zsh install."
  fi
}

install_omz_plugins() {
  if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
    log "Oh-My-Zsh not found. Skipping plugin install."
    return 0
  fi
  local zsh_custom="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"
  local autosuggest_dir="${zsh_custom}/plugins/zsh-autosuggestions"
  local completions_dir="${zsh_custom}/plugins/zsh-completions"

  log "Installing Oh-My-Zsh plugins."
  if [[ -d "${autosuggest_dir}" ]]; then
    log "zsh-autosuggestions already installed. Skipping."
  else
    if confirm "Install zsh-autosuggestions?"; then
      git clone https://github.com/zsh-users/zsh-autosuggestions "${autosuggest_dir}"
    else
      log "Skipping zsh-autosuggestions."
    fi
  fi

  if [[ -d "${completions_dir}" ]]; then
    log "zsh-completions already installed. Skipping."
  else
    if confirm "Install zsh-completions?"; then
      git clone https://github.com/zsh-users/zsh-completions.git "${completions_dir}"
    else
      log "Skipping zsh-completions."
    fi
  fi
}

brewfile_has_entry() {
  local brewfile="${1}"
  local type="${2}"
  local name="${3}"
  grep -E "^[[:space:]]*${type}[[:space:]]+\"${name}\"([[:space:],#]|$)" "${brewfile}" > /dev/null 2>&1
}

install_migrated_brew_casks() {
  local brewfile="${1}"
  if brewfile_has_entry "${brewfile}" brew codex && ! brewfile_has_entry "${brewfile}" cask codex; then
    log "Installing codex as a Homebrew cask because the formula has migrated."
    brew install --cask codex
  fi
}

run_brew_bundle() {
  local brewfile="${1}"
  local tap_skip
  local brew_skip

  tap_skip="$(append_words "${HOMEBREW_BUNDLE_TAP_SKIP:-}" "${BREW_BUNDLE_DEPRECATED_TAPS[@]}")"
  brew_skip="$(append_words "${HOMEBREW_BUNDLE_BREW_SKIP:-}" "${BREW_BUNDLE_MIGRATED_FORMULAE_TO_CASKS[@]}")"

  log "Running brew bundle."
  HOMEBREW_BUNDLE_TAP_SKIP="${tap_skip}" HOMEBREW_BUNDLE_BREW_SKIP="${brew_skip}" brew bundle --file "${brewfile}"
  install_migrated_brew_casks "${brewfile}"
}

install_brew_bundle() {
  local brewfile=""
  ensure_brew_on_path
  if ! command -v brew > /dev/null 2>&1; then
    log "Homebrew not found. Skipping Brewfile."
    return 0
  fi
  if ! brewfile="$(brewfile_path)"; then
    log "Brewfile not found at ${TARGET_DIR}/homebrew/.config/homebrew/Brewfile or ${TARGET_DIR}/Brewfile. Skipping."
    return 0
  fi
  if confirm "Install Brewfile packages from ${brewfile}?"; then
    require_sudo
    run_brew_bundle "${brewfile}"
  else
    log "Skipping Brewfile install."
  fi
}

is_homebrew_maintenance_loaded() {
  if ! command -v launchctl > /dev/null 2>&1; then
    return 1
  fi

  launchctl print "gui/$(id -u)/${HOMEBREW_MAINTENANCE_LABEL}" > /dev/null 2>&1
}

setup_homebrew_maintenance() {
  local plist_path
  local script_path
  plist_path="$(homebrew_maintenance_plist_path)"
  script_path="$(homebrew_maintenance_script_path)"

  if [[ ! -f "${plist_path}" || ! -f "${script_path}" ]]; then
    log "Homebrew maintenance LaunchAgent or script not found. Skipping scheduled Homebrew maintenance setup."
    return 0
  fi

  if ! command -v launchctl > /dev/null 2>&1; then
    log "launchctl not found. Skipping scheduled Homebrew maintenance setup."
    return 0
  fi

  if is_homebrew_maintenance_loaded; then
    log "Homebrew maintenance LaunchAgent is already loaded."
    return 0
  fi

  if confirm "Enable daily Homebrew maintenance LaunchAgent?"; then
    if ! launchctl bootstrap "gui/$(id -u)" "${plist_path}"; then
      log "Unable to bootstrap Homebrew maintenance LaunchAgent. Continuing."
      return 0
    fi

    if ! launchctl enable "gui/$(id -u)/${HOMEBREW_MAINTENANCE_LABEL}"; then
      log "Unable to enable Homebrew maintenance LaunchAgent. Continuing."
      return 0
    fi
  else
    log "Skipping scheduled Homebrew maintenance setup."
  fi
}

setup_node_runtime() {
  ensure_brew_on_path
  if ! command -v brew > /dev/null 2>&1; then
    log "Homebrew not found. Skipping Node runtime setup."
    return 0
  fi

  if ! command -v mise > /dev/null 2>&1; then
    log "mise is not installed."
    if confirm "Install mise with Homebrew now?"; then
      brew install mise
    else
      log "Skipping Node runtime setup."
      return 0
    fi
  fi

  if ! command -v mise > /dev/null 2>&1; then
    log "mise not found on PATH after install. Skipping Node runtime setup."
    return 0
  fi

  if confirm "Install Node.js LTS with mise and set it as the global default?"; then
    mise use --global node@lts
  else
    log "Skipping Node.js LTS install."
  fi

  if confirm "Enable mise support for .nvmrc and .node-version files?"; then
    if ! mise settings add idiomatic_version_file_enable_tools node; then
      log "Unable to update mise idiomatic Node version file setting. Continuing."
    fi
  else
    log "Skipping mise idiomatic Node version file support."
  fi
}

setup_app_defaults() {
  local defaults_script
  defaults_script="$(script_path "macos-set-default-apps.sh")"

  if [[ ! -f "${defaults_script}" ]]; then
    log "Default-app setup script not found at ${defaults_script}. Skipping."
    return 0
  fi

  if ! command -v duti > /dev/null 2>&1; then
    log "duti not found. Skipping default app setup."
    return 0
  fi

  local required_apps=(
    "/Applications/Helium.app"
    "/Applications/Microsoft Edge.app"
    "/Applications/WezTerm.app"
  )
  local missing_apps=()
  local app_path
  for app_path in "${required_apps[@]}"; do
    if [[ ! -d "${app_path}" ]]; then
      missing_apps+=("${app_path}")
    fi
  done

  if [[ "${#missing_apps[@]}" -gt 0 ]]; then
    log "Required app(s) not found for default app setup: ${missing_apps[*]}"
    log "Skipping default app setup."
    return 0
  fi

  if confirm "Set Helium as browser, Microsoft Edge as PDF reader, and WezTerm as terminal handler?"; then
    DOTFILES_DIR="${TARGET_DIR}" bash "${defaults_script}"
  else
    log "Skipping default app setup."
  fi
}

# Offer the dotfiles macOS tuning profile without making personal UI changes mandatory.
setup_macos_performance_beauty() {
  local tuning_script
  tuning_script="$(script_path "macos-performance-beauty.sh")"

  if [[ ! -f "${tuning_script}" ]]; then
    log "macOS performance and appearance script not found at ${tuning_script}. Skipping."
    return 0
  fi

  if confirm "Apply macOS performance and appearance defaults from dotfiles?"; then
    DOTFILES_DIR="${TARGET_DIR}" bash "${tuning_script}"
  else
    log "Skipping macOS performance and appearance defaults."
  fi
}

# Downloads LazyVim plugins after the nvim package has been stowed.
bootstrap_neovim() {
  if ! command -v nvim > /dev/null 2>&1; then
    log "nvim not found. Skipping LazyVim plugin bootstrap."
    return 0
  fi

  local lazy_spec="${HOME}/.config/nvim/lua/config/lazy.lua"
  if [[ ! -f "${lazy_spec}" ]]; then
    log "LazyVim spec not found at ${lazy_spec}. Skipping LazyVim plugin bootstrap."
    return 0
  fi

  if confirm "Bootstrap LazyVim plugins now? This downloads plugin sources and can take several minutes."; then
    log "Syncing LazyVim plugins."
    if nvim --headless "+Lazy! sync" +qa; then
      log "LazyVim plugins synced."
    else
      log "LazyVim plugin bootstrap failed. Run nvim once to finish installation."
    fi
  else
    log "Skipping LazyVim plugin bootstrap."
  fi
}

# Runs the dotfiles extension synchronizer after validating prerequisites and consent.
install_vscodium_extensions() {
  local extensions_script
  extensions_script="$(script_path "vscodium-install-extensions.sh")"

  if [[ ! -f "${extensions_script}" ]]; then
    log "VSCodium extension installer not found at ${extensions_script}. Skipping."
    return 0
  fi

  ensure_codium_on_path
  if ! command -v codium > /dev/null 2>&1; then
    log "codium command not found. Skipping VSCodium extension install."
    return 0
  fi

  if confirm "Install missing VSCodium extensions from dotfiles?"; then
    DOTFILES_DIR="${TARGET_DIR}" bash "${extensions_script}"
  else
    log "Skipping VSCodium extension install."
  fi
}

install_browser_extensions() {
  local urls_file="${TARGET_DIR}/browser/extensions-urls.txt"
  if [[ ! -f "${urls_file}" ]]; then
    log "Browser extension URL list not found at ${urls_file}. Skipping browser extension setup."
    return 0
  fi

  if ! command -v open > /dev/null 2>&1; then
    log "macOS open command not found. Skipping browser extension setup."
    return 0
  fi

  local installed_apps=()
  local entry
  for entry in "${CHROMIUM_BROWSER_APPS[@]}"; do
    local app_path="${entry#*|}"
    if [[ -d "${app_path}" ]]; then
      installed_apps+=("${entry}")
    fi
  done

  if [[ "${#installed_apps[@]}" -eq 0 ]]; then
    log "No managed Chromium-family browser apps found. Skipping browser extension setup."
    return 0
  fi

  local installed_labels=()
  for entry in "${installed_apps[@]}"; do
    installed_labels+=("${entry%%|*}")
  done

  log "Managed Chromium-family browser apps found: ${installed_labels[*]}"
  if ! confirm "Open browser extension pages in each installed managed Chromium browser?"; then
    log "Skipping browser extension setup."
    return 0
  fi

  for entry in "${installed_apps[@]}"; do
    local label="${entry%%|*}"
    local app_path="${entry#*|}"
    local url=""
    log "Opening browser extension pages in ${label}."
    while IFS= read -r url || [[ -n "${url}" ]]; do
      [[ -n "${url}" ]] || continue
      [[ "${url}" == \#* ]] && continue
      open -a "${app_path}" "${url}"
      sleep 0.15
    done < "${urls_file}"
  done

  log "Done opening browser extension pages. Install each extension manually from the opened tabs."
}

ai_memory_macos_asset() {
  local arch="${1:-$(uname -m)}"
  case "${arch}" in
    arm64 | aarch64) printf 'ai-memory-macos-aarch64.tar.gz\n' ;;
    x86_64) printf 'ai-memory-macos-x86_64.tar.gz\n' ;;
    *) return 1 ;;
  esac
}

ai_memory_binary_path() {
  printf '%s/Applications/ai-memory/ai-memory\n' "${HOME}"
}

ai_memory_installed() {
  local binary
  binary="$(ai_memory_binary_path)"
  [[ -x "${binary}" && ! -d "${binary}" ]]
}

ai_memory_extract_root() {
  local extract_dir="${1}"
  local nested
  if [[ -x "${extract_dir}/ai-memory" && ! -d "${extract_dir}/ai-memory" ]]; then
    printf '%s\n' "${extract_dir}"
    return 0
  fi
  nested="$(find "${extract_dir}" -mindepth 2 -maxdepth 2 -type f -name ai-memory -perm -111 -print -quit)"
  if [[ -n "${nested}" ]]; then
    dirname "${nested}"
    return 0
  fi
  return 1
}

file_sha256() {
  local file="${1}"
  if command -v shasum > /dev/null 2>&1; then
    shasum -a 256 "${file}" | awk '{ print $1 }'
    return 0
  fi
  sha256sum "${file}" | awk '{ print $1 }'
}

ensure_ai_memory_symlink() {
  local binary
  local link_dir
  local link_path
  binary="$(ai_memory_binary_path)"
  link_dir="${HOME}/.local/bin"
  link_path="${link_dir}/ai-memory"
  if ! ai_memory_installed; then
    return 0
  fi
  mkdir -p "${link_dir}"
  ln -sfn "${binary}" "${link_path}"
}

ensure_local_bin_on_path() {
  local zshrc="${HOME}/.zshrc"
  local link_path="${HOME}/.local/bin/ai-memory"
  if [[ ! -e "${link_path}" ]]; then
    return 0
  fi
  if [[ -f "${zshrc}" ]] && grep -Fq "${LOCAL_BIN_PATH_EXPORT}" "${zshrc}"; then
    log "${HOME}/.local/bin is already on PATH in ${zshrc}."
    return 0
  fi
  if ! confirm "Add ${HOME}/.local/bin to PATH in ${zshrc} so ai-memory is found in new shells?"; then
    log "Skipping PATH update. ai-memory stays unreachable until ${HOME}/.local/bin is on PATH."
    return 0
  fi
  touch "${zshrc}"
  if [[ -s "${zshrc}" ]]; then
    printf '\n%s\n' "${LOCAL_BIN_PATH_EXPORT}" >> "${zshrc}"
  else
    printf '%s\n' "${LOCAL_BIN_PATH_EXPORT}" >> "${zshrc}"
  fi
  log "Added ${HOME}/.local/bin to PATH in ${zshrc}. Start a new shell to use it."
}

install_ai_memory_release() {
  local asset
  local stage
  local archive
  local expected
  local actual
  local extract_root
  local dest
  if ! asset="$(ai_memory_macos_asset)"; then
    log "Unsupported architecture for the ai-memory macOS release: $(uname -m)"
    return 1
  fi
  stage="$(mktemp -d "${TMPDIR:-/tmp}/ai-memory.XXXXXX")"
  archive="${stage}/${asset}"
  if ! curl -fsSL "${AI_MEMORY_RELEASE_BASE}/${asset}" -o "${archive}"; then
    rm -rf "${stage}"
    log "Unable to download the ai-memory release."
    return 1
  fi
  if ! curl -fsSL "${AI_MEMORY_RELEASE_BASE}/${asset}.sha256" -o "${archive}.sha256"; then
    rm -rf "${stage}"
    log "Unable to download the ai-memory checksum."
    return 1
  fi
  expected="$(awk 'NR == 1 { print $1 }' "${archive}.sha256")"
  actual="$(file_sha256 "${archive}")"
  if [[ -z "${expected}" || "${actual}" != "${expected}" ]]; then
    rm -rf "${stage}"
    log "ai-memory checksum mismatch. Refusing to install."
    return 1
  fi
  mkdir -p "${stage}/extract"
  if ! tar -xzf "${archive}" -C "${stage}/extract"; then
    rm -rf "${stage}"
    log "Unable to extract the ai-memory release."
    return 1
  fi
  if ! extract_root="$(ai_memory_extract_root "${stage}/extract")"; then
    rm -rf "${stage}"
    log "ai-memory release did not contain the expected binary."
    return 1
  fi
  dest="${HOME}/Applications/ai-memory"
  mkdir -p "${HOME}/Applications"
  rm -rf "${dest}"
  if [[ "${extract_root}" == "${stage}/extract" ]]; then
    mv "${extract_root}" "${dest}"
  else
    mkdir -p "${dest}"
    mv "${extract_root}/." "${dest}/"
  fi
  rm -rf "${stage}"
  if ! ai_memory_installed; then
    log "ai-memory binary is missing after extraction."
    return 1
  fi
}

init_ai_memory_if_needed() {
  local binary
  local data_dir
  binary="$(ai_memory_binary_path)"
  data_dir="${HOME}/Library/Application Support/ai-memory"
  if [[ -d "${data_dir}" ]]; then
    log "ai-memory data directory already exists. Skipping init."
    return 0
  fi
  if ! "${binary}" init; then
    log "ai-memory init failed. Continuing."
    return 0
  fi
  log "ai-memory data directory initialized."
}

setup_ai_memory_launchd() {
  local template
  local plist_path
  local binary
  template="${HOME}/Applications/ai-memory/packaging/launchd/${AI_MEMORY_LAUNCHD_LABEL}.plist"
  plist_path="${HOME}/Library/LaunchAgents/${AI_MEMORY_LAUNCHD_LABEL}.plist"
  binary="$(ai_memory_binary_path)"
  if [[ ! -f "${template}" ]]; then
    log "ai-memory LaunchAgent template not found. Skipping login service."
    return 0
  fi
  if ! command -v launchctl > /dev/null 2>&1; then
    log "launchctl not found. Skipping ai-memory login service."
    return 0
  fi
  if launchctl print "gui/$(id -u)/${AI_MEMORY_LAUNCHD_LABEL}" > /dev/null 2>&1; then
    log "ai-memory LaunchAgent is already loaded."
    return 0
  fi
  if ! confirm "Start ai-memory at login?"; then
    log "Skipping ai-memory login service."
    return 0
  fi
  mkdir -p "${HOME}/Library/Logs/ai-memory" "${HOME}/Library/LaunchAgents"
  sed -e "s|__AI_MEMORY_BIN__|${binary}|g" -e "s|__HOME__|${HOME}|g" "${template}" > "${plist_path}"
  if ! launchctl bootstrap "gui/$(id -u)" "${plist_path}"; then
    log "Unable to bootstrap the ai-memory LaunchAgent. Continuing."
    return 0
  fi
  log "ai-memory LaunchAgent loaded."
}

install_ai_memory() {
  local already_installed=0
  if ai_memory_installed; then
    already_installed=1
    log "ai-memory already installed. Skipping download."
    ensure_ai_memory_symlink
  else
    if ! confirm "Install ai-memory from the latest macOS release?"; then
      log "Skipping ai-memory install."
      return 0
    fi
    if ! install_ai_memory_release; then
      log "ai-memory install failed. Continuing."
      return 0
    fi
    ensure_ai_memory_symlink
  fi
  init_ai_memory_if_needed
  setup_ai_memory_launchd
  if [[ "${already_installed}" -eq 0 ]]; then
    log "ai-memory installed at $(ai_memory_binary_path)."
  fi
}

rtk_is_token_killer() {
  command -v rtk > /dev/null 2>&1 && rtk gain --help > /dev/null 2>&1
}

install_rtk() {
  ensure_brew_on_path
  if ! command -v brew > /dev/null 2>&1; then
    log "Homebrew not found. Skipping RTK install."
    return 0
  fi
  if rtk_is_token_killer; then
    log "RTK token killer already installed. Skipping."
    return 0
  fi
  if ! confirm "Install RTK (rtk-ai/rtk) with Homebrew?"; then
    log "Skipping RTK install."
    return 0
  fi
  if ! brew install rtk; then
    log "RTK Homebrew install failed. Continuing."
    return 0
  fi
  if ! rtk_is_token_killer; then
    log "Installed rtk does not provide rtk gain. This is not the rtk-ai token killer. Continuing."
    return 0
  fi
  log "RTK token killer installed."
}

hermes_skill_present() {
  local name="${1}"
  command -v hermes > /dev/null 2>&1 || return 1
  hermes skills list 2> /dev/null | grep -Eq "(^|[^[:alnum:]_-])${name}([^[:alnum:]_-]|$)"
}

install_hermes_skills() {
  local index
  local identifier
  local name
  ensure_brew_on_path
  if ! command -v hermes > /dev/null 2>&1; then
    log "hermes not found. Skipping Hermes skill install."
    return 0
  fi
  if ! confirm "Install Hermes skills i-have-adhd and teach?"; then
    log "Skipping Hermes skill install."
    return 0
  fi
  for index in "${!HERMES_SKILL_IDENTIFIERS[@]}"; do
    identifier="${HERMES_SKILL_IDENTIFIERS[${index}]}"
    name="${HERMES_SKILL_NAMES[${index}]}"
    if hermes_skill_present "${name}"; then
      log "Hermes skill ${name} already installed. Skipping."
      continue
    fi
    if ! hermes skills install "${identifier}" --yes; then
      log "Unable to install Hermes skill ${name}. Continuing."
    fi
  done
}

extract_stow_conflict_targets() {
  local line
  local rel

  while IFS= read -r line; do
    rel=""
    if [[ "${line}" == *"existing target is not owned by stow: "* ]]; then
      rel="${line##*existing target is not owned by stow: }"
    elif [[ "${line}" == *" over existing target "* ]]; then
      rel="${line#* over existing target }"
      rel="${rel%% since *}"
    fi

    if [[ -n "${rel}" ]]; then
      printf '%s\n' "${rel#./}"
    fi
  done
}

backup_stow_conflicts() {
  local dry_output="${1}"
  local backup_dir="${2}"
  local conflict_targets=()
  local rel

  while IFS= read -r rel; do
    [[ -n "${rel}" ]] || continue
    if [[ "${#conflict_targets[@]}" -eq 0 ]] || ! array_contains "${rel}" "${conflict_targets[@]}"; then
      conflict_targets+=("${rel}")
    fi
  done < <(printf '%s\n' "${dry_output}" | extract_stow_conflict_targets)

  if [[ "${#conflict_targets[@]}" -eq 0 ]]; then
    log "No specific stow conflict targets could be parsed. Skipping backup."
    return 1
  fi

  mkdir -p "${backup_dir}"
  for rel in "${conflict_targets[@]}"; do
    if [[ "${rel}" == /* || "${rel}" == ".." || "${rel}" == ../* || "${rel}" == */../* ]]; then
      log "Skipping unsafe conflict path from stow output: ${rel}"
      continue
    fi

    local dest="${HOME}/${rel}"
    if [[ -e "${dest}" || -L "${dest}" ]]; then
      mkdir -p "${backup_dir}/$(dirname "${rel}")"
      mv "${dest}" "${backup_dir}/${rel}"
      log "Moved ${dest} to ${backup_dir}/${rel}."
    fi
  done
}

stow_packages() {
  if ! command -v stow > /dev/null 2>&1; then
    log "GNU Stow not found. Skipping stow step."
    return 0
  fi

  local packages=()
  local package
  while IFS= read -r package; do
    packages+=("${package}")
  done < <(discover_stow_packages)

  local skipped_packages=()
  for package in "${NON_STOW_PACKAGES[@]}"; do
    if [[ -d "${TARGET_DIR}/${package}" ]]; then
      skipped_packages+=("${package}")
    fi
  done

  if [[ "${#packages[@]}" -eq 0 ]]; then
    log "No stow packages found."
    return 0
  fi

  if [[ "${#skipped_packages[@]}" -gt 0 ]]; then
    log "The following dotfiles data directories will not be stowed: ${skipped_packages[*]}"
  fi

  log "The following packages will be stowed: ${packages[*]}"
  if confirm "Stow all packages into ${HOME}?"; then
    local stow_args=(-d "${TARGET_DIR}" -t "${HOME}")
    local ignore_pattern
    for ignore_pattern in "${STOW_IGNORE_PATTERNS[@]}"; do
      stow_args+=(--ignore="${ignore_pattern}")
    done
    stow_args+=("${packages[@]}")
    log "Running stow dry-run to detect conflicts."
    local dry_output
    local dry_status=0
    dry_output="$(stow -n -v "${stow_args[@]}" 2>&1)" || dry_status=$?

    local has_conflicts=0
    if printf '%s' "${dry_output}" | grep -E "existing target|CONFLICT" > /dev/null 2>&1; then
      has_conflicts=1
    fi

    if [[ "${dry_status}" -ne 0 && "${has_conflicts}" -eq 0 ]]; then
      log "Stow dry-run failed without a recognized conflict. Skipping stow."
      printf '%s\n' "${dry_output}"
      return 0
    fi

    if [[ "${has_conflicts}" -eq 1 ]]; then
      log "Stow dry-run detected conflicts."
      printf '%s\n' "${dry_output}"
      if confirm "Move conflicting files to a backup directory and continue?"; then
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        if backup_stow_conflicts "${dry_output}" "${HOME}/.dotfiles-backup/${timestamp}"; then
          stow -v "${stow_args[@]}"
        else
          log "Skipping stow because conflicts could not be backed up safely."
        fi
      else
        log "Skipping stow due to conflicts."
      fi
      return 0
    fi

    log "Dry-run looks clean."
    if confirm "Proceed with stow?"; then
      stow -v "${stow_args[@]}"
    else
      log "Skipping stow."
    fi
  else
    log "Skipping stow."
  fi
}

main() {
  parse_args "$@"
  require_macos
  require_interactive_tty
  print_banner

  log "Starting dotfiles setup."
  ensure_xcode_clt
  clone_repo
  install_homebrew
  install_oh_my_zsh
  install_omz_plugins
  install_brew_bundle
  install_rtk
  install_ai_memory
  setup_node_runtime
  stow_packages
  ensure_local_bin_on_path
  setup_context7_api_key
  bootstrap_neovim
  setup_homebrew_maintenance
  setup_macos_performance_beauty
  setup_app_defaults
  install_vscodium_extensions
  install_browser_extensions
  install_hermes_skills
  log "Done."
}

if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
