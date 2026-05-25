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

disk_home() {
    df -h "$HOME" 2>/dev/null | awk 'NR == 2 {print "Disk:" $5 " " $4 " free"; exit}'
}

main() {
    local os cpu mem gpu disk now host

    os="$(uname -s)"
    case "$os" in
        Darwin)
            cpu="$(macos_cpu)"
            mem="$(macos_mem)"
            gpu=""
            ;;
        Linux)
            cpu="$(linux_cpu)"
            mem="$(linux_mem)"
            gpu="$(linux_gpu)"
            ;;
        *)
            cpu=""
            mem=""
            gpu=""
            ;;
    esac

    disk="$(disk_home)"
    now="$(date '+%Y-%m-%d %H:%M:%S')"
    host="$(hostname -s 2>/dev/null || hostname)"

    segment cyan "${cpu:+CPU:$cpu}"
    segment green "${mem:+MEM:$mem}"
    segment magenta "$gpu"
    segment yellow "$disk"
    segment blue "$now"
    segment brightcyan "$host"
}

main
