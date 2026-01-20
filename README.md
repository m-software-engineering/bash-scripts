# bash-scripts

Small collection of utility bash scripts. Currently this repo includes a guided installer to bootstrap a dotfiles setup on macOS.

## Contents

- `m-config-install.sh`: interactive setup for the `m-software-engineering/dotfiles` repo.

## What the installer does

`m-config-install.sh` walks you through:

- cloning the dotfiles repo into `~/dotfiles`
- installing Homebrew (if missing)
- installing Oh My Zsh (if missing)
- installing zsh plugins (autosuggestions, completions)
- running `brew bundle` against the dotfiles `Brewfile`
- stowing all non-hidden packages from `~/dotfiles` into `~`

Every step is opt-in and prompts for confirmation.

## Requirements

- macOS (Homebrew and Oh My Zsh are macOS-focused here)
- `git`
- `curl` (for Homebrew/Oh My Zsh installers)
- `stow` (optional; only needed for the stow step)

## Usage

```bash
chmod +x m-config-install.sh
./m-config-install.sh
```

## Behavior and safeguards

- Uses `set -euo pipefail` and stops on errors.
- Requests `sudo` only for Homebrew install or `brew bundle` steps.
- Runs a GNU Stow dry-run before applying changes.
- Optionally moves conflicting files into `~/.dotfiles-backup/<timestamp>/`.

## Notes

- The script targets `https://github.com/m-software-engineering/dotfiles.git`.
- If `~/dotfiles` exists but is not a git repo, the script exits with an error.
