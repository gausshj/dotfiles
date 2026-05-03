#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
step() { echo -e "${CYAN}[STEP]${NC} $*"; }

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

select_all() {
    UNSTOW_ZSH=1
    UNSTOW_TMUX=1
    UNSTOW_GIT=1
    UNSTOW_NVIM=1
    REMOVE_LOCAL_TEMPLATES=1
    REMOVE_TMUX_PLUGINS=1
    REMOVE_ZSH_STACK=1
    RESTORE_SHELL=1
}

select_none() {
    UNSTOW_ZSH=0
    UNSTOW_TMUX=0
    UNSTOW_GIT=0
    UNSTOW_NVIM=0
    REMOVE_LOCAL_TEMPLATES=0
    REMOVE_TMUX_PLUGINS=0
    REMOVE_ZSH_STACK=0
    RESTORE_SHELL=0
}

show_menu() {
    echo ""
    echo "Select uninstall steps. Type numbers to toggle, then press Enter to continue."
    echo "Use comma or spaces between numbers. 'a' selects all, 'n' selects none."
    echo ""
    printf "  1) %s Unstow zsh config\n" "$(mark UNSTOW_ZSH)"
    printf "  2) %s Unstow tmux config\n" "$(mark UNSTOW_TMUX)"
    printf "  3) %s Unstow shared git config\n" "$(mark UNSTOW_GIT)"
    printf "  4) %s Unstow nvim config\n" "$(mark UNSTOW_NVIM)"
    printf "  5) %s Remove local template files\n" "$(mark REMOVE_LOCAL_TEMPLATES)"
    printf "  6) %s Remove tmux plugins\n" "$(mark REMOVE_TMUX_PLUGINS)"
    printf "  7) %s Remove oh-my-zsh, p10k, zsh plugins\n" "$(mark REMOVE_ZSH_STACK)"
    printf "  8) %s Restore default shell to bash\n" "$(mark RESTORE_SHELL)"
    echo ""
}

prompt_selection() {
    local input item

    while true; do
        show_menu
        read -r -p "Toggle choices, or press Enter to continue: " input
        [[ -z "$input" ]] && break

        input="${input//,/ }"
        for item in $input; do
            case "$item" in
                1) toggle UNSTOW_ZSH ;;
                2) toggle UNSTOW_TMUX ;;
                3) toggle UNSTOW_GIT ;;
                4) toggle UNSTOW_NVIM ;;
                5) toggle REMOVE_LOCAL_TEMPLATES ;;
                6) toggle REMOVE_TMUX_PLUGINS ;;
                7) toggle REMOVE_ZSH_STACK ;;
                8) toggle RESTORE_SHELL ;;
                a|A) select_all ;;
                n|N) select_none ;;
                *)
                    warn "Unknown choice: $item"
                    ;;
            esac
        done
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

if [[ "${DOTFILES_NO_PROMPT:-0}" != "1" && -t 0 ]]; then
    prompt_selection
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
