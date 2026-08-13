#!/bin/bash
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"
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
TX_RATE=$(get_int "${CACHE_TX}_rate")
TX_BYTES=$(get_int "${CACHE_TX}_total")
TX_RATE_STR=$(format_bytes "$TX_RATE")"/s"
TX_TOTAL_STR=$(format_bytes "$TX_BYTES")

echo "\${color6}[\${color2}${TX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${TX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
