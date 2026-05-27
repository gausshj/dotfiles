#!/usr/bin/env bash
set -u

segment() {
    local color="$1"
    local text="$2"

    [[ -n "$text" ]] || return
    printf '#[fg=%s]%s ' "$color" "$text"
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
    printf 'GPU:%s%% %s/%sMiB' "$gpu_util" "$gpu_used" "$gpu_total"
}

linux_net() {
    local iface stats

    iface="$(ip -o -4 route show to default 2>/dev/null | awk '{print $5; exit}')"
    [[ -n "$iface" ]] || return
    command -v ifstat >/dev/null 2>&1 || return

    stats="$(ifstat -i "$iface" 0.1 1 2>/dev/null | tail -n 1 | awk '{printf "Net:Up %.1fKB/s Down %.1fKB/s", $2, $1}')"
    [[ -n "$stats" ]] || return
    printf '%s' "$stats"
}

linux_disks() {
    df -h -P 2>/dev/null | awk '
        NR > 1 && $1 ~ "^/dev/" {
            size = $2
            target = $6

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
            out = out label ":" $5
        }
        END {
            if (out != "") print "Disk:" out
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
            out = out label ":" $5
        }
        END {
            if (out != "") print "Disk:" out
        }
    '
}

main() {
    local os cpu mem gpu net disk now host
    local width
    local windows
    local tab_budget
    local first=1

    os="$(uname -s)"
    case "$os" in
        Darwin)
            cpu="$(macos_cpu)"
            mem="$(macos_mem)"
            gpu=""
            net=""
            disk="$(macos_disks)"
            ;;
        Linux)
            cpu="$(linux_cpu)"
            mem="$(linux_mem)"
            gpu="$(linux_gpu)"
            net="$(linux_net)"
            disk="$(linux_disks)"
            ;;
        *)
            cpu=""
            mem=""
            gpu=""
            net=""
            disk=""
            ;;
    esac

    now="$(date '+%Y-%m-%d %H:%M:%S')"
    host="$(hostname -s 2>/dev/null || hostname)"
    width="${TMUX_STATUS_WIDTH:-$(tmux display-message -p '#{client_width}' 2>/dev/null || printf '0')}"
    [[ "$width" =~ ^[0-9]+$ ]] || width=0
    windows="${TMUX_STATUS_WINDOWS:-$(tmux display-message -p '#{session_windows}' 2>/dev/null || printf '0')}"
    [[ "$windows" =~ ^[0-9]+$ ]] || windows=0
    if ((width > 0 && windows > 0)); then
        tab_budget=$(( (width - 60) / windows ))
    else
        tab_budget=999
    fi

    if ((tab_budget < 8)); then
        cpu=""
        mem=""
        gpu=""
        net=""
        disk=""
    elif ((tab_budget < 11)); then
        gpu=""
        net=""
        disk=""
    elif ((tab_budget < 14)); then
        net=""
        disk=""
    elif ((tab_budget < 17)); then
        net=""
    fi

    if ((width > 0 && width < 110)); then
        cpu=""
        mem=""
        gpu=""
        net=""
        disk=""
    elif ((width > 0 && width < 140)); then
        gpu=""
        net=""
        disk=""
    elif ((width > 0 && width < 170)); then
        net=""
        disk=""
    elif ((width > 0 && width < 200)); then
        net=""
    fi

    add_segment() {
        local color="$1"
        local text="$2"

        [[ -n "$text" ]] || return
        if ((first)); then
            first=0
        else
            printf '#[fg=%s]| ' brightblack
        fi
        segment "$color" "$text"
    }

    add_segment cyan "${cpu:+CPU:$cpu}"
    add_segment green "${mem:+MEM:$mem}"
    add_segment magenta "$gpu"
    add_segment brightblue "$net"
    add_segment yellow "$disk"
    add_segment blue "$now"
    add_segment brightcyan "$host"
}

main
