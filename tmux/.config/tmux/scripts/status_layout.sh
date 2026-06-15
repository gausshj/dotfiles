#!/usr/bin/env bash
set -euo pipefail

status_command="#(TMUX_STATUS_DENSITY='#{@tmux_status_density}' TMUX_STATUS_BUDGET='#{@tmux_status_right_budget}' ~/.config/tmux/scripts/status_info.sh)"

usage() {
    cat <<'EOF'
Usage: status_layout.sh [apply|apply-all|apply-all-deferred|print] [-t target-session] [-c target-client]

Calculate tmux status/tab layout budgets.

Commands:
  apply               Set tmux options for the current session.
  apply-all           Set tmux options for all sessions.
  apply-all-deferred  Wait briefly for continuum's hook, then apply all sessions.
  print               Print the calculated values for debugging.
EOF
}

target="${TMUX_STATUS_TARGET:-}"
target_client="${TMUX_STATUS_CLIENT:-}"

show_session_option() {
    local option="$1"

    if [[ -n "$target" ]]; then
        tmux show-option -qv -t "$target" "$option"
    else
        tmux show-option -qv "$option"
    fi
}

display_session_value() {
    local format="$1"

    if [[ -n "$target" ]]; then
        tmux display-message -p -t "$target" "$format"
    else
        tmux display-message -p "$format"
    fi
}

display_client_value() {
    local format="$1"

    if [[ -n "$target_client" ]]; then
        tmux display-message -p -c "$target_client" "$format"
    else
        display_session_value "$format"
    fi
}

set_session_option() {
    local option="$1"
    local value="$2"

    if [[ -n "$target" ]]; then
        tmux set-option -q -t "$target" "$option" "$value"
    else
        tmux set-option -q "$option" "$value"
    fi
}

unset_session_option() {
    local option="$1"

    if [[ -n "$target" ]]; then
        tmux set-option -q -u -t "$target" "$option" 2>/dev/null || true
    else
        tmux set-option -q -u "$option" 2>/dev/null || true
    fi
}

is_uint() {
    [[ "${1:-}" =~ ^[0-9]+$ ]]
}

option_value() {
    local option="$1"
    local fallback="$2"
    local value

    value="$(show_session_option "$option" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
        value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
    fi
    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

continuum_save_enabled() {
    local interval

    interval="$(option_value '@continuum-save-interval' 0)"
    is_uint "$interval" && ((interval > 0))
}

continuum_save_command() {
    local pattern
    local value

    continuum_save_enabled || return 0

    pattern='(#\([^)]*tmux-continuum/scripts/continuum_save\.sh\))'
    for value in "$(show_session_option status-right 2>/dev/null || true)" "$(tmux show-option -gqv status-right 2>/dev/null || true)"; do
        if [[ "$value" =~ $pattern ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done
}

format_value() {
    local format="$1"
    local fallback="$2"
    local value

    value="$(display_session_value "$format" 2>/dev/null || true)"
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

dynamic_full_budget() {
    local max_budget="$1"
    local tab_reserved_budget
    local expanded_budget

    tab_reserved_budget=$((windows * (tab_fixed_width + tab_max_title_width)))
    expanded_budget=$((width - left_budget - tab_reserved_budget))

    if ((expanded_budget < right_budget_full)); then
        printf '%s\n' "$right_budget_full"
    elif ((expanded_budget > max_budget)); then
        printf '%s\n' "$max_budget"
    else
        printf '%s\n' "$expanded_budget"
    fi
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
    left_budget="$(uint_value "${TMUX_STATUS_LEFT_BUDGET:-$(option_value '@tmux_status_left_budget' 24)}" 24)"
    right_budget_full="$(uint_value "${TMUX_STATUS_RIGHT_BUDGET_FULL:-$(option_value '@tmux_status_right_budget_full' 108)}" 108)"
    right_budget_full_max="$(uint_value "${TMUX_STATUS_RIGHT_BUDGET_FULL_MAX:-$(option_value '@tmux_status_right_budget_full_max' 160)}" 160)"
    right_budget_medium="$(uint_value "${TMUX_STATUS_RIGHT_BUDGET_MEDIUM:-$(option_value '@tmux_status_right_budget_medium' 38)}" 38)"
    right_budget_compact="$(uint_value "${TMUX_STATUS_RIGHT_BUDGET_COMPACT:-$(option_value '@tmux_status_right_budget_compact' 24)}" 24)"
    tab_min_title_width="$(uint_value "${TMUX_TAB_MIN_TITLE_WIDTH:-$(option_value '@tmux_tab_min_title_width' 3)}" 3)"
    tab_max_title_width="$(uint_value "${TMUX_TAB_MAX_TITLE_WIDTH:-$(option_value '@tmux_tab_max_title_width' 18)}" 18)"
    tab_fixed_width="$(uint_value "${TMUX_TAB_FIXED_WIDTH:-$(option_value '@tmux_tab_fixed_width' 6)}" 6)"
    desired_full_width="$(uint_value "${TMUX_TAB_DESIRED_FULL_WIDTH:-$(option_value '@tmux_tab_desired_full_width' 10)}" 10)"
    desired_medium_width="$(uint_value "${TMUX_TAB_DESIRED_MEDIUM_WIDTH:-$(option_value '@tmux_tab_desired_medium_width' 7)}" 7)"
    desired_compact_width="$(uint_value "${TMUX_TAB_DESIRED_COMPACT_WIDTH:-$(option_value '@tmux_tab_desired_compact_width' 3)}" 3)"
    many_windows_threshold="$(uint_value "${TMUX_STATUS_MANY_WINDOWS_THRESHOLD:-$(option_value '@tmux_status_many_windows_threshold' 10)}" 10)"

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
            right_budget="$(dynamic_full_budget "$right_budget_full_max")"
            raw_title_width="$(raw_title_width_for_budget "$right_budget")"
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
    local continuum_command
    local status_right
    local status_right_length

    continuum_command="$(continuum_save_command)"
    status_right="$continuum_command"
    if [[ "$density" != "off" ]]; then
        status_right+="$status_command"
    fi

    status_right_length="$right_budget"
    if [[ -n "$continuum_command" && "$status_right_length" -eq 0 ]]; then
        status_right_length=1
    fi

    set_session_option @tmux_status_density "$density"
    set_session_option @tmux_status_right_budget "$right_budget"
    set_session_option @tmux_tab_title_width "$tab_title_width"
    set_session_option @tmux_tab_trim_width "$tab_trim_width"
    set_session_option status-right-length "$status_right_length"
    set_session_option status-right "$status_right"
}

apply_one() {
    local client
    local client_width
    local min_client=""
    local min_width=""
    local session
    local target_id=""
    local width

    if [[ -z "$target_client" && -n "$target" ]]; then
        target_id="$(display_session_value '#{session_id}' 2>/dev/null || true)"
        while read -r session client width; do
            [[ "$session" == "$target_id" ]] || continue
            is_uint "$width" || continue
            if [[ -z "$min_width" || "$width" -lt "$min_width" ]]; then
                min_width="$width"
                min_client="$client"
            fi
        done < <(tmux list-clients -F '#{session_id} #{client_tty} #{client_width}' 2>/dev/null || true)
        target_client="$min_client"
        [[ -n "$target_client" ]] || return 0
    fi

    client_width="$(display_client_value '#{client_width}' 2>/dev/null || true)"
    if ! is_uint "$client_width" || ((client_width == 0)); then
        return 0
    fi

    TMUX_STATUS_WIDTH="$client_width"
    calculate_layout
    apply_layout
}

apply_all() {
    local original_target="$target"
    local original_target_client="$target_client"
    local session

    while IFS= read -r session; do
        [[ -n "$session" ]] || continue
        target="$session"
        target_client=""
        if [[ "$(tmux show-option -gqv @tmux_status_preference 2>/dev/null || true)" == "off" ]]; then
            unset_session_option @tmux_status_preference
        fi
        apply_one
    done < <(tmux list-sessions -F '#{session_id}' 2>/dev/null || true)

    target="$original_target"
    target_client="$original_target_client"
}

wait_for_continuum_hook() {
    local attempt

    for attempt in {1..20}; do
        [[ -n "$(continuum_save_command)" ]] && return 0
        sleep 0.1
    done

    return 1
}

apply_all_deferred() {
    if continuum_save_enabled; then
        wait_for_continuum_hook || true
    fi
    apply_all
}

command="apply"

while (($#)); do
    case "$1" in
        apply | apply-all | apply-all-deferred | print)
            command="$1"
            ;;
        -t | --target)
            shift
            if (($# == 0)); then
                usage >&2
                exit 2
            fi
            target="$1"
            ;;
        -c | --client)
            shift
            if (($# == 0)); then
                usage >&2
                exit 2
            fi
            target_client="$1"
            ;;
        -h | --help | help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
    shift
done

case "$command" in
    apply)
        apply_one
        ;;
    apply-all)
        apply_all
        ;;
    apply-all-deferred)
        apply_all_deferred
        ;;
    print)
        calculate_layout
        print_layout
        ;;
esac
