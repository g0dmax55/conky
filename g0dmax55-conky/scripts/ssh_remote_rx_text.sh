#!/bin/bash
CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
get_int() {
    local val
    val=$(cat "$1" 2>/dev/null | tr -dc '0-9')
    echo "${val:-0}"
}
format_bytes() {
    local bytes=$1
    if [ "$bytes" -ge 1073741824 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.2f GB", b/1073741824}'
    elif [ "$bytes" -ge 1048576 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f MB", b/1048576}'
    elif [ "$bytes" -ge 1024 ]; then
        awk -v b="$bytes" 'BEGIN {printf "%.1f KB", b/1024}'
    else
        echo "${bytes} B"
    fi
}
RX_RATE=$(get_int "${CACHE_RX}_rate")
RX_BYTES=$(get_int "${CACHE_RX}_total")
RX_RATE_STR=$(format_bytes "$RX_RATE")"/s"
RX_TOTAL_STR=$(format_bytes "$RX_BYTES")

echo "\${color6}[\${color2}${RX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
