#!/usr/bin/env bash
set -u

segment() {
    local color="$1"
    local text="$2"

    [[ -n "$text" ]] || return
    printf '#[fg=%s]%s' "$color" "$text"
}

option_value() {
    local option="$1"
    local fallback="$2"
    local value

    value="$(tmux show-option -qv "$option" 2>/dev/null || true)"
    if [[ -z "$value" ]]; then
        value="$(tmux show-option -gqv "$option" 2>/dev/null || true)"
    fi

    if [[ -n "$value" ]]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' "$fallback"
    fi
}

linux_cpu() {
    top -bn1 2>/dev/null | awk -F'[, ]+' '/Cpu\(s\)/ {printf "%.1f%%", $2 + $4; exit}'
}

macos_cpu() {
    top -l 1 -n 0 2>/dev/null | awk '
        /CPU usage/ {
            user=$3
            sys=$5
            gsub("%", "", user)
            gsub("%", "", sys)
            printf "%.1f%%", user + sys
            exit
        }
    '
}

linux_mem() {
    free -h 2>/dev/null | awk '/Mem:/ {print $3 "/" $2; exit}'
}

macos_mem() {
    local total page_size active wired compressed used

    total="$(sysctl -n hw.memsize 2>/dev/null || true)"
    page_size="$(pagesize 2>/dev/null || true)"
    [[ -n "$total" && -n "$page_size" ]] || return

    read -r active wired compressed < <(
        vm_stat 2>/dev/null | awk '
            /Pages active/ {gsub("[^0-9]", "", $3); active=$3}
            /Pages wired down/ {gsub("[^0-9]", "", $4); wired=$4}
            /Pages occupied by compressor/ {gsub("[^0-9]", "", $5); compressed=$5}
            END {print active + 0, wired + 0, compressed + 0}
        '
    )
    active="${active:-0}"
    wired="${wired:-0}"
    compressed="${compressed:-0}"
    used=$(( (active + wired + compressed) * page_size ))
    awk -v used="$used" -v total="$total" 'BEGIN {printf "%.1f/%.1fGiB", used/1073741824, total/1073741824}'
}

linux_gpu() {
    local gpu_info gpu_util gpu_used gpu_total

    command -v nvidia-smi >/dev/null 2>&1 || return
    gpu_info="$(nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n1 | tr -d ' ')"
    [[ -n "$gpu_info" ]] || return
    gpu_util="${gpu_info%%,*}"
    gpu_info="${gpu_info#*,}"
    gpu_used="${gpu_info%%,*}"
    gpu_total="${gpu_info#*,}"
    printf 'G:%s%% %sM' "$gpu_util" "$gpu_used"
}

linux_net() {
    local iface stats

    iface="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
    [[ -n "$iface" ]] || return
    command -v ifstat >/dev/null 2>&1 || return

    stats="$(ifstat -i "$iface" 0.1 1 2>/dev/null | tail -n 1 | awk '{printf "N:%.1fU %.1fD", $2, $1}')"
    [[ -n "$stats" ]] || return
    printf '%s' "$stats"
}

linux_disks() {
    df -h -P 2>/dev/null | awk '
        NR > 1 {
            size = $2
            target = $6

            if ($1 !~ "^/dev/" && target !~ "^/(mnt|media)/") next
            if (target ~ "^/(boot|snap|var/lib/docker|run|dev|proc|sys)(/|$)") next
            if (size ~ /K$/ || size ~ /M$/) next

            used = $5
            sub("%", "", used)
            if (used == "") next

            label = target
            if (label == "/") label = "root"
            sub("^/home/[^/]+/", "", label)
            sub("^/mnt/", "", label)
            sub("^/media/[^/]+/", "", label)

            if (out != "") out = out " "
            used = $5
            sub("%", "", used)
            out = out label used
        }
        END {
            if (out != "") print "D:" out
        }
    '
}

macos_disks() {
    df -H -P 2>/dev/null | awk '
        NR > 1 && ($1 ~ "^/dev/" || $6 ~ "^/Volumes/") {
            target = $6
            if (target ~ "^/System/Volumes/(VM|Preboot|Update|xarts|iSCPreboot|Hardware)") next
            if (target ~ "^/private/var/") next

            label = target
            if (label == "/") label = "root"
            sub("^/System/Volumes/Data$", "data", label)
            sub("^/Volumes/", "", label)

            if (seen[label]++) next
            if (out != "") out = out " "
            used = $5
            sub("%", "", used)
            out = out label used
        }
        END {
            if (out != "") print "D:" out
        }
    '
}

main() {
    local os cpu mem gpu net disk now host
    local density
    local budget
    local required_width
    local optional_width=0
    local selected_cpu="" selected_mem="" selected_gpu="" selected_net="" selected_disk=""
    local first=1
    local default_budget

    density="${TMUX_STATUS_DENSITY:-$(option_value @tmux_status_density compact)}"
    case "$density" in
        full | medium | compact)
            ;;
        off)
            return
            ;;
        *)
            density="compact"
            ;;
    esac

    budget="${TMUX_STATUS_BUDGET:-$(option_value @tmux_status_right_budget '')}"
    case "$density" in
        full)
            default_budget=108
            ;;
        medium)
            default_budget=38
            ;;
        compact)
            default_budget=24
            ;;
    esac
    [[ "$budget" =~ ^[0-9]+$ ]] || budget="$default_budget"

    os="$(uname -s)"
    case "$os" in
        Darwin)
            if [[ "$density" == "full" ]]; then
                cpu="$(macos_cpu)"
                mem="$(macos_mem)"
            else
                cpu=""
                mem=""
            fi
            gpu=""
            net=""
            if [[ "$density" == "full" || "$density" == "medium" ]]; then
                disk="$(macos_disks)"
            else
                disk=""
            fi
            ;;
        Linux)
            if [[ "$density" == "full" ]]; then
                cpu="$(linux_cpu)"
                mem="$(linux_mem)"
                gpu="$(linux_gpu)"
                net="$(linux_net)"
            else
                cpu=""
                mem=""
                gpu=""
                net=""
            fi
            if [[ "$density" == "full" || "$density" == "medium" ]]; then
                disk="$(linux_disks)"
            else
                disk=""
            fi
            ;;
        *)
            cpu=""
            mem=""
            gpu=""
            net=""
            disk=""
            ;;
    esac

    if [[ "$density" == "compact" ]]; then
        now="$(date '+%H:%M:%S')"
    else
        now="$(date '+%Y-%m-%d %H:%M:%S')"
    fi
    host="$(hostname -s 2>/dev/null || hostname)"
    mem="${mem//GiB/G}"
    mem="${mem//Gi/G}"

    required_width=$((${#now} + ${#host}))
    if [[ -n "$now" && -n "$host" ]]; then
        required_width=$((required_width + 3))
    fi

    can_fit_optional() {
        local text="$1"
        local next_optional_width
        local bridge_width=0

        [[ -n "$text" ]] || return 1
        if ((optional_width > 0)); then
            next_optional_width=$((optional_width + 3 + ${#text}))
        else
            next_optional_width="${#text}"
        fi
        if ((next_optional_width > 0 && required_width > 0)); then
            bridge_width=3
        fi
        ((next_optional_width + bridge_width + required_width <= budget))
    }

    select_optional() {
        local name="$1"
        local text="$2"

        can_fit_optional "$text" || return
        if ((optional_width > 0)); then
            optional_width=$((optional_width + 3 + ${#text}))
        else
            optional_width="${#text}"
        fi

        case "$name" in
            cpu)
                selected_cpu="$text"
                ;;
            mem)
                selected_mem="$text"
                ;;
            gpu)
                selected_gpu="$text"
                ;;
            net)
                selected_net="$text"
                ;;
            disk)
                selected_disk="$text"
                ;;
        esac
    }

    upgrade_optional() {
        local name="$1"
        local text="$2"
        local current=""
        local delta
        local bridge_width=0

        [[ -n "$text" ]] || return
        case "$name" in
            cpu)
                current="$selected_cpu"
                ;;
            mem)
                current="$selected_mem"
                ;;
            gpu)
                current="$selected_gpu"
                ;;
            net)
                current="$selected_net"
                ;;
            disk)
                current="$selected_disk"
                ;;
        esac

        [[ -n "$current" ]] || return
        delta=$((${#text} - ${#current}))
        if ((delta <= 0)); then
            :
        elif ((optional_width + delta > 0 && required_width > 0)); then
            bridge_width=3
        fi
        ((optional_width + delta + bridge_width + required_width <= budget)) || return
        optional_width=$((optional_width + delta))

        case "$name" in
            cpu)
                selected_cpu="$text"
                ;;
            mem)
                selected_mem="$text"
                ;;
            gpu)
                selected_gpu="$text"
                ;;
            net)
                selected_net="$text"
                ;;
            disk)
                selected_disk="$text"
                ;;
        esac
    }

    if [[ "$density" == "full" ]]; then
        select_optional cpu "${cpu:+C:$cpu}"
        select_optional mem "${mem:+M:$mem}"
        select_optional gpu "$gpu"
        select_optional net "$net"
        select_optional disk "$disk"
        upgrade_optional cpu "${cpu:+CPU:$cpu}"
        upgrade_optional mem "${mem:+MEM:$mem}"
        upgrade_optional gpu "${gpu/#G:/GPU:}"
        upgrade_optional net "${net/#N:/NET:}"
        upgrade_optional disk "${disk/#D:/Disk:}"
    fi
    if [[ "$density" == "medium" ]]; then
        select_optional disk "$disk"
        upgrade_optional disk "${disk/#D:/Disk:}"
    fi

    add_segment() {
        local color="$1"
        local text="$2"

        [[ -n "$text" ]] || return
        if ((first)); then
            first=0
        else
            printf ' #[fg=%s]| ' brightblack
        fi
        segment "$color" "$text"
    }

    add_segment cyan "$selected_cpu"
    add_segment green "$selected_mem"
    add_segment magenta "$selected_gpu"
    add_segment brightblue "$selected_net"
    add_segment yellow "$selected_disk"
    add_segment blue "$now"
    add_segment brightcyan "$host"
}

main
