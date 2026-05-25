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
- running `brew bundle` against the dotfiles `Brewfile`, while skipping known deprecated Homebrew taps and handling the `codex` formula-to-cask migration
- setting up Node LTS via `mise`
- stowing dotfiles packages into `~`, while skipping non-stow data directories such as `browser`
- setting macOS default handlers for Helium, Microsoft Edge, and WezTerm
- installing VSCodium extensions from the dotfiles extension list
- opening browser extension install pages for installed managed Chromium-family browsers

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

## Development

Install the local harness tools with Homebrew:

```bash
brew bundle
```

Run the full verification suite:

```bash
make check
```

Useful focused targets:

```bash
make syntax       # bash -n over shell and Bats files
make format-check # shfmt diff check
make format       # rewrite shell formatting with shfmt
make lint         # ShellCheck static analysis
make test         # Bats test suite
```

The test suite lives in `test/`, uses Bats, and sources the installer without running `main`. The CI workflow runs the same `make check` target on macOS.

## Behavior and safeguards

- Uses `set -euo pipefail` and stops on errors.
- Fails fast if run without a TTY (prevents broken prompt behavior from `curl ... | bash`).
- Performs CLT health checks before clone/Homebrew operations.
- Requests `sudo` for Homebrew install, `brew bundle`, and `xcode-select` repair/switch actions when needed.
- Runs a GNU Stow dry-run before applying changes.
- Treats `browser` as automation data, not a stow package.
- Optionally moves conflicting files into `~/.dotfiles-backup/<timestamp>/`.
- Skips optional app setup cleanly when required tools or apps are not installed.

## Notes

- Default repo target is `https://github.com/m-software-engineering/dotfiles.git`.
- If `~/dotfiles` exists but is not a git repo, the script exits with an error.
- Browser extension setup opens Chrome Web Store URLs from `browser/extensions-urls.txt`; each Chromium-family browser still requires manual extension confirmation.
