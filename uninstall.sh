#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
step() { echo -e "${CYAN}[STEP]${NC} $*"; }

tty_available() {
    [[ -t 0 || -r /dev/tty ]]
}

read_key() {
    local __var="$1"
    if [[ -t 0 ]]; then
        IFS= read -rsn1 "$__var"
    else
        IFS= read -rsn1 "$__var" </dev/tty
    fi
}

read_key_rest() {
    local __var="$1"
    if [[ -t 0 ]]; then
        IFS= read -rsn2 "$__var"
    else
        IFS= read -rsn2 "$__var" </dev/tty
    fi
}

enabled() {
    local value
    eval "value=\${$1}"
    [[ "$value" == "1" ]]
}

mark() {
    if enabled "$1"; then
        printf '[x]'
    else
        printf '[ ]'
    fi
}

set_enabled() {
    eval "$1=$2"
}

toggle() {
    local name="$1"
    local value
    eval "value=\${$name}"
    if [[ "$value" == "1" ]]; then
        eval "$name=0"
    else
        eval "$name=1"
    fi
}

checkbox_set_all() {
    local value="$1"
    local var

    for var in "${CHECKBOX_VARS[@]}"; do
        set_enabled "$var" "$value"
    done
}

render_checkbox_menu() {
    local title="$1"
    local cursor="$2"
    local i var prefix marker

    printf '\033[H\033[2J'
    printf '%s\n\n' "$title"
    printf 'Use Up/Down to move, Space to toggle, Enter to continue.\n'
    printf 'Shortcuts: a = all, n = none, q = cancel.\n\n'

    for i in "${!CHECKBOX_VARS[@]}"; do
        var="${CHECKBOX_VARS[$i]}"
        if [[ "$i" -eq "$cursor" ]]; then
            prefix=">"
        else
            prefix=" "
        fi
        marker="$(mark "$var")"
        printf ' %s %s %s\n' "$prefix" "$marker" "${CHECKBOX_LABELS[$i]}"
    done
}

prompt_checkbox_menu() {
    local title="$1"
    local cursor=0
    local count key rest current

    while true; do
        count="${#CHECKBOX_VARS[@]}"
        render_checkbox_menu "$title" "$cursor"

        read_key key || break
        case "$key" in
            "")
                printf '\n'
                break
                ;;
            " ")
                current="${CHECKBOX_VARS[$cursor]}"
                toggle "$current"
                ;;
            a|A)
                checkbox_set_all 1
                ;;
            n|N)
                checkbox_set_all 0
                ;;
            q|Q)
                CHECKBOX_CANCELLED=1
                printf '\n'
                break
                ;;
            $'\033')
                read_key_rest rest || true
                case "$rest" in
                    "[A")
                        if [[ "$cursor" -gt 0 ]]; then
                            cursor=$((cursor - 1))
                        else
                            cursor=$((count - 1))
                        fi
                        ;;
                    "[B")
                        if [[ "$cursor" -lt $((count - 1)) ]]; then
                            cursor=$((cursor + 1))
                        else
                            cursor=0
                        fi
                        ;;
                esac
                ;;
            k|K)
                if [[ "$cursor" -gt 0 ]]; then
                    cursor=$((cursor - 1))
                else
                    cursor=$((count - 1))
                fi
                ;;
            j|J)
                if [[ "$cursor" -lt $((count - 1)) ]]; then
                    cursor=$((cursor + 1))
                else
                    cursor=0
                fi
                ;;
        esac
    done
}

unstow_package() {
    local pkg="$1"

    if [[ ! -d "$DOTFILES/$pkg" ]]; then
        warn "Package not found: $pkg"
        return
    fi

    if ! command -v stow >/dev/null 2>&1; then
        warn "stow is not installed; cannot unstow $pkg"
        return
    fi

    info "Unstowing $pkg..."
    stow -v -D -t "$HOME" "$pkg" 2>&1 || true
}

unstow_dotfiles() {
    step "Unstowing dotfiles..."
    cd "$DOTFILES"

    enabled UNSTOW_ZSH && unstow_package zsh
    enabled UNSTOW_TMUX && unstow_package tmux
    enabled UNSTOW_GIT && unstow_package git
    enabled UNSTOW_NVIM && unstow_package nvim
    return 0
}

remove_if_dotfiles_managed() {
    local path="$1"

    if [[ ! -e "$path" ]]; then
        info "$path does not exist, skipping"
        return
    fi

    if [[ -L "$path" ]]; then
        warn "$path is a symlink, skipping"
        return
    fi

    if grep -q "dotfiles" "$path" 2>/dev/null; then
        rm -i "$path"
    else
        warn "$path does not look dotfiles-managed, skipping"
    fi
}

remove_local_templates() {
    step "Removing local template files..."
    remove_if_dotfiles_managed "$HOME/.zshrc.local"
    remove_if_dotfiles_managed "$HOME/.zshrc.secrets"
    remove_if_dotfiles_managed "$HOME/.gitconfig.local"
}

remove_tmux_plugins() {
    step "Removing tmux plugins..."
    if [[ -d "$HOME/.tmux/plugins" ]]; then
        rm -ri "$HOME/.tmux/plugins"
    else
        info "$HOME/.tmux/plugins does not exist, skipping"
    fi
}

remove_zsh_stack() {
    step "Removing oh-my-zsh stack..."
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        rm -ri "$HOME/.oh-my-zsh"
    else
        info "$HOME/.oh-my-zsh does not exist, skipping"
    fi
}

restore_shell() {
    local bash_path

    step "Restoring default shell to bash..."
    bash_path="$(command -v bash || true)"
    if [[ -z "$bash_path" ]]; then
        warn "bash not found; skipping"
        return
    fi

    if [[ "$OS_TYPE" == "macos" ]]; then
        sudo dscl . -create "/Users/$USER" UserShell "$bash_path" 2>/dev/null ||
            warn "Could not change shell via dscl - run: chsh -s $bash_path"
    else
        chsh -s "$bash_path" || warn "Could not change shell - run: chsh -s $bash_path"
    fi
}

OS="$(uname -s)"
case "$OS" in
    Darwin) OS_TYPE="macos" ;;
    Linux) OS_TYPE="linux" ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac
info "Detected OS: $OS_TYPE ($OS)"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$SCRIPT_DIR"
info "Dotfiles directory: $DOTFILES"

UNSTOW_ZSH=1
UNSTOW_TMUX=1
UNSTOW_GIT=1
UNSTOW_NVIM=1
REMOVE_LOCAL_TEMPLATES=0
REMOVE_TMUX_PLUGINS=0
REMOVE_ZSH_STACK=0
RESTORE_SHELL=0

if [[ "${DOTFILES_NO_PROMPT:-0}" != "1" ]] && tty_available; then
    CHECKBOX_VARS=(
        UNSTOW_ZSH
        UNSTOW_TMUX
        UNSTOW_GIT
        UNSTOW_NVIM
        REMOVE_LOCAL_TEMPLATES
        REMOVE_TMUX_PLUGINS
        REMOVE_ZSH_STACK
        RESTORE_SHELL
    )
    CHECKBOX_LABELS=(
        "Unstow zsh config"
        "Unstow tmux config"
        "Unstow shared git config"
        "Unstow nvim config"
        "Remove local template files"
        "Remove tmux plugins"
        "Remove oh-my-zsh, p10k, zsh plugins"
        "Restore default shell to bash"
    )
    CHECKBOX_CANCELLED=0
    prompt_checkbox_menu "Dotfiles uninstall"
    if [[ "$CHECKBOX_CANCELLED" == "1" ]]; then
        info "Uninstall cancelled."
        exit 0
    fi
else
    info "Non-interactive mode: using default uninstall selection."
fi

unstow_dotfiles
enabled REMOVE_LOCAL_TEMPLATES && remove_local_templates
enabled REMOVE_TMUX_PLUGINS && remove_tmux_plugins
enabled REMOVE_ZSH_STACK && remove_zsh_stack
enabled RESTORE_SHELL && restore_shell

echo ""
echo "════════════════════════════════════════════════"
echo -e "${GREEN}  Dotfiles uninstall complete!${NC}"
echo ""
echo -e "  This script does not uninstall Homebrew, apt packages, or this repository."
echo -e "  Start a new shell session to verify the result."
echo "════════════════════════════════════════════════"
