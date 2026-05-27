#!/usr/bin/env bash
set -euo pipefail

status_command='#(~/.config/tmux/scripts/status_info.sh)'

usage() {
    cat <<'EOF'
Usage: status_layout.sh [apply|print]

Calculate tmux status/tab layout budgets.

Commands:
  apply  Set tmux options for the current server.
  print  Print the calculated values for debugging.
EOF
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

option_value() {
    local option="$1"
    local fallback="$2"
    local value

    value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

format_value() {
    local format="$1"
    local fallback="$2"
    local value

    value="$(tmux display-message -p "$format" 2>/dev/null || true)"
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

uint_value() {
    local value="$1"
    local fallback="$2"

    if is_uint "$value"; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

raw_title_width_for_budget() {
    local right_budget="$1"
    local available

    available=$((width - left_budget - right_budget - (windows * tab_fixed_width)))
    printf '%s\n' $((available / windows))
}

clamp_title_width() {
    local raw="$1"

    if ((raw < tab_min_title_width)); then
        printf '%s\n' "$tab_min_title_width"
    elif ((raw > tab_max_title_width)); then
        printf '%s\n' "$tab_max_title_width"
    else
        printf '%s\n' "$raw"
    fi
}

calculate_layout() {
    width="$(uint_value "${TMUX_STATUS_WIDTH:-$(format_value '#{client_width}' 0)}" 0)"
    windows="$(uint_value "${TMUX_STATUS_WINDOWS:-$(format_value '#{session_windows}' 1)}" 1)"
    ((windows > 0)) || windows=1

    preference="${TMUX_STATUS_PREFERENCE:-$(option_value '@tmux_status_preference' on)}"
    left_budget="$(uint_value "$(option_value '@tmux_status_left_budget' 16)" 16)"
    right_budget_full="$(uint_value "$(option_value '@tmux_status_right_budget_full' 64)" 64)"
    right_budget_medium="$(uint_value "$(option_value '@tmux_status_right_budget_medium' 38)" 38)"
    right_budget_compact="$(uint_value "$(option_value '@tmux_status_right_budget_compact' 24)" 24)"
    tab_min_title_width="$(uint_value "$(option_value '@tmux_tab_min_title_width' 3)" 3)"
    tab_max_title_width="$(uint_value "$(option_value '@tmux_tab_max_title_width' 18)" 18)"
    tab_fixed_width="$(uint_value "$(option_value '@tmux_tab_fixed_width' 6)" 6)"
    desired_full_width="$(uint_value "$(option_value '@tmux_tab_desired_full_width' 10)" 10)"
    desired_medium_width="$(uint_value "$(option_value '@tmux_tab_desired_medium_width' 7)" 7)"
    desired_compact_width="$(uint_value "$(option_value '@tmux_tab_desired_compact_width' 3)" 3)"
    many_windows_threshold="$(uint_value "$(option_value '@tmux_status_many_windows_threshold' 10)" 10)"

    density="off"
    right_budget=0

    if [[ "$preference" != "off" && "$width" -gt 0 ]]; then
        raw_full="$(raw_title_width_for_budget "$right_budget_full")"
        raw_medium="$(raw_title_width_for_budget "$right_budget_medium")"
        raw_compact="$(raw_title_width_for_budget "$right_budget_compact")"

        if ((windows >= many_windows_threshold)); then
            if ((raw_compact >= desired_compact_width)); then
                density="compact"
                right_budget="$right_budget_compact"
                raw_title_width="$raw_compact"
            else
                density="off"
                right_budget=0
                raw_title_width="$(raw_title_width_for_budget 0)"
            fi
        elif ((raw_full >= desired_full_width)); then
            density="full"
            right_budget="$right_budget_full"
            raw_title_width="$raw_full"
        elif ((raw_medium >= desired_medium_width)); then
            density="medium"
            right_budget="$right_budget_medium"
            raw_title_width="$raw_medium"
        elif ((raw_compact >= desired_compact_width)); then
            density="compact"
            right_budget="$right_budget_compact"
            raw_title_width="$raw_compact"
        else
            density="off"
            right_budget=0
            raw_title_width="$(raw_title_width_for_budget 0)"
        fi
    else
        raw_title_width="$(raw_title_width_for_budget 0)"
    fi

    tab_title_width="$(clamp_title_width "$raw_title_width")"
    tab_trim_width="$tab_title_width"
}

print_layout() {
    printf 'density=%s\n' "$density"
    printf 'right_budget=%s\n' "$right_budget"
    printf 'title_width=%s\n' "$tab_title_width"
    printf 'trim_width=%s\n' "$tab_trim_width"
}

apply_layout() {
    tmux set-option -gq @tmux_status_density "$density"
    tmux set-option -gq @tmux_status_right_budget "$right_budget"
    tmux set-option -gq @tmux_tab_title_width "$tab_title_width"
    tmux set-option -gq @tmux_tab_trim_width "$tab_trim_width"
    tmux set-option -gq status-right-length "$right_budget"

    if [[ "$density" == "off" ]]; then
        tmux set-option -gq status-right ""
    else
        tmux set-option -gq status-right "$status_command"
    fi
}

command="${1:-apply}"

case "$command" in
    apply)
        tmux display-message -p '#{client_width}' >/dev/null 2>&1 || exit 0
        calculate_layout
        apply_layout
        ;;
    print)
        calculate_layout
        print_layout
        ;;
    -h | --help | help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
