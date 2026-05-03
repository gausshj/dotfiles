#!/usr/bin/env bash

new_window() {
    [[ -x $(command -v fzf 2>/dev/null) ]] || return
    pane_id=$(tmux show -gqv '@fzf_pane_id')
    [[ -n $pane_id ]] && tmux kill-pane -t "$pane_id" >/dev/null 2>&1
    tmux new-window "bash $0 do_action" >/dev/null 2>&1
}

update_mru_pane_ids() {
    o_data=($(tmux show -gqv '@mru_pane_ids'))
    current_pane_id=$(tmux display-message -p '#D')
    n_data=("$current_pane_id")
    for i in "${!o_data[@]}"; do
        [[ $current_pane_id != "${o_data[i]}" ]] && n_data+=("${o_data[i]}")
    done
    tmux set -g '@mru_pane_ids' "${n_data[*]}"
}

do_action() {
    trap 'tmux set -gu @fzf_pane_id' EXIT SIGINT SIGTERM
    current_pane_id=$(tmux display-message -p '#D')
    tmux set -g @fzf_pane_id "$current_pane_id"

    cmd="bash $0 panes_src"
    set -- 'tmux capture-pane -pe -S' \
        '$(start=$(( $(tmux display-message -t {1} -p "#{pane_height}")' \
        '- $FZF_PREVIEW_LINES ));' \
        '(( start>0 )) && echo $start || echo 0) -t {1}'
    preview_cmd=$*
    last_pane_cmd='$(tmux show -gqv "@mru_pane_ids" | cut -d\  -f1)'
    selected=$(FZF_DEFAULT_COMMAND=$cmd fzf -m --preview="$preview_cmd" \
        --preview-window='down:80%' --reverse --info=inline --header-lines=1 \
        --delimiter='\s{2,}' --with-nth=2..-1 --nth=1,2,9 \
        --bind="alt-p:toggle-preview" \
        --bind="ctrl-r:reload($cmd)" \
        --bind="ctrl-x:execute-silent(tmux kill-pane -t {1})+reload($cmd)" \
        --bind="ctrl-v:execute(tmux move-pane -h -t $last_pane_cmd -s {1})+accept" \
        --bind="ctrl-s:execute(tmux move-pane -v -t $last_pane_cmd -s {1})+accept" \
        --bind="ctrl-t:execute-silent(tmux swap-pane -t $last_pane_cmd -s {1})+reload($cmd)")
    (($?)) && return

    ids_o=($(tmux show -gqv '@mru_pane_ids'))
    ids=()
    for id in "${ids_o[@]}"; do
        while read -r pane_line; do
            pane_info=($pane_line)
            pane_id=${pane_info[0]}
            [[ $id == "$pane_id" ]] && ids+=("$id")
        done <<<"$selected"
    done

    id_n=${#ids[@]}
    id1=${ids[0]}
    if ((id_n == 1)); then
        tmux switch-client -t"$id1"
    elif ((id_n > 1)); then
        tmux break-pane -s"$id1"
        i=1
        tmux_cmd="tmux "
        while ((i < id_n)); do
            tmux_cmd+="move-pane -t${ids[i-1]} -s${ids[i]} \\; select-layout -t$id1 'tiled' \\; "
            ((i++))
        done

        if ((id_n == 2)); then
            w_size=($(tmux display-message -p '#{window_width} #{window_height}'))
            w_wid=${w_size[0]}
            w_hei=${w_size[1]}
            if ((9 * w_wid > 16 * w_hei)); then
                layout='even-horizontal'
            else
                layout='even-vertical'
            fi
        else
            layout='tiled'
        fi

        tmux_cmd+="switch-client -t$id1 \\; select-layout -t$id1 $layout \\; "
        eval "$tmux_cmd"
    fi
}

panes_src() {
    printf "%-8s %-12s %-16s %-8s %-8s %-16s %-12s %s\n" \
        'PANEID' 'SESSION' 'WINDOW' 'PANE' 'PID' 'TTY' 'CMD' 'TEXT'

    panes_info="$(tmux list-panes -aF '#D	#{session_name}	#{window_index}:#{window_name}	#I.#P	#{pane_pid}	#{pane_tty}	#{pane_current_command}')"
    printed_ids=""

    print_one_pane() {
        target_id="$1"

        while IFS=$'\t' read -r pane_id session window pane pid tty cmd; do
            [[ -z "$pane_id" ]] && continue

            if [[ "$target_id" = "$pane_id" ]]; then
                case " $printed_ids " in
                    *" $pane_id "*) return ;;
                esac

                printed_ids="$printed_ids $pane_id"
                tty="${tty#/dev/}"

                text="$(tmux capture-pane -p -t "$pane_id" -S -30 2>/dev/null |
                    tr '\n' ' ' |
                    sed 's/[[:space:]][[:space:]]*/ /g' |
                    cut -c1-160)"

                printf "%-8s %-12s %-16s %-8s %-8s %-16s %-12s %s\n" \
                    "$pane_id" "$session" "$window" "$pane" "$pid" "$tty" "$cmd" "$text"
                return
            fi
        done <<<"$panes_info"
    }

    for id in $(tmux show -gqv '@mru_pane_ids'); do
        print_one_pane "$id"
    done

    while IFS=$'\t' read -r pane_id session window pane pid tty cmd; do
        [[ -z "$pane_id" ]] && continue

        case " $printed_ids " in
            *" $pane_id "*) continue ;;
        esac

        printed_ids="$printed_ids $pane_id"
        tty="${tty#/dev/}"

        text="$(tmux capture-pane -p -t "$pane_id" -S -30 2>/dev/null |
            tr '\n' ' ' |
            sed 's/[[:space:]][[:space:]]*/ /g' |
            cut -c1-160)"

        printf "%-8s %-12s %-16s %-8s %-8s %-16s %-12s %s\n" \
            "$pane_id" "$session" "$window" "$pane" "$pid" "$tty" "$cmd" "$text"
    done <<<"$panes_info"

    printed_ids="${printed_ids# }"
    tmux set -g '@mru_pane_ids' "$printed_ids"
}

"$@"
