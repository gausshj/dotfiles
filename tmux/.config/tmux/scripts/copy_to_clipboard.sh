#!/usr/bin/env bash
set -euo pipefail

tmp="$(mktemp "${TMPDIR:-/tmp}/tmux-copy.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

cat >"$tmp"
[[ -s "$tmp" ]] || exit 0

copy_with() {
    local command_name="$1"
    shift

    if command -v "$command_name" >/dev/null 2>&1 && "$command_name" "$@" <"$tmp" >/dev/null 2>&1; then
        exit 0
    fi
}

case "$(uname -s)" in
    Darwin)
        copy_with pbcopy
        ;;
    Linux)
        if [[ -n "${WAYLAND_DISPLAY:-}" ]]; then
            copy_with wl-copy
        fi
        if [[ -n "${DISPLAY:-}" ]]; then
            copy_with xclip -selection clipboard
            copy_with xsel --clipboard --input
        fi
        copy_with wl-copy
        copy_with xclip -selection clipboard
        copy_with xsel --clipboard --input
        ;;
esac

# copy-pipe-and-cancel already stores the selection in tmux's paste buffer.
# Exit cleanly if this host has no system clipboard command available.
exit 0
