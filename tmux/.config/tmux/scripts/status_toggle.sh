#!/usr/bin/env bash
set -euo pipefail

layout_script="$HOME/.config/tmux/scripts/status_layout.sh"

usage() {
    cat <<'EOF'
Usage: status_toggle.sh [on|off|toggle]

Toggle the right-side tmux machine status segment.
EOF
}

status_on() {
    local density

    tmux set-option -q @tmux_status_preference on
    bash "$layout_script" apply >/dev/null 2>&1 || true
    density="$(tmux show-option -qv @tmux_status_density 2>/dev/null || printf 'on')"
    tmux display-message "tmux machine status: on (${density})"
}

status_off() {
    tmux set-option -q @tmux_status_preference off
    bash "$layout_script" apply >/dev/null 2>&1 || true
    tmux display-message 'tmux machine status: off'
}

case "${1:-toggle}" in
    on)
        status_on
        ;;
    off)
        status_off
        ;;
    toggle)
        current="$(tmux show-option -qv @tmux_status_preference 2>/dev/null || tmux show-option -gqv @tmux_status_preference 2>/dev/null || printf 'on')"
        if [[ "$current" != "off" ]]; then
            status_off
        else
            status_on
        fi
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
