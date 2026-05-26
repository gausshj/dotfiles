# Manual Install Test

This repository has CI smoke tests, but the interactive installer still needs a human pass before merging larger setup changes.

Run this from the repository root:

```bash
scripts/manual-test-docker.sh --branch your-branch-name
```

If the network needs a proxy:

```bash
scripts/manual-test-docker.sh \
  --branch your-branch-name \
  --proxy http://host.docker.internal:7890
```

The script builds a reusable local Ubuntu image with only the prerequisites needed to fetch the repo: `sudo`, `curl`, `git`, `ca-certificates`, and locale support. It then opens an interactive shell as a normal user named `gausshj`.

The container uses the test environment timezone by default. You can override it explicitly:

```bash
scripts/manual-test-docker.sh \
  --branch your-branch-name \
  --timezone Asia/Shanghai
```

The container prints login details on startup:

```text
user: gausshj
password: gausshj
sudo does not ask for a password in this test container
timezone: inherited from the test environment, or the value passed to --timezone
```

The test container sets `DEBIAN_FRONTEND=noninteractive` and `TZ` so package installs do not stop at the system `tzdata` geographic-area prompt.

Inside the container, use one of these flows:

```bash
# Test the exact working tree mounted from your machine.
test-local

# Test the public curl flow for a pushed branch.
test-curl
```

The container prints these commands automatically on shell startup. Run `dotfiles-test-help` to show them again.

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
