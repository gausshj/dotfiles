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

install_stow() {
    step "Installing GNU Stow..."
    if command -v stow >/dev/null 2>&1; then
        info "stow already installed"
    elif [[ "$OS_TYPE" == "macos" ]]; then
        if ! command -v brew >/dev/null 2>&1; then
            warn "Homebrew not found - installing Homebrew first..."
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        fi
        brew install stow
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y stow
        elif command -v pacman >/dev/null 2>&1; then
            sudo pacman -S --noconfirm stow
        elif command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y stow
        else
            warn "Cannot determine package manager - please install stow manually"
            exit 1
        fi
    fi
}

install_system_packages() {
    install_stow

    step "Installing system packages..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        if [[ -f "$DOTFILES/Brewfile" ]]; then
            info "Running brew bundle..."
            brew bundle --file="$DOTFILES/Brewfile"
        fi
    elif [[ "$OS_TYPE" == "linux" ]]; then
        if command -v apt >/dev/null 2>&1; then
            sudo apt update
            sudo apt install -y zsh tmux fzf ripgrep fd-find bat

            mkdir -p "$HOME/.local/bin"
            if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
                ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
            fi
            if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
                ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
            fi
        fi
    fi
}

install_zsh_stack() {
    step "Installing oh-my-zsh..."
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        info "oh-my-zsh already installed"
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    step "Installing powerlevel10k..."
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$P10K_DIR" ]]; then
        info "powerlevel10k already installed"
    elif [[ -d "$HOME/.oh-my-zsh" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR"
    fi

    step "Installing zsh plugins..."
    PLUGIN_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    mkdir -p "$PLUGIN_DIR"

    if [[ ! -d "$PLUGIN_DIR/zsh-autosuggestions" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions.git "$PLUGIN_DIR/zsh-autosuggestions"
    else
        info "zsh-autosuggestions already installed"
    fi

    if [[ ! -d "$PLUGIN_DIR/zsh-syntax-highlighting" ]]; then
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGIN_DIR/zsh-syntax-highlighting"
    else
        info "zsh-syntax-highlighting already installed"
    fi

    if [[ ! -d "$PLUGIN_DIR/zsh-z" ]]; then
        git clone --depth=1 https://github.com/agkozak/zsh-z.git "$PLUGIN_DIR/zsh-z"
    else
        info "zsh-z already installed"
    fi
}

install_tpm() {
    step "Installing TPM..."
    TPM_DIR="$HOME/.tmux/plugins/tpm"
    if [[ -d "$TPM_DIR" ]]; then
        info "TPM already installed"
    else
        git clone --depth=1 https://github.com/tmux-plugins/tpm.git "$TPM_DIR"
    fi
}

backup_root() {
    if [[ -z "${DOTFILES_BACKUP_DIR:-}" ]]; then
        DOTFILES_BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    fi
    printf '%s' "$DOTFILES_BACKUP_DIR"
}

is_dotfiles_link() {
    local target="$1"
    local link_dest resolved_target

    [[ -L "$target" ]] || return 1
    link_dest="$(readlink "$target")"
    if [[ "$link_dest" != /* ]]; then
        link_dest="$(cd "$(dirname "$target")" && cd "$(dirname "$link_dest")" && pwd -P)/$(basename "$link_dest")"
    fi
    resolved_target="$(cd "$(dirname "$link_dest")" 2>/dev/null && pwd -P)/$(basename "$link_dest")"
    [[ "$resolved_target" == "$DOTFILES/"* ]]
}

backup_stow_conflicts() {
    local pkg="$1"
    local source rel target backup_dir backup_path

    while IFS= read -r source; do
        rel="${source#"$DOTFILES/$pkg/"}"
        target="$HOME/$rel"

        [[ -e "$target" || -L "$target" ]] || continue
        is_dotfiles_link "$target" && continue

        backup_dir="$(backup_root)"
        backup_path="$backup_dir/$rel"
        mkdir -p "$(dirname "$backup_path")"
        warn "Backing up existing $target to $backup_path"
        mv "$target" "$backup_path"
    done < <(find "$DOTFILES/$pkg" -type f)
}

stow_package() {
    local pkg="$1"

    if [[ ! -d "$DOTFILES/$pkg" ]]; then
        warn "Package not found: $pkg"
        return
    fi

    if ! command -v stow >/dev/null 2>&1; then
        warn "stow is not installed; skipping $pkg"
        return
    fi

    info "Stowing $pkg..."
    backup_stow_conflicts "$pkg"
    stow -v -R -t "$HOME" "$pkg"
}

stow_dotfiles() {
    step "Stowing dotfiles..."
    cd "$DOTFILES"

    enabled STOW_ZSH && stow_package zsh
    enabled STOW_TMUX && stow_package tmux
    enabled STOW_GIT && stow_package git
    enabled STOW_NVIM && stow_package nvim
    return 0
}

copy_templates() {
    step "Setting up local config templates..."
    for tmpl in "$DOTFILES/templates/"*; do
        [[ -f "$tmpl" ]] || continue
        dest="$HOME/.$(basename "$tmpl")"
        if [[ ! -f "$dest" ]]; then
            cp "$tmpl" "$dest"
            info "Created $dest"
        else
            info "$dest already exists, skipping"
        fi
    done
}

configure_git() {
    if tty_available && [[ -x "$DOTFILES/scripts/configure-git.sh" ]]; then
        step "Configuring personal Git/GPG/GitHub auth..."
        "$DOTFILES/scripts/configure-git.sh"
    else
        warn "Cannot run Git/GPG/GitHub setup without an interactive terminal."
    fi
}

change_default_shell() {
    step "Setting default shell to zsh..."
    ZSH_PATH="$(command -v zsh || true)"
    if [[ -z "$ZSH_PATH" ]]; then
        warn "zsh not found; skipping default shell change"
        return
    fi

    if [[ "${SHELL:-}" != "$ZSH_PATH" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            if sudo dscl . -create "/Users/$USER" UserShell "$ZSH_PATH" 2>/dev/null; then
                info "Default shell changed to $ZSH_PATH (new terminal sessions will use zsh)"
            else
                warn "Could not change shell via dscl - run: chsh -s $ZSH_PATH"
            fi
        else
            if chsh -s "$ZSH_PATH"; then
                info "Default shell changed to $ZSH_PATH (new terminal sessions will use zsh)"
            else
                warn "Could not change shell - run: chsh -s $ZSH_PATH"
            fi
        fi
    else
        info "Default shell already set to $ZSH_PATH"
    fi
}

install_tmux_plugins() {
    step "Installing tmux plugins..."
    TPM_DIR="$HOME/.tmux/plugins/tpm"
    if [[ -x "$TPM_DIR/bin/install_plugins" && -x "$(command -v tmux 2>/dev/null || true)" ]]; then
        "$TPM_DIR/bin/install_plugins" || true
        info "tmux plugins installed"
    else
        warn "tmux or TPM not found - install TPM first, then press prefix+I in tmux"
    fi
}

# ------------------------------------------------------------------
# Platform detection
# ------------------------------------------------------------------
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

# ------------------------------------------------------------------
# Find dotfiles directory
# ------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES="$SCRIPT_DIR"
info "Dotfiles directory: $DOTFILES"

# ------------------------------------------------------------------
# Default setup selection
# ------------------------------------------------------------------
INSTALL_PACKAGES=1
INSTALL_ZSH_STACK=1
INSTALL_TMUX_STACK=1
STOW_ZSH=1
STOW_TMUX=1
STOW_GIT=1
STOW_NVIM=0
COPY_TEMPLATES=1
CONFIGURE_GIT="${DOTFILES_CONFIGURE_GIT:-0}"
CHANGE_SHELL=1
INSTALL_TMUX_PLUGINS=1

if [[ "$OS_TYPE" == "linux" ]]; then
    STOW_NVIM=1
fi

if [[ "${DOTFILES_NO_PROMPT:-0}" != "1" ]] && tty_available; then
    CHECKBOX_VARS=(
        INSTALL_PACKAGES
        INSTALL_ZSH_STACK
        INSTALL_TMUX_STACK
        STOW_ZSH
        STOW_TMUX
        STOW_GIT
        STOW_NVIM
        COPY_TEMPLATES
        CONFIGURE_GIT
        CHANGE_SHELL
        INSTALL_TMUX_PLUGINS
    )
    CHECKBOX_LABELS=(
        "Install system packages"
        "Install oh-my-zsh, powerlevel10k, zsh plugins"
        "Install tmux plugin manager"
        "Stow zsh config"
        "Stow tmux config"
        "Stow shared git config"
        "Stow nvim config"
        "Create local template files"
        "Configure personal Git/GPG/GitHub auth"
        "Set default shell to zsh"
        "Install tmux plugins"
    )
    CHECKBOX_CANCELLED=0
    prompt_checkbox_menu "Dotfiles setup"
    if [[ "$CHECKBOX_CANCELLED" == "1" ]]; then
        info "Setup cancelled."
        exit 0
    fi
else
    info "Non-interactive mode: using default setup selection."
fi

# ------------------------------------------------------------------
# Execute selected steps
# ------------------------------------------------------------------
enabled INSTALL_PACKAGES && install_system_packages
enabled INSTALL_ZSH_STACK && install_zsh_stack
enabled INSTALL_TMUX_STACK && install_tpm
stow_dotfiles
enabled COPY_TEMPLATES && copy_templates
enabled CONFIGURE_GIT && configure_git
enabled CHANGE_SHELL && change_default_shell
enabled INSTALL_TMUX_PLUGINS && install_tmux_plugins

# ------------------------------------------------------------------
# Final instructions
# ------------------------------------------------------------------
echo ""
echo "════════════════════════════════════════════════"
echo -e "${GREEN}  Dotfiles setup complete!${NC}"
echo ""
echo -e "  Optional follow-up:"
echo -e "  - Personal Git/GPG/GitHub auth: ${YELLOW}scripts/configure-git.sh${NC}"
echo -e "  - Local overrides: ${YELLOW}~/.zshrc.local${NC}"
echo -e "  - Machine credentials: ${YELLOW}~/.zshrc.secrets${NC}"
echo -e "  - Restart terminal or run: ${YELLOW}exec zsh${NC}"
echo "════════════════════════════════════════════════"
