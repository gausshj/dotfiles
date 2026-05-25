# Install Design Notes

This is the proposed direction for the next installer iteration. It is intentionally separate from `bootstrap.sh` until the scope is agreed.

## Baseline

Mainstream dotfiles tools tend to split into a few models:

- GNU Stow: simple package directories and symlinks into a target directory.
- chezmoi: source-state driven dotfiles with templates, scripts, and per-machine data.
- yadm: Git-backed dotfiles with bootstrap hooks and alternate files.
- Dotbot: declarative install files with link, clean, shell, and create tasks.
- Home Manager: Nix-based user environments, strongest when the machine already uses Nix.

For this repository, keeping the current shell installer is still reasonable because the setup needs interactive choices, public one-line install, VPS-friendly defaults, and personal machine options.

## Proposed Model

Add a small manifest first, then let the installer read it:

```text
modules/
  core.toml
  zsh.toml
  tmux.toml
  tmux-status.toml
  nvim.toml
  git-auth.toml
```

Each module should declare:

- `id`: stable module name.
- `description`: text shown in the installer.
- `packages`: apt and Homebrew packages.
- `deploy`: repo paths that can be linked or copied.
- `post_install`: optional bounded commands such as `PlugInstall`.
- `scope`: `user`, `global`, or both.
- `default`: whether QuickStart selects it.

This gives us the OpenClaw-style flow without hard-coding every option directly inside `bootstrap.sh`.

## User vs Global Install

Keep user install as the default.

For global install, avoid writing arbitrary dotfiles into every existing home directory by default. Safer options:

- Install shared files under a configurable prefix such as `/usr/local/share/gauss-dotfiles` or `/opt/gauss-dotfiles`.
- Optionally install `/etc/skel` defaults for future users.
- Optionally patch one selected existing user only.
- Require explicit confirmation before touching `/etc`, `/usr/local`, or another user's home.

The installer can expose:

```bash
DOTFILES_SCOPE=user
DOTFILES_PREFIX=/usr/local/share/gauss-dotfiles
DOTFILES_TARGET_HOME="$HOME"
```

Interactive mode should ask for scope first, then module groups, then deploy mode.

## Partial tmux Updates

For machines like `local_labpc`, do not replace the whole tmux config.

Use a small snippet model:

```text
tmux/.config/tmux/scripts/status_info.sh
tmux/.config/tmux/snippets/status.tmux
tmux/.config/tmux/snippets/keybindings.tmux
tmux/.config/tmux/snippets/style.tmux
```

The installer can install only the selected snippet and either:

- print the exact `source-file` line for manual use, or
- append a guarded block to the existing `~/.tmux.conf` after making a backup.

Guarded block example:

```tmux
# >>> gauss dotfiles: tmux-status
source-file ~/.config/tmux/snippets/status.tmux
# <<< gauss dotfiles: tmux-status
```

## Status Bar Design

The status script should be cross-platform and degrade quietly:

- Linux: CPU, memory, disk, date/time, host, and GPU when `nvidia-smi` exists.
- macOS: CPU, memory, disk, date/time, host; omit GPU unless a reliable command exists.
- Optional tools such as `ifstat` should enrich the output but never be required.
- iTerm users can still use terminal-native status UI; tmux should stay readable over SSH and inside plain terminals.

The status bar should be a separate module so it can be installed on `local_labpc` without installing nvim, zsh, or the full tmux config.
