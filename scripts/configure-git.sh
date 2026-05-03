#!/usr/bin/env bash
set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
step() { echo -e "${CYAN}[STEP]${NC} $*"; }

marker_begin() {
    printf '# >>> dotfiles git setup >>>\n'
}

marker_end() {
    printf '# <<< dotfiles git setup <<<\n'
}

prompt() {
    local label="$1"
    local default="${2:-}"
    local value

    if [[ -n "$default" ]]; then
        read -r -p "$label [$default]: " value
        printf '%s' "${value:-$default}"
    else
        read -r -p "$label: " value
        printf '%s' "$value"
    fi
}

prompt_secret() {
    local label="$1"
    local value

    read -r -s -p "$label: " value
    printf '\n' >&2
    printf '%s' "$value"
}

append_or_replace_block() {
    local file="$1"
    local tmp block
    tmp="$(mktemp)"
    block="$(mktemp)"

    cat >"$block"
    mkdir -p "$(dirname "$file")"
    touch "$file"

    awk '
        /^# >>> dotfiles git setup >>>$/ { skip = 1; next }
        /^# <<< dotfiles git setup <<<$/ { skip = 0; next }
        skip != 1 { print }
    ' "$file" >"$tmp"

    {
        sed -e '${/^$/d;}' "$tmp"
        printf '\n'
        cat "$block"
    } >"$file"

    rm -f "$tmp" "$block"
}

write_gitconfig_local() {
    local file="$HOME/.gitconfig.local"
    local current_name current_email name email signing_key gpgsign

    current_name="$(git config --global --get user.name 2>/dev/null || true)"
    current_email="$(git config --global --get user.email 2>/dev/null || true)"

    step "Git identity"
    name="$(prompt 'Git user.name' "$current_name")"
    email="$(prompt 'Git user.email' "$current_email")"
    signing_key="$(prompt 'GPG signing key (optional)' '')"
    gpgsign="$(prompt 'Sign commits with GPG? yes/no' 'no')"

    append_or_replace_block "$file" <<EOF
$(marker_begin)
[user]
	name = $name
	email = $email
EOF

    if [[ -n "$signing_key" ]]; then
        cat >>"$file" <<EOF
	signingkey = $signing_key
EOF
    fi

    if [[ "$gpgsign" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
        cat >>"$file" <<'EOF'
[commit]
	gpgsign = true
[gpg]
	program = gpg
EOF
    fi

    marker_end >>"$file"
    info "Wrote $file"
}

write_github_token() {
    local file="$HOME/.zshrc.secrets"
    local configure token

    configure="$(prompt 'Configure GH_TOKEN for this machine? yes/no' 'no')"
    if [[ ! "$configure" =~ ^([Yy][Ee][Ss]|[Yy])$ ]]; then
        info "Skipping GH_TOKEN"
        return
    fi

    token="$(prompt_secret 'GH_TOKEN')"
    if [[ -z "$token" ]]; then
        warn "Empty GH_TOKEN; skipping"
        return
    fi

    append_or_replace_block "$file" <<'EOF'
# >>> dotfiles git setup >>>
# Personal-machine GitHub token. Never commit this file.
EOF

    printf 'export GH_TOKEN=%q\n' "$token" >>"$file"
    marker_end >>"$file"
    chmod 600 "$file"
    info "Wrote $file"
}

if [[ ! -t 0 ]]; then
    warn "No interactive terminal detected; skipping local configuration prompts."
    exit 0
fi

write_gitconfig_local
write_github_token

info "Personal Git/GPG/GitHub configuration complete."
