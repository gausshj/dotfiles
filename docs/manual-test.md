# Manual Install Test

This repository has CI smoke tests, but the interactive installer still needs a human pass before merging larger setup changes.

Run this from the repository root:

```bash
scripts/manual-test-docker.sh --branch codex/nvim-status-manual-tests
```

If the network needs a proxy:

```bash
scripts/manual-test-docker.sh \
  --branch codex/nvim-status-manual-tests \
  --proxy http://host.docker.internal:7890
```

The script builds a reusable local Ubuntu image with only the prerequisites needed to fetch the repo: `sudo`, `curl`, `git`, `ca-certificates`, and locale support. It then opens an interactive shell as a normal user named `gauss`.

Inside the container, use one of these flows:

```bash
# Test the exact working tree mounted from your machine.
cd /workspace/dotfiles && ./bootstrap.sh

# Test the public curl flow for a pushed branch.
curl -fsSL https://github.com/gausshj/dotfiles/raw/${DOTFILES_BRANCH}/install.sh | bash
```

Useful checks after install:

```bash
zsh --version
tmux -f ~/.tmux.conf new-session -d -s smoke
tmux capture-pane -pt smoke
tmux kill-session -t smoke
nvim --headless '+qall'
ls -l ~/.zshrc ~/.p10k.zsh ~/.tmux.conf ~/.config/nvim
```

The container is intentionally not started with `--rm`. If something fails, inspect it with:

```bash
docker start -ai dotfiles-manual
```

Remove it when finished:

```bash
docker rm -f dotfiles-manual
```
