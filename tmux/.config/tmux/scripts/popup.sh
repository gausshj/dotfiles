#!/usr/bin/env bash
set -euo pipefail

width="${TMUX_POPUP_WIDTH:-85%}"
height="${TMUX_POPUP_HEIGHT:-80%}"
scratch_session="${TMUX_POPUP_SCRATCH_SESSION:-tmux-scratch}"
script_path="${BASH_SOURCE[0]}"
popup_copy_restore_file=""
popup_copy_socket_path=""
popup_copy_active=0
popup_copy_lock_acquired=0
popup_copy_lock_name="dotfiles-popup-copy"
popup_copy_target_option="@dotfiles_popup_parent_client"

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

tmux_for_socket() {
    local socket_path="$1"
    shift

    if [[ -n "$socket_path" ]]; then
        tmux -S "$socket_path" "$@"
    else
        tmux "$@"
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

save_copy_binding() {
    local socket_path="$1"
    local table="$2"
    local key="$3"

    if ! tmux_for_socket "$socket_path" list-keys -T "$table" "$key" >>"$popup_copy_restore_file" 2>/dev/null; then
        printf 'unbind-key -T %s %s\n' "$table" "$key" >>"$popup_copy_restore_file"
    fi
}

copy_binding_command() {
    local socket_path="$1"
    local table="$2"
    local key="$3"
    local line prefix

    line="$(tmux_for_socket "$socket_path" list-keys -T "$table" "$key" 2>/dev/null || true)"
    prefix="bind-key -T $table $key "
    if [[ "$line" == "$prefix"* ]]; then
        printf '%s\n' "${line#"$prefix"}"
    else
        printf '%s\n' "run-shell -b true"
    fi
}

save_session_option() {
    local socket_path="$1"
    local session_name="$2"
    local option="$3"
    local old_option old_value

    old_option="$(tmux_for_socket "$socket_path" show-options -t "$session_name" -q "$option" 2>/dev/null || true)"
    if [[ -n "$old_option" ]]; then
        old_value="$(tmux_for_socket "$socket_path" show-options -t "$session_name" -qv "$option" 2>/dev/null || true)"
        printf 'set-option -t %s %s %s\n' "$(shell_quote "$session_name")" "$option" "$(shell_quote "$old_value")" >>"$popup_copy_restore_file"
    else
        printf 'set-option -u -t %s %s\n' "$(shell_quote "$session_name")" "$option" >>"$popup_copy_restore_file"
    fi
}

tmux_double_quote() {
    local value="$1"

    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    printf '"%s"' "$value"
}

bind_popup_copy_key() {
    local socket_path="$1"
    local table="$2"
    local key="$3"
    local copy_command="$4"
    local popup_command original_command

    original_command="$(copy_binding_command "$socket_path" "$table" "$key")"
    popup_command="send-keys -F -X copy-pipe-and-cancel $(tmux_double_quote "$copy_command")"

    tmux_for_socket "$socket_path" bind-key -T "$table" "$key" \
        if-shell -F "#{${popup_copy_target_option}}" "$popup_command" "$original_command"
}

acquire_popup_copy_lock() {
    local socket_path="$1"
    local target_client="$2"

    [[ -n "$target_client" ]] || return 1
    tmux_version_supports_popup || return 1

    popup_copy_socket_path="$socket_path"
    tmux_for_socket "$socket_path" wait-for -L "$popup_copy_lock_name"
    popup_copy_lock_acquired=1
}

configure_popup_copy() {
    local socket_path="$1"
    local session_name="$2"
    local target_client="$3"
    local copy_command tmux_socket_args

    [[ -n "$target_client" ]] || return 0
    tmux_version_supports_popup || return 0

    # The popup attaches a second tmux client inside the real client. Copy-mode
    # inside that popup must pipe back to the real client, then restore defaults.
    if [[ "$popup_copy_lock_acquired" != "1" ]]; then
        acquire_popup_copy_lock "$socket_path" "$target_client" || return 0
    fi

    popup_copy_restore_file="$(mktemp "${TMPDIR:-/tmp}/tmux-popup-copy.XXXXXX")"
    popup_copy_active=1

    save_copy_binding "$socket_path" copy-mode-vi y
    save_copy_binding "$socket_path" copy-mode-vi Enter
    save_copy_binding "$socket_path" copy-mode-vi MouseDragEnd1Pane
    save_copy_binding "$socket_path" copy-mode y
    save_copy_binding "$socket_path" copy-mode Enter
    save_copy_binding "$socket_path" copy-mode MouseDragEnd1Pane
    save_session_option "$socket_path" "$session_name" "$popup_copy_target_option"

    tmux_for_socket "$socket_path" set-option -t "$session_name" "$popup_copy_target_option" "$target_client"

    tmux_socket_args="$(tmux_args_for_socket "$socket_path")"
    copy_command="tmux ${tmux_socket_args:+$tmux_socket_args }load-buffer -w -t \"#{${popup_copy_target_option}}\" -"

    bind_popup_copy_key "$socket_path" copy-mode-vi y "$copy_command"
    bind_popup_copy_key "$socket_path" copy-mode-vi Enter "$copy_command"
    bind_popup_copy_key "$socket_path" copy-mode-vi MouseDragEnd1Pane "$copy_command"
    bind_popup_copy_key "$socket_path" copy-mode y "$copy_command"
    bind_popup_copy_key "$socket_path" copy-mode Enter "$copy_command"
    bind_popup_copy_key "$socket_path" copy-mode MouseDragEnd1Pane "$copy_command"
}

restore_popup_copy() {
    if [[ "$popup_copy_active" == "1" ]]; then
        popup_copy_active=0
    fi

    if [[ -n "$popup_copy_restore_file" && -f "$popup_copy_restore_file" ]]; then
        tmux_for_socket "$popup_copy_socket_path" source-file "$popup_copy_restore_file" >/dev/null 2>&1 || true
        rm -f "$popup_copy_restore_file"
    fi

    if [[ "$popup_copy_lock_acquired" == "1" ]]; then
        tmux_for_socket "$popup_copy_socket_path" wait-for -U "$popup_copy_lock_name" >/dev/null 2>&1 || true
        popup_copy_lock_acquired=0
    fi
}

open_shell() {
    local path shell_path socket_path client_name session_name command

    path="$(current_path)"
    shell_path="$(default_shell)"
    socket_path="$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)"
    client_name="$(tmux display-message -p '#{client_name}' 2>/dev/null || true)"
    session_name="tmux-popup-$$-$RANDOM"
    command="$(popup_command _temp-session "$socket_path" "$session_name" "$path" "$shell_path" "$client_name")"

    if tmux_version_supports_popup; then
        tmux display-popup -E -d "$path" -w "$width" -h "$height" -T ' shell ' "$command" || true
    else
        tmux new-window -c "$path" "$shell_path -l" || true
    fi
}

open_scratch() {
    local path socket_path client_name command

    path="$(current_path)"
    socket_path="$(tmux display-message -p '#{socket_path}' 2>/dev/null || true)"
    client_name="$(tmux display-message -p '#{client_name}' 2>/dev/null || true)"

    if tmux_version_supports_popup; then
        command="$(popup_command _scratch-session "$socket_path" "$scratch_session" "$path" "$client_name")"
        tmux display-popup -E -d "$path" -w "$width" -h "$height" -T " scratch: $scratch_session " "$command" || true
    else
        command="$(popup_command _scratch-session "$socket_path" "$scratch_session" "$path" "")"
        tmux new-window -c "$path" "$command" || true
    fi
}

attach_temp_session() {
    local socket_path="$1"
    local session_name="$2"
    local path="$3"
    local shell_path="$4"
    local target_client="$5"
    local tmux_socket_args

    tmux_socket_args="$(tmux_args_for_socket "$socket_path")"
    unset TMUX

    cleanup_temp_session() {
        restore_popup_copy
        # shellcheck disable=SC2086
        tmux $tmux_socket_args kill-session -t "$session_name" >/dev/null 2>&1 || true
    }

    trap cleanup_temp_session EXIT
    trap 'exit 130' HUP INT TERM

    acquire_popup_copy_lock "$socket_path" "$target_client" || true

    # shellcheck disable=SC2086
    tmux $tmux_socket_args new-session -d -s "$session_name" -c "$path" "$shell_path -l" >/dev/null 2>&1 || true
    # shellcheck disable=SC2086
    tmux $tmux_socket_args set-option -t "$session_name" status off >/dev/null 2>&1 || true
    configure_popup_copy "$socket_path" "$session_name" "$target_client"
    # shellcheck disable=SC2086
    tmux $tmux_socket_args attach-session -t "$session_name" || true
    restore_popup_copy
    # shellcheck disable=SC2086
    tmux $tmux_socket_args kill-session -t "$session_name" >/dev/null 2>&1 || true
    trap - EXIT HUP INT TERM
}

attach_scratch_session() {
    local socket_path="$1"
    local session_name="$2"
    local path="$3"
    local target_client="$4"
    local tmux_socket_args

    tmux_socket_args="$(tmux_args_for_socket "$socket_path")"
    unset TMUX

    trap restore_popup_copy EXIT
    trap 'exit 130' HUP INT TERM

    acquire_popup_copy_lock "$socket_path" "$target_client" || true

    # shellcheck disable=SC2086
    tmux $tmux_socket_args new-session -d -s "$session_name" -c "$path" >/dev/null 2>&1 || true
    configure_popup_copy "$socket_path" "$session_name" "$target_client"
    # shellcheck disable=SC2086
    tmux $tmux_socket_args attach-session -t "$session_name" || true
    restore_popup_copy
    trap - EXIT HUP INT TERM
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
        attach_temp_session "$2" "$3" "$4" "$5" "${6:-}"
        ;;
    _scratch-session)
        attach_scratch_session "$2" "$3" "$4" "${5:-}"
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
