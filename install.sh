#!/usr/bin/env bash
# One-line installer script - curl-friendly entry point for dotfiles.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gausshj/dotfiles/main/install.sh | bash
#
# Or locally:
#   ./install.sh

set -euo pipefail

REPO_URL="${DOTFILES_REPO_URL:-https://github.com/gausshj/dotfiles.git}"
DOTFILES_DIR="$HOME/.dotfiles"

echo "==> Installing dotfiles from $REPO_URL"

if [[ -d "$DOTFILES_DIR" ]]; then
    echo "==> Dotfiles directory exists — pulling latest changes..."
    cd "$DOTFILES_DIR"
    git pull --rebase
else
    echo "==> Cloning dotfiles..."
    git clone "$REPO_URL" "$DOTFILES_DIR"
    cd "$DOTFILES_DIR"
fi

echo "==> Running bootstrap..."
chmod +x bootstrap.sh
./bootstrap.sh
