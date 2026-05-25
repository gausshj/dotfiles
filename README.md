# Dotfiles

> My personal dotfiles for zsh, tmux, nvim, and more. One-command setup across macOS and Linux via `stow` symlinks or copied files.

## Quick Install

```bash
# Clone and bootstrap
git clone https://github.com/gausshj/dotfiles.git ~/.dotfiles
cd ~/.dotfiles
./bootstrap.sh

# Or one-liner for the public repo
curl -fsSL https://raw.githubusercontent.com/gausshj/dotfiles/main/install.sh | bash
```

## What's Included

| Package | Description |
|---------|-------------|
| `zsh/` | `.zshrc`, `.p10k.zsh` — OMZ + powerlevel10k + plugins |
| `tmux/` | `.tmux.conf` + fzf pane switcher |
| `nvim/` | `.config/nvim/init.vim` — gruvbox, LSP, treesitter, telescope |
| `git/` | shared `.gitconfig`; identity/signing live in `~/.gitconfig.local` |
| `packages/` | package manifests used by `bootstrap.sh` |
| `Brewfile` | macOS-only: manual `brew bundle` alternative |
| `scripts/` | optional local setup and manual test helpers |

## Structure

```
.
├── bootstrap.sh          # Main installer (run locally)
├── uninstall.sh          # Interactive uninstaller
├── install.sh           # One-liner entry point for curl
├── Brewfile             # macOS Homebrew packages
├── packages/            # Package manifests used by bootstrap.sh
├── scripts/
│   ├── configure-git.sh      # Optional personal Git/GPG/GitHub setup
│   └── manual-test-docker.sh # Human install test container
├── zsh/
│   ├── .zshrc           # Main zsh config
│   └── .p10k.zsh        # powerlevel10k theme
├── tmux/
│   ├── .tmux.conf       # Main tmux config (macOS + Linux unified)
│   └── .config/tmux/scripts/
│       ├── pane_switcher.sh
│       └── status_info.sh
├── nvim/.config/nvim/
│   └── init.vim         # Neovim/Vim init (Linux primary)
├── git/
│   └── .gitconfig
└── templates/           # Machine-specific overrides (gitignored)
    ├── zshrc.secrets
    ├── zshrc.local
    └── gitconfig.local
```

## Setup on a New Machine

```bash
# 1. Clone this repo
git clone https://github.com/gausshj/dotfiles.git ~/.dotfiles

# 2. Bootstrap
cd ~/.dotfiles
./bootstrap.sh

# 3. Restart terminal
exec zsh
```

`bootstrap.sh` shows a checkbox-style setup menu when run in an interactive terminal. Use Up/Down to move, Space to toggle items, and Enter to run the selected steps. The personal Git/GPG/GitHub auth option is off by default, which keeps VPS installs free of local identity and GitHub token setup.

By default, configs are deployed with `stow` symlinks. Uncheck `Use symlinks via stow` to copy files into `$HOME` instead. If an existing dotfile would conflict, `bootstrap.sh` backs it up under `~/.dotfiles-backup/<timestamp>/` before deploying the repo version.

System packages are listed in plain text under `packages/`:

| File | Used for |
|------|----------|
| `packages/linux-apt.txt` | Ubuntu/Debian apt packages |
| `packages/macos-taps.txt` | Homebrew taps |
| `packages/macos-brews.txt` | Homebrew formulae |
| `packages/macos-casks.txt` | Homebrew casks |

The checked-in `zsh/.p10k.zsh` file is deployed as the default prompt configuration.

On a personal development machine, optionally configure Git identity, commit signing, and `GH_TOKEN`:

```bash
cd ~/.dotfiles
./scripts/configure-git.sh
```

Or include it during bootstrap:

```bash
DOTFILES_CONFIGURE_GIT=1 ./bootstrap.sh
```

For non-interactive installs, the default selection is used:

```bash
DOTFILES_NO_PROMPT=1 ./bootstrap.sh
```

Non-interactive defaults can be overridden with `DOTFILES_*` flags, for example:

```bash
DOTFILES_NO_PROMPT=1 DOTFILES_USE_SYMLINKS=0 DOTFILES_CHANGE_SHELL=0 ./bootstrap.sh
```

`install.sh` also accepts a branch for testing PRs before merge:

```bash
DOTFILES_BRANCH=codex/nvim-status-manual-tests \
  curl -fsSL https://github.com/gausshj/dotfiles/raw/codex/nvim-status-manual-tests/install.sh | bash
```

## macOS Only

```bash
brew bundle --file=~/.dotfiles/Brewfile
```

## Linux Only (nvim)

```bash
stow -t ~ nvim
```

`bootstrap.sh` installs `vim-plug` for Neovim, installs/updates pinned plugins, and removes plugins that are no longer listed when the nvim config is selected. To retry plugin installation manually:

```bash
nvim '+PlugInstall --sync' '+PlugUpdate --sync' '+PlugClean!' +qall
```

Disable this step during automated runs with:

```bash
DOTFILES_INSTALL_NVIM_PLUGINS=0 ./bootstrap.sh
```

## Manual Install Test

For a human pass through the interactive installer:

```bash
scripts/manual-test-docker.sh --branch codex/nvim-status-manual-tests
```

See `docs/manual-test.md` for proxy usage and post-install checks.

## Updating

```bash
cd ~/.dotfiles && git pull && ./bootstrap.sh
```

## Cross-Platform Design

- `.tmux.conf` uses `if-shell` to detect Darwin vs Linux for shell/path differences
- `.zshrc` respects Homebrew only on macOS (`if command -v brew`)
- Machine-specific values go in `~/.zshrc.secrets`, `~/.zshrc.local`, and `~/.gitconfig.local`
- `stow` creates symlinks so changes in `~/.dotfiles` are reflected everywhere; copied-file mode is available for machines where symlinks are not desired

## Privacy Model

This repository is intended to be public. Do not commit real identities, API keys, database credentials, proxy credentials, private machine paths, SSH keys, or GPG private material.

The shared `git/.gitconfig` includes only common behavior. `scripts/configure-git.sh` prompts for `user.name`, `user.email`, optional GPG signing, and optional `GH_TOKEN`, then writes them to local-only files under `$HOME`.

## Manual TPM (tmux plugin) Installation

If tmux is already running:

```
Ctrl-b + I   # install plugins (prefix+I)
```

## Uninstall

```bash
cd ~/.dotfiles
./uninstall.sh
```

The uninstaller also uses the same Up/Down, Space, Enter checkbox menu. By default it removes deployed config links and copied files that still exactly match the repo version. Removing local template files, tmux plugins, oh-my-zsh, or changing the default shell back to bash must be explicitly selected.
