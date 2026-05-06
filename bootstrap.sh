#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
step() { echo -e "${CYAN}[STEP]${NC} $*"; }

run_with_timeout() {
    local seconds="$1"
    shift

    if command -v timeout >/dev/null 2>&1; then
        timeout "$seconds" "$@"
    else
        "$@"
    fi
}

git_clone_shallow() {
    local url="$1"
    local dest="$2"

    run_with_timeout 120 git -c http.lowSpeedLimit=1 -c http.lowSpeedTime=30 clone --depth=1 "$url" "$dest"
}

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
    local i var marker prefix label_color

    printf '%b◆%b  %s\n' "$GREEN" "$NC" "$title"
    printf '%b│%b\n' "$DIM" "$NC"
    printf '%b│%b  %b↑/↓%b or %bj/k%b move · %bSpace%b toggle · %bEnter%b run\n' "$DIM" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    printf '%b│%b  %ba%b all · %bn%b none · %bq%b cancel\n' "$DIM" "$NC" "$GREEN" "$NC" "$GREEN" "$NC" "$GREEN" "$NC"
    printf '%b│%b\n' "$DIM" "$NC"

    for i in "${!CHECKBOX_VARS[@]}"; do
        var="${CHECKBOX_VARS[$i]}"
        if enabled "$var"; then
            marker="${GREEN}●${NC}"
        else
            marker="${DIM}○${NC}"
        fi

        if [[ "$i" -eq "$cursor" ]]; then
            prefix="${GREEN}›${NC}"
            label_color="$NC"
        else
            prefix=" "
            label_color="$DIM"
        fi
        printf '%b│%b  %b %b  %b%s%b\n' "$DIM" "$NC" "$prefix" "$marker" "$label_color" "${CHECKBOX_LABELS[$i]}" "$NC"
    done
    printf '%b│%b\n' "$DIM" "$NC"
    printf '%b◇%b  Press Enter to continue.\n' "$DIM" "$NC"
    printf '\033[J'
}

prompt_checkbox_menu() {
    local title="$1"
    local cursor=0
    local count key rest current menu_lines=0 rendered=0

    printf '\033[?25l'
    while true; do
        count="${#CHECKBOX_VARS[@]}"
        if [[ "$rendered" == "1" ]]; then
            printf '\033[%dA\033[J' "$menu_lines"
        fi
        render_checkbox_menu "$title" "$cursor"
        menu_lines=$((count + 7))
        rendered=1

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
    printf '\033[?25h'
}

package_file_path() {
    printf '%s/packages/%s\n' "$DOTFILES" "$1"
}

read_package_file() {
    local file="$1"

    [[ -f "$file" ]] || return 0
    sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$file"
}

install_homebrew_if_needed() {
    if ! command -v brew >/dev/null 2>&1; then
        warn "Homebrew not found - installing Homebrew first..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi
}

install_macos_packages() {
    local item

    install_homebrew_if_needed

    while IFS= read -r item; do
        info "Tapping $item..."
        brew tap "$item"
    done < <(read_package_file "$(package_file_path macos-taps.txt)")

    while IFS= read -r item; do
        if brew list "$item" >/dev/null 2>&1; then
            info "$item already installed"
        else
            brew install "$item"
        fi
    done < <(read_package_file "$(package_file_path macos-brews.txt)")

    while IFS= read -r item; do
        if brew list --cask "$item" >/dev/null 2>&1; then
            info "$item already installed"
        else
            brew install --cask "$item"
        fi
    done < <(read_package_file "$(package_file_path macos-casks.txt)")
}

install_linux_packages() {
    local package_file packages

    package_file="$(package_file_path linux-apt.txt)"
    if command -v apt >/dev/null 2>&1; then
        packages="$(read_package_file "$package_file" | xargs)"
        if [[ -z "$packages" ]]; then
            warn "No apt packages listed in $package_file"
            return
        fi
        sudo apt update
        sudo apt install -y $packages

        mkdir -p "$HOME/.local/bin"
        if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
            ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        fi
        if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
            ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        fi
    elif command -v pacman >/dev/null 2>&1; then
        warn "pacman package manifest is not configured yet; install packages manually or add packages/arch-pacman.txt support."
    elif command -v dnf >/dev/null 2>&1; then
        warn "dnf package manifest is not configured yet; install packages manually or add packages/fedora-dnf.txt support."
    else
        warn "Cannot determine package manager - skipping system packages"
    fi
}

install_stow() {
    if command -v stow >/dev/null 2>&1; then
        return
    fi

    step "Installing GNU Stow..."
    if [[ "$OS_TYPE" == "macos" ]]; then
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
    step "Installing system packages..."
    if [[ "$OS_TYPE" == "macos" ]]; then
        install_macos_packages
    elif [[ "$OS_TYPE" == "linux" ]]; then
        install_linux_packages
    fi
}

install_oh_my_zsh_official() {
    local installer status

    installer="$(mktemp)"

    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL --connect-timeout 10 --max-time 60 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "$installer"; then
            run_with_timeout 120 env CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh "$installer" --unattended --keep-zshrc
            status=$?
            rm -f "$installer"
            return "$status"
        fi
    fi

    if command -v wget >/dev/null 2>&1; then
        if wget -qO "$installer" --timeout=10 --tries=1 https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh; then
            run_with_timeout 120 env CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh "$installer" --unattended --keep-zshrc
            status=$?
            rm -f "$installer"
            return "$status"
        fi
    fi

    rm -f "$installer"
    return 1
}

install_zsh_stack() {
    step "Installing oh-my-zsh..."
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        info "oh-my-zsh already installed"
    elif install_oh_my_zsh_official; then
        info "oh-my-zsh installed via official installer"
    else
        warn "Official oh-my-zsh installer failed; falling back to bounded git clone"
        rm -rf "$HOME/.oh-my-zsh"
        if git_clone_shallow https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"; then
            info "oh-my-zsh installed via git clone"
        else
            rm -rf "$HOME/.oh-my-zsh"
            warn "Could not install oh-my-zsh; skipping zsh framework setup"
            return
        fi
    fi

    step "Installing powerlevel10k..."
    P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$P10K_DIR" ]]; then
        info "powerlevel10k already installed"
    elif [[ -d "$HOME/.oh-my-zsh" ]]; then
        git_clone_shallow https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" || warn "Could not install powerlevel10k"
    fi

    step "Installing zsh plugins..."
    PLUGIN_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"
    mkdir -p "$PLUGIN_DIR"

    if [[ ! -d "$PLUGIN_DIR/zsh-autosuggestions" ]]; then
        git_clone_shallow https://github.com/zsh-users/zsh-autosuggestions.git "$PLUGIN_DIR/zsh-autosuggestions" || warn "Could not install zsh-autosuggestions"
    else
        info "zsh-autosuggestions already installed"
    fi

    if [[ ! -d "$PLUGIN_DIR/zsh-syntax-highlighting" ]]; then
        git_clone_shallow https://github.com/zsh-users/zsh-syntax-highlighting.git "$PLUGIN_DIR/zsh-syntax-highlighting" || warn "Could not install zsh-syntax-highlighting"
    else
        info "zsh-syntax-highlighting already installed"
    fi

    if [[ ! -d "$PLUGIN_DIR/zsh-z" ]]; then
        git_clone_shallow https://github.com/agkozak/zsh-z.git "$PLUGIN_DIR/zsh-z" || warn "Could not install zsh-z"
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
        git_clone_shallow https://github.com/tmux-plugins/tpm.git "$TPM_DIR" || warn "Could not install TPM"
    fi
}

backup_root() {
    if [[ -z "${DOTFILES_BACKUP_DIR:-}" ]]; then
        DOTFILES_BACKUP_DIR="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
    fi
    printf '%s' "$DOTFILES_BACKUP_DIR"
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

backup_stow_conflicts() {
    local pkg="$1"
    local source rel target backup_dir backup_path

    while IFS= read -r source; do
        rel="${source#"$DOTFILES/$pkg/"}"
        target="$HOME/$rel"

        [[ -e "$target" || -L "$target" ]] || continue
        is_dotfiles_managed_path "$target" && continue

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

copy_package() {
    local pkg="$1"
    local source rel target

    if [[ ! -d "$DOTFILES/$pkg" ]]; then
        warn "Package not found: $pkg"
        return
    fi

    info "Copying $pkg..."
    backup_stow_conflicts "$pkg"
    while IFS= read -r source; do
        rel="${source#"$DOTFILES/$pkg/"}"
        target="$HOME/$rel"
        mkdir -p "$(dirname "$target")"
        cp -p "$source" "$target"
        info "Copied $target"
    done < <(find "$DOTFILES/$pkg" -type f)
}

deploy_package() {
    local pkg="$1"

    if enabled USE_SYMLINKS; then
        stow_package "$pkg"
    else
        copy_package "$pkg"
    fi
}

deploy_dotfiles() {
    if enabled USE_SYMLINKS; then
        step "Stowing dotfiles..."
    else
        step "Copying dotfiles..."
    fi
    cd "$DOTFILES"

    enabled DEPLOY_ZSH && deploy_package zsh
    enabled DEPLOY_TMUX && deploy_package tmux
    enabled DEPLOY_GIT && deploy_package git
    enabled DEPLOY_NVIM && deploy_package nvim
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
        SHELL_CHANGE_STATUS="missing"
        return
    fi

    if [[ "${SHELL:-}" != "$ZSH_PATH" ]]; then
        if [[ "$OS_TYPE" == "macos" ]]; then
            if sudo dscl . -create "/Users/$USER" UserShell "$ZSH_PATH" 2>/dev/null; then
                info "Default shell changed to $ZSH_PATH (new terminal sessions will use zsh)"
                SHELL_CHANGE_STATUS="changed"
            else
                warn "Could not change shell via dscl - run: chsh -s $ZSH_PATH"
                SHELL_CHANGE_STATUS="failed"
            fi
        else
            if chsh -s "$ZSH_PATH"; then
                info "Default shell changed to $ZSH_PATH (new terminal sessions will use zsh)"
                SHELL_CHANGE_STATUS="changed"
            else
                warn "Could not change shell - run: chsh -s $ZSH_PATH"
                SHELL_CHANGE_STATUS="failed"
            fi
        fi
    else
        info "Default shell already set to $ZSH_PATH"
        SHELL_CHANGE_STATUS="already"
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
INSTALL_PACKAGES="${DOTFILES_INSTALL_PACKAGES:-1}"
INSTALL_ZSH_STACK="${DOTFILES_INSTALL_ZSH_STACK:-1}"
INSTALL_TMUX_STACK="${DOTFILES_INSTALL_TMUX_STACK:-1}"
USE_SYMLINKS="${DOTFILES_USE_SYMLINKS:-1}"
DEPLOY_ZSH="${DOTFILES_DEPLOY_ZSH:-1}"
DEPLOY_TMUX="${DOTFILES_DEPLOY_TMUX:-1}"
DEPLOY_GIT="${DOTFILES_DEPLOY_GIT:-1}"
DEPLOY_NVIM="${DOTFILES_DEPLOY_NVIM:-0}"
COPY_TEMPLATES="${DOTFILES_COPY_TEMPLATES:-1}"
CONFIGURE_GIT="${DOTFILES_CONFIGURE_GIT:-0}"
CHANGE_SHELL="${DOTFILES_CHANGE_SHELL:-1}"
INSTALL_TMUX_PLUGINS="${DOTFILES_INSTALL_TMUX_PLUGINS:-1}"
SHELL_CHANGE_STATUS="not_requested"

if [[ "$OS_TYPE" == "linux" && -z "${DOTFILES_DEPLOY_NVIM:-}" ]]; then
    DEPLOY_NVIM=1
fi

if [[ "${DOTFILES_NO_PROMPT:-0}" != "1" ]] && tty_available; then
    CHECKBOX_VARS=(
        INSTALL_PACKAGES
        INSTALL_ZSH_STACK
        INSTALL_TMUX_STACK
        USE_SYMLINKS
        DEPLOY_ZSH
        DEPLOY_TMUX
        DEPLOY_GIT
        DEPLOY_NVIM
        COPY_TEMPLATES
        CONFIGURE_GIT
        CHANGE_SHELL
        INSTALL_TMUX_PLUGINS
    )
    CHECKBOX_LABELS=(
        "Install system packages"
        "Install oh-my-zsh, powerlevel10k, zsh plugins"
        "Install tmux plugin manager"
        "Use symlinks via stow (uncheck to copy files)"
        "Deploy zsh config"
        "Deploy tmux config"
        "Deploy shared git config"
        "Deploy nvim config"
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
deploy_dotfiles
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
if [[ "$SHELL_CHANGE_STATUS" == "changed" || "$SHELL_CHANGE_STATUS" == "already" ]]; then
    echo -e "  - Open a new terminal, or run now: ${YELLOW}exec zsh${NC}"
elif [[ "$SHELL_CHANGE_STATUS" == "failed" && -n "${ZSH_PATH:-}" ]]; then
    echo -e "  - Default shell was not changed. Run: ${YELLOW}chsh -s $ZSH_PATH${NC}"
    echo -e "  - To try zsh only in this session: ${YELLOW}exec zsh${NC}"
elif [[ "$SHELL_CHANGE_STATUS" == "missing" ]]; then
    echo -e "  - Install zsh, then rerun bootstrap or run: ${YELLOW}chsh -s /path/to/zsh${NC}"
elif [[ -n "$(command -v zsh || true)" ]]; then
    echo -e "  - To try zsh now: ${YELLOW}exec zsh${NC}"
    echo -e "  - To make zsh default: ${YELLOW}chsh -s $(command -v zsh)${NC}"
fi
echo "════════════════════════════════════════════════"
