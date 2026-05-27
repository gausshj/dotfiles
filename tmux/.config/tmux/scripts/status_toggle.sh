#!/usr/bin/env bash
set -euo pipefail

status_command='#(~/.config/tmux/scripts/status_info.sh)'

usage() {
    cat <<'EOF'
Usage: status_toggle.sh [on|off|toggle]

Toggle the right-side tmux machine status segment.
EOF
}

status_on() {
    tmux set-option -g status-right "$status_command" >/dev/null
    tmux set-option -g status-right-length 120 >/dev/null
    tmux display-message 'tmux machine status: on'
}

status_off() {
    tmux set-option -g status-right "" >/dev/null
    tmux set-option -g status-right-length 0 >/dev/null
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
        current="$(tmux show-option -gqv status-right)"
        if [[ -n "$current" ]]; then
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
