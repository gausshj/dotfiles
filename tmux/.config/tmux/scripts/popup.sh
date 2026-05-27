#!/usr/bin/env bash
set -euo pipefail

width="${TMUX_POPUP_WIDTH:-85%}"
height="${TMUX_POPUP_HEIGHT:-80%}"
scratch_session="${TMUX_POPUP_SCRATCH_SESSION:-tmux-scratch}"
script_path="${BASH_SOURCE[0]}"

tmux_version_supports_popup() {
    local version major minor

    version="$(tmux -V 2>/dev/null | awk '{print $2}')"
    version="${version%%[-_]*}"
    version="${version%%[!0-9.]*}"
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"

    [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
    ((major > 3 || (major == 3 && minor >= 2)))
}

current_path() {
    tmux display-message -p '#{pane_current_path}' 2>/dev/null || printf '%s\n' "$HOME"
}

default_shell() {
    local shell_path

    shell_path="$(tmux show-option -gqv default-shell 2>/dev/null || true)"
    if [[ -n "$shell_path" && -x "$shell_path" ]]; then
        printf '%s\n' "$shell_path"
        return
    fi

    printf '%s\n' "${SHELL:-/bin/sh}"
}

shell_quote() {
    printf '%q' "$1"
}

tmux_args_for_socket() {
    local socket_path="$1"

    if [[ -n "$socket_path" ]]; then
        printf -- '-S %s' "$(shell_quote "$socket_path")"
    fi
}

popup_command() {
    local subcommand="$1"
    shift

    printf 'bash %s %s' "$(shell_quote "$script_path")" "$(shell_quote "$subcommand")"
    for arg in "$@"; do
        printf ' %s' "$(shell_quote "$arg")"
    done
}

open_shell() {
    local path shell_path socket_path session_name command

    path="$(current_path)"
    shell_path="$(default_shell)"
    socket_path="$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)"
    session_name="tmux-popup-$$-$RANDOM"
    command="$(popup_command _temp-session "$socket_path" "$session_name" "$path" "$shell_path")"

    if tmux_version_supports_popup; then
        tmux display-popup -E -d "$path" -w "$width" -h "$height" -T ' shell ' "$command" || true
    else
        tmux new-window -c "$path" "$shell_path -l" || true
    fi
}

open_scratch() {
    local path socket_path command

    path="$(current_path)"
    socket_path="$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)"
    command="$(popup_command _scratch-session "$socket_path" "$scratch_session" "$path")"

    if tmux_version_supports_popup; then
        tmux display-popup -E -d "$path" -w "$width" -h "$height" -T " scratch: $scratch_session " "$command" || true
    else
        tmux new-window -c "$path" "$command" || true
    fi
}

attach_temp_session() {
    local socket_path="$1"
    local session_name="$2"
    local path="$3"
    local shell_path="$4"
    local tmux_socket_args

    tmux_socket_args="$(tmux_args_for_socket "$socket_path")"
    unset TMUX

    # shellcheck disable=SC2086
    tmux $tmux_socket_args new-session -d -s "$session_name" -c "$path" "$shell_path -l" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    tmux $tmux_socket_args set-option -t "$session_name" status off >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    tmux $tmux_socket_args attach-session -t "$session_name" || true
    # shellcheck disable=SC2086
    tmux $tmux_socket_args kill-session -t "$session_name" >/dev/null 2>&1 || true
}

attach_scratch_session() {
    local socket_path="$1"
    local session_name="$2"
    local path="$3"
    local tmux_socket_args

    tmux_socket_args="$(tmux_args_for_socket "$socket_path")"
    unset TMUX

    # shellcheck disable=SC2086
    tmux $tmux_socket_args new-session -d -s "$session_name" -c "$path" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    tmux $tmux_socket_args attach-session -t "$session_name" || true
}

usage() {
    cat <<'EOF'
Usage: popup.sh <command>

Commands:
  shell     Open a temporary shell popup in the current pane directory.
  scratch   Open or attach to a persistent scratch tmux session in a popup.

Inside a popup, use the normal tmux copy-mode keys, for example prefix + [
then vi-style selection with v/y.
EOF
}

case "${1:-}" in
    shell)
        open_shell
        ;;
    scratch)
        open_scratch
        ;;
    _temp-session)
        attach_temp_session "$2" "$3" "$4" "$5"
        ;;
    _scratch-session)
        attach_scratch_session "$2" "$3" "$4"
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
