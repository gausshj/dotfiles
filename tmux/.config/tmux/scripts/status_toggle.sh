#!/usr/bin/env bash
set -euo pipefail

status_command='#(~/.config/tmux/scripts/status_info.sh)'
layout_script="$HOME/.config/tmux/scripts/status_layout.sh"

usage() {
    cat <<'EOF'
Usage: status_toggle.sh [on|off|toggle]

Toggle the right-side tmux machine status segment.
EOF
}

status_on() {
    local density

    tmux set-option -gq @tmux_status_preference on
    tmux set-option -gq status-right "$status_command"
    bash "$layout_script" apply >/dev/null 2>&1 || true
    density="$(tmux show-option -gqv @tmux_status_density 2>/dev/null || printf 'on')"
    tmux display-message "tmux machine status: on (${density})"
}

status_off() {
    tmux set-option -gq @tmux_status_preference off
    bash "$layout_script" apply >/dev/null 2>&1 || true
    tmux set-option -gq status-right ""
    tmux set-option -gq status-right-length 0
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
        current="$(tmux show-option -gqv @tmux_status_preference 2>/dev/null || printf 'on')"
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
