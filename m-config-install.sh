#!/usr/bin/env bash
set -euo pipefail

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

REPO_URL="https://github.com/m-software-engineering/dotfiles.git"
TARGET_DIR="${HOME}/dotfiles"
BREW_INSTALL_CMD='/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
OMZ_INSTALL_CMD='sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'

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
  if confirm "Clone dotfiles repo to ${TARGET_DIR}? [y/N] "; then
    git clone "${REPO_URL}" "${TARGET_DIR}"
  else
    log "Skipping clone."
  fi
}

install_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    log "Homebrew already installed. Skipping."
    return 0
  fi
  if confirm "Install Homebrew? [y/N] "; then
    require_sudo
    eval "${BREW_INSTALL_CMD}"
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv)"
    fi
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
  if ! command -v brew >/dev/null 2>&1; then
    log "Homebrew not found. Skipping Brewfile."
    return 0
  fi
  if [[ ! -f "${brewfile}" ]]; then
    log "Brewfile not found at ${brewfile}. Skipping."
    return 0
  fi
  if confirm "Install Brewfile packages? [y/N] "; then
    require_sudo
    brew bundle --file "${brewfile}"
  else
    log "Skipping Brewfile install."
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
              find . -type f -o -type l | sed 's|^\./||' | while read -r rel; do
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
  log "Starting dotfiles setup."
  clone_repo
  install_homebrew
  install_oh_my_zsh
  install_omz_plugins
  install_brew_bundle
  stow_packages
  log "Done."
}

main "$@"
