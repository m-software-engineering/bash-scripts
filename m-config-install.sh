#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/m-software-engineering/dotfiles.git"
DEFAULT_TARGET_DIR="${HOME}/dotfiles"
SAFE_CURL_URL="https://raw.githubusercontent.com/m-software-engineering/bash-scripts/refs/heads/main/m-config-install.sh"
BREW_INSTALL_CMD='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
OMZ_INSTALL_CMD='sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
CLT_TIMEOUT_SECONDS=1800
CLT_POLL_INTERVAL_SECONDS=15

REPO_URL="${DOTFILES_REPO_URL:-${DEFAULT_REPO_URL}}"
TARGET_DIR="${DOTFILES_DIR:-${DEFAULT_TARGET_DIR}}"

usage() {
  cat <<EOF
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
  local prompt="${1:-Continue?} [y/N] "
  read -r -p "$prompt" reply
  case "${reply}" in
    [yY]|[yY][eE][sS]) return 0 ;;
    *) return 1 ;;
  esac
}

require_sudo() {
  log "Requesting sudo for the next step."
  sudo -v
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dotfiles-dir)
        [[ "$#" -ge 2 ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 1; }
        TARGET_DIR="$2"
        shift 2
        ;;
      --repo-url)
        [[ "$#" -ge 2 ]] || { printf 'Missing value for %s\n' "$1" >&2; exit 1; }
        REPO_URL="$2"
        shift 2
        ;;
      -h|--help)
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
    cat <<EOF >&2
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
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

has_clt() {
  xcode-select -p >/dev/null 2>&1 && xcrun --find clang >/dev/null 2>&1
}

repair_developer_dir_if_broken() {
  local current_dir
  current_dir="$(xcode-select -p 2>/dev/null || true)"

  if [[ -n "${current_dir}" && -d "${current_dir}" ]]; then
    return 0
  fi
  if [[ ! -d /Library/Developer/CommandLineTools ]]; then
    return 0
  fi

  log "Found Command Line Tools at /Library/Developer/CommandLineTools, but xcode-select is not pointing to a valid developer directory."
  if confirm "Switch xcode-select to /Library/Developer/CommandLineTools? [y/N] "; then
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

  while (( elapsed < timeout_seconds )); do
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
  if ! confirm "Install Xcode Command Line Tools now? [y/N] "; then
    log "Xcode Command Line Tools are required. Exiting."
    exit 1
  fi

  log "Launching Xcode Command Line Tools installer."
  if ! xcode-select --install >/dev/null 2>&1; then
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

  if ! git --version >/dev/null 2>&1; then
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
  if confirm "Clone dotfiles repo (${REPO_URL}) to ${TARGET_DIR}? [y/N] "; then
    git clone "${REPO_URL}" "${TARGET_DIR}"
  else
    log "Skipping clone."
  fi
}

install_homebrew() {
  ensure_brew_on_path
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed. Skipping."
    return 0
  fi
  if confirm "Install Homebrew? [y/N] "; then
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
  if confirm "Install Oh-My-Zsh? [y/N] "; then
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
    if confirm "Install zsh-autosuggestions? [y/N] "; then
      git clone https://github.com/zsh-users/zsh-autosuggestions "${autosuggest_dir}"
    else
      log "Skipping zsh-autosuggestions."
    fi
  fi

  if [[ -d "${completions_dir}" ]]; then
    log "zsh-completions already installed. Skipping."
  else
    if confirm "Install zsh-completions? [y/N] "; then
      git clone https://github.com/zsh-users/zsh-completions.git "${completions_dir}"
    else
      log "Skipping zsh-completions."
    fi
  fi
}

install_brew_bundle() {
  local brewfile="${TARGET_DIR}/Brewfile"
  ensure_brew_on_path
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Skipping Brewfile."
    return 0
  fi
  if [[ ! -f "${brewfile}" ]]; then
    log "Brewfile not found at ${brewfile}. Skipping."
    return 0
  fi
  if confirm "Install Brewfile packages from ${brewfile}? [y/N] "; then
    require_sudo
    brew bundle --file "${brewfile}"
  else
    log "Skipping Brewfile install."
  fi
}

setup_node_runtime() {
  ensure_brew_on_path
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Skipping Node runtime setup."
    return 0
  fi

  if ! brew list --versions nvm >/dev/null 2>&1; then
    log "nvm is not installed."
    if confirm "Install nvm with Homebrew now? [y/N] "; then
      brew install nvm
    else
      log "Skipping Node runtime setup."
      return 0
    fi
  fi

  local brew_prefix
  local nvm_sh
  brew_prefix="$(brew --prefix nvm 2>/dev/null || true)"
  nvm_sh="${brew_prefix}/nvm.sh"
  if [[ ! -s "${nvm_sh}" ]]; then
    log "nvm.sh not found at ${nvm_sh}. Skipping Node runtime setup."
    return 0
  fi

  export NVM_DIR="${NVM_DIR:-${HOME}/.nvm}"
  mkdir -p "${NVM_DIR}"
  # shellcheck disable=SC1090
  . "${nvm_sh}"

  if [[ "$(nvm version --lts 2>/dev/null || printf 'N/A')" == "N/A" ]]; then
    log "Installing Node.js LTS with nvm."
    nvm install --lts
  fi

  nvm alias default 'lts/*' >/dev/null
  nvm use --lts >/dev/null

  if command -v corepack >/dev/null 2>&1; then
    corepack enable >/dev/null 2>&1 || true
    log "Enabled corepack."
  else
    log "corepack not found. Skipping corepack enable."
  fi
}

stow_packages() {
  if ! command -v stow >/dev/null 2>&1; then
    log "GNU Stow not found. Skipping stow step."
    return 0
  fi

  local packages=()
  local dir
  for dir in "${TARGET_DIR}"/*; do
    [[ -d "${dir}" ]] || continue
    local name
    name="$(basename "${dir}")"
    [[ "${name}" == .* ]] && continue
    packages+=("${name}")
  done

  if [[ "${#packages[@]}" -eq 0 ]]; then
    log "No stow packages found."
    return 0
  fi

  log "The following packages will be stowed: ${packages[*]}"
  if confirm "Stow all packages into ${HOME}? [y/N] "; then
    local stow_args=(-d "${TARGET_DIR}" -t "${HOME}" "${packages[@]}")
    log "Running stow dry-run to detect conflicts."
    local dry_output
    if ! dry_output="$(stow -n -v "${stow_args[@]}" 2>&1)"; then
      log "Stow dry-run reported issues:"
      printf '%s\n' "${dry_output}"
    fi

    if printf '%s' "${dry_output}" | grep -E "existing target|CONFLICT" >/dev/null 2>&1; then
      log "Stow dry-run detected conflicts."
      printf '%s\n' "${dry_output}"
      if confirm "Move conflicting files to a backup directory and continue? [y/N] "; then
        local timestamp
        timestamp="$(date +%Y%m%d-%H%M%S)"
        local pkg
        for pkg in "${packages[@]}"; do
          local pkg_dir="${TARGET_DIR}/${pkg}"
          local backup_dir="${HOME}/.dotfiles-backup/${timestamp}/${pkg}"
          if [[ -d "${pkg_dir}" ]]; then
            log "Backing up conflicts for package ${pkg}."
            mkdir -p "${backup_dir}"
            (
              cd "${pkg_dir}"
              find . \( -type f -o -type l \) | sed 's|^\./||' | while read -r rel; do
                local dest="${HOME}/${rel}"
                if [[ -e "${dest}" && ! -L "${dest}" ]]; then
                  mkdir -p "${backup_dir}/$(dirname "${rel}")"
                  mv "${dest}" "${backup_dir}/${rel}"
                fi
              done
            )
          fi
        done
        stow -v "${stow_args[@]}"
      else
        log "Skipping stow due to conflicts."
      fi
      return 0
    fi

    log "Dry-run looks clean."
    if confirm "Proceed with stow? [y/N] "; then
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
  setup_node_runtime
  stow_packages
  log "Done."
}

main "$@"
