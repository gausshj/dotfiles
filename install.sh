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
REPO_BRANCH="${DOTFILES_BRANCH:-}"
DOTFILES_DIR="$HOME/.dotfiles"

echo "==> Installing dotfiles from $REPO_URL"
if [[ -n "$REPO_BRANCH" ]]; then
    echo "==> Requested branch: $REPO_BRANCH"
fi

if [[ -d "$DOTFILES_DIR" ]]; then
    echo "==> Dotfiles directory exists — pulling latest changes..."
    cd "$DOTFILES_DIR"
    if [[ -n "$REPO_BRANCH" ]]; then
        git fetch origin "$REPO_BRANCH"
        git checkout "$REPO_BRANCH" 2>/dev/null || git checkout -b "$REPO_BRANCH" FETCH_HEAD
        git pull --rebase --autostash origin "$REPO_BRANCH" || echo "==> Warning: update failed; continuing with the existing checkout."
    else
        git pull --rebase --autostash || echo "==> Warning: update failed; continuing with the existing checkout."
    fi
else
    echo "==> Cloning dotfiles..."
    if [[ -n "$REPO_BRANCH" ]]; then
        git clone --branch "$REPO_BRANCH" --single-branch "$REPO_URL" "$DOTFILES_DIR"
    else
        git clone "$REPO_URL" "$DOTFILES_DIR"
    fi
    cd "$DOTFILES_DIR"
fi

echo "==> Running bootstrap..."
chmod +x bootstrap.sh
./bootstrap.sh
