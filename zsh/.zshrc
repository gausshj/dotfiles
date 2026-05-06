# ─────────────────────────────────────────────
# Terminal and locale (must be set before powerlevel10k initializes)
# ─────────────────────────────────────────────
if [[ -z "${TERM:-}" || "$TERM" == "dumb" ]]; then
    export TERM=xterm-256color
fi

if command -v tput >/dev/null 2>&1; then
    _dotfiles_term_colors="$(tput colors 2>/dev/null || printf '0')"
    if [[ "${_dotfiles_term_colors:-0}" -lt 256 ]]; then
        case "${TERM:-}" in
            xterm) export TERM=xterm-256color ;;
            screen) export TERM=screen-256color ;;
            tmux) export TERM=tmux-256color ;;
            *)
                if [[ -f /.dockerenv || -n "${container:-}" || -n "${SSH_TTY:-}" ]]; then
                    export TERM=xterm-256color
                fi
                ;;
        esac
    fi
    unset _dotfiles_term_colors
fi

case "${TERM:-}" in
    *-256color)
        export COLORTERM="${COLORTERM:-truecolor}"
        ;;
esac

if command -v locale >/dev/null 2>&1; then
    _dotfiles_locales="$(locale -a 2>/dev/null)"
    if printf '%s\n' "$_dotfiles_locales" | grep -Eqi '^en_US\.(UTF-8|utf8)$'; then
        export LANG=en_US.UTF-8
        export LC_ALL=en_US.UTF-8
    elif printf '%s\n' "$_dotfiles_locales" | grep -Eqi '^C\.(UTF-8|utf8)$'; then
        export LANG=C.UTF-8
        export LC_ALL=C.UTF-8
    fi
    unset _dotfiles_locales
fi

# ─────────────────────────────────────────────
# Enable Powerlevel10k instant prompt
# ─────────────────────────────────────────────
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# ─────────────────────────────────────────────
# Oh My Zsh
# ─────────────────────────────────────────────
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"

# ─────────────────────────────────────────────
# macOS: fix fpath for Homebrew completions
# ─────────────────────────────────────────────
if command -v brew >/dev/null 2>&1; then
  eval "$(/usr/bin/env brew shellenv)" 2>/dev/null
  fpath=(${fpath:#/usr/local/share/zsh/site-functions})
  fpath=("$(brew --prefix)"/share/zsh/site-functions $fpath)
  typeset -U fpath
fi

# ─────────────────────────────────────────────
# Plugins
# ─────────────────────────────────────────────
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    zsh-z
)

source $ZSH/oh-my-zsh.sh

# ─────────────────────────────────────────────
# Editor
# ─────────────────────────────────────────────
if command -v nvim >/dev/null 2>&1; then
    export EDITOR="nvim"
    export VISUAL="nvim"
elif command -v vim >/dev/null 2>&1; then
    export EDITOR="vim"
    export VISUAL="vim"
fi

# ─────────────────────────────────────────────
# GPG
# ─────────────────────────────────────────────
export GPG_TTY=$(tty)
gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1

# ─────────────────────────────────────────────
# Powerlevel10k prompt
# ─────────────────────────────────────────────
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# ─────────────────────────────────────────────
# Machine-specific overrides (gitignored)
# ─────────────────────────────────────────────
[[ -f ~/.zshrc.local ]] && source ~/.zshrc.local

# ─────────────────────────────────────────────
# Secrets: API keys, tokens, DB credentials (gitignored)
# ─────────────────────────────────────────────
[[ -f ~/.zshrc.secrets ]] && source ~/.zshrc.secrets
