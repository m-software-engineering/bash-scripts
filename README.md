# bash-scripts

Guided macOS installer for the `m-software-engineering/dotfiles` checkout. It asks before each change, skips work that is already done, and keeps going after a step fails.

## Install

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/m-software-engineering/bash-scripts/refs/heads/main/m-config-install.sh)"
```

Custom checkout path:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/m-software-engineering/bash-scripts/refs/heads/main/m-config-install.sh)" bash --target-dir "$HOME/dotfiles"
```

Run it from an interactive terminal. Saying no skips that step. Saying yes and then hitting an install error does not stop the later steps. At the end the installer lists every failed step and exits non-zero. A second run skips clones, packages, Node, Stow links, and a wallpaper that are already in place.

## Check

```bash
make check
```

Syntax, `shfmt`, ShellCheck, and Bats. `make fmt` rewrites the shell style.
