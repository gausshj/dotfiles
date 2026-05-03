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
# Locale
# ─────────────────────────────────────────────
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

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
