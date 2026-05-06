#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
REVERSE='\033[7m'
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
        printf '●'
    else
        printf '○'
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

is_dotfiles_managed_path() {
    local target="$1"
    local link_dest resolved_target resolved_dir resolved_path

    [[ -e "$target" || -L "$target" ]] || return 1

    if [[ -L "$target" ]]; then
        link_dest="$(readlink "$target")"
        if [[ "$link_dest" != /* ]]; then
            link_dest="$(cd "$(dirname "$target")" && cd "$(dirname "$link_dest")" && pwd -P)/$(basename "$link_dest")"
        fi
        resolved_target="$(cd "$(dirname "$link_dest")" 2>/dev/null && pwd -P)/$(basename "$link_dest")"
        [[ "$resolved_target" == "$DOTFILES/"* ]] && return 0
    fi

    resolved_dir="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || return 1
    resolved_path="$resolved_dir/$(basename "$target")"
    [[ "$resolved_path" == "$DOTFILES/"* ]]
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
    local i var marker row
    local width=76
    local inner_width=72

    printf '\033[H'
    printf '%b╭─ %-*.*s─╮%b\n' "$CYAN" "$inner_width" "$inner_width" "$title" "$NC"
    printf '%b│%b %-*.*s %b│%b\n' "$CYAN" "$DIM" "$inner_width" "$inner_width" "Up/Down or j/k to move · Space toggles · Enter runs" "$CYAN" "$NC"
    printf '%b│%b %-*.*s %b│%b\n' "$CYAN" "$DIM" "$inner_width" "$inner_width" "Shortcuts: a select all · n select none · q cancel" "$CYAN" "$NC"
    printf '%b├%*s┤%b\n' "$CYAN" "$width" "" "$NC" | sed 's/ /─/g'

    for i in "${!CHECKBOX_VARS[@]}"; do
        var="${CHECKBOX_VARS[$i]}"
        marker="$(mark "$var")"
        row="  $marker  ${CHECKBOX_LABELS[$i]}"
        if [[ "$i" -eq "$cursor" ]]; then
            printf '%b│%b%s %-*.*s%b%b│%b\n' "$CYAN" "$REVERSE" "›" $((inner_width - 1)) $((inner_width - 1)) "$row" "$NC" "$CYAN" "$NC"
        else
            printf '%b│%b %b%-*.*s%b │%b\n' "$CYAN" "$NC" "$DIM" "$inner_width" "$inner_width" "$row" "$CYAN" "$NC"
        fi
    done
    printf '%b╰%*s╯%b\n' "$CYAN" "$width" "" "$NC" | sed 's/ /─/g'
    printf '\033[J'
}

prompt_checkbox_menu() {
    local title="$1"
    local cursor=0
    local count key rest current

    printf '\033[?1049h\033[?25l\033[H\033[J'
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
    printf '\033[?25h\033[?1049l'
}

remove_package_copies() {
    local pkg="$1"
    local source rel target

    if [[ ! -d "$DOTFILES/$pkg" ]]; then
        warn "Package not found: $pkg"
        return
    fi

    while IFS= read -r source; do
        rel="${source#"$DOTFILES/$pkg/"}"
        target="$HOME/$rel"

        [[ -f "$target" && ! -L "$target" ]] || continue
        is_dotfiles_managed_path "$target" && continue
        if cmp -s "$source" "$target"; then
            rm -f "$target"
            info "Removed copied $target"
        else
            warn "$target was modified, skipping"
        fi
    done < <(find "$DOTFILES/$pkg" -type f)
}

remove_deployed_package() {
    local pkg="$1"

    if [[ ! -d "$DOTFILES/$pkg" ]]; then
        warn "Package not found: $pkg"
        return
    fi

    remove_package_copies "$pkg"

    if command -v stow >/dev/null 2>&1; then
        info "Removing stow links for $pkg..."
        stow -v -D -t "$HOME" "$pkg" 2>&1 || true
    else
        warn "stow is not installed; skipped link removal for $pkg"
    fi
}

remove_deployed_dotfiles() {
    step "Removing deployed dotfiles..."
    cd "$DOTFILES"

    enabled REMOVE_ZSH_CONFIG && remove_deployed_package zsh
    enabled REMOVE_TMUX_CONFIG && remove_deployed_package tmux
    enabled REMOVE_GIT_CONFIG && remove_deployed_package git
    enabled REMOVE_NVIM_CONFIG && remove_deployed_package nvim
    return 0
}

remove_template_file() {
    local template="$1"
    local path="$2"

    if [[ ! -e "$path" ]]; then
        info "$path does not exist, skipping"
        return
    fi

    if [[ -L "$path" ]]; then
        warn "$path is a symlink, skipping"
        return
    fi

    if cmp -s "$template" "$path"; then
        rm -f "$path"
        info "Removed $path"
    else
        warn "$path was modified, skipping"
    fi
}

remove_local_templates() {
    step "Removing local template files..."
    remove_template_file "$DOTFILES/templates/zshrc.local" "$HOME/.zshrc.local"
    remove_template_file "$DOTFILES/templates/zshrc.secrets" "$HOME/.zshrc.secrets"
    remove_template_file "$DOTFILES/templates/gitconfig.local" "$HOME/.gitconfig.local"
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

REMOVE_ZSH_CONFIG=1
REMOVE_TMUX_CONFIG=1
REMOVE_GIT_CONFIG=1
REMOVE_NVIM_CONFIG=1
REMOVE_LOCAL_TEMPLATES=0
REMOVE_TMUX_PLUGINS=0
REMOVE_ZSH_STACK=0
RESTORE_SHELL=0

if [[ "${DOTFILES_NO_PROMPT:-0}" != "1" ]] && tty_available; then
    CHECKBOX_VARS=(
        REMOVE_ZSH_CONFIG
        REMOVE_TMUX_CONFIG
        REMOVE_GIT_CONFIG
        REMOVE_NVIM_CONFIG
        REMOVE_LOCAL_TEMPLATES
        REMOVE_TMUX_PLUGINS
        REMOVE_ZSH_STACK
        RESTORE_SHELL
    )
    CHECKBOX_LABELS=(
        "Remove zsh config links/copies"
        "Remove tmux config links/copies"
        "Remove shared git config links/copies"
        "Remove nvim config links/copies"
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

remove_deployed_dotfiles
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
