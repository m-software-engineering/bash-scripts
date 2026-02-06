# bash-scripts

Small collection of utility bash scripts. Currently this repo includes a guided installer to bootstrap a dotfiles setup on macOS.

## Contents

- `m-config-install.sh`: interactive setup for the `m-software-engineering/dotfiles` repo.

## What the installer does

`m-config-install.sh` walks you through:

- validating macOS + interactive TTY execution
- ensuring Xcode Command Line Tools are installed and healthy (`xcode-select`, `xcrun`, `clang`, `git`)
- cloning the dotfiles repo into `~/dotfiles` (or a custom path)
- installing Homebrew (if missing)
- installing Oh My Zsh (if missing)
- installing zsh plugins (autosuggestions, completions)
- running `brew bundle` against the dotfiles `Brewfile`
- setting up Node LTS via `nvm` and enabling `corepack`
- stowing all top-level non-hidden directories from dotfiles into `~` (including `scripts` and `images`)

Every step is opt-in and prompts for confirmation.

## Requirements

- macOS
- interactive terminal (TTY)
- `curl` (for installer bootstrap and Homebrew/Oh My Zsh install)

`git` is validated through Xcode Command Line Tools during installer preflight.

## Usage

```bash
chmod +x m-config-install.sh
./m-config-install.sh
```

Safe remote execution:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/m-software-engineering/bash-scripts/refs/heads/main/m-config-install.sh)"
```

## Options

```bash
./m-config-install.sh --dotfiles-dir /path/to/dotfiles --repo-url https://github.com/you/dotfiles.git
```

- `--dotfiles-dir <path>`: set target directory for dotfiles.
- `--repo-url <url>`: set remote URL used for cloning.

Environment alternatives:

- `DOTFILES_DIR`
- `DOTFILES_REPO_URL`

## Behavior and safeguards

- Uses `set -euo pipefail` and stops on errors.
- Fails fast if run without a TTY (prevents broken prompt behavior from `curl ... | bash`).
- Performs CLT health checks before clone/Homebrew operations.
- Requests `sudo` for Homebrew install, `brew bundle`, and `xcode-select` repair/switch actions when needed.
- Runs a GNU Stow dry-run before applying changes.
- Optionally moves conflicting files into `~/.dotfiles-backup/<timestamp>/`.

## Notes

- Default repo target is `https://github.com/m-software-engineering/dotfiles.git`.
- If `~/dotfiles` exists but is not a git repo, the script exits with an error.
