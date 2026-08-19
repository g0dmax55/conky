#!/bin/bash
CACHE_TX="/tmp/.g0dmax55_conky_remote_snmp_tx_rate"

get_int() {
    local val=""
    if [ -f "$1" ]; then
        read -r val < "$1" 2>/dev/null
    fi
    val="${val//[!0-9]/}"
    echo "${val:-0}"
}

get_str() {
    local val=""
    if [ -f "$1" ]; then
        read -r val < "$1" 2>/dev/null
    fi
    echo "$val"
}

format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" -le 0 ] 2>/dev/null; then
        echo "0 B"
    elif [ "$bytes" -ge 1073741824 ]; then
        local gb=$(( bytes / 1073741824 ))
        local rem=$(( (bytes % 1073741824) * 100 / 1073741824 ))
        printf "%d.%02d GB" "$gb" "$rem"
    elif [ "$bytes" -ge 1048576 ]; then
        local mb=$(( bytes / 1048576 ))
        local rem=$(( (bytes % 1048576) * 10 / 1048576 ))
        printf "%d.%d MB" "$mb" "$rem"
    elif [ "$bytes" -ge 1024 ]; then
        local kb=$(( bytes / 1024 ))
        local rem=$(( (bytes % 1024) * 10 / 1024 ))
        printf "%d.%d KB" "$kb" "$rem"
    else
        printf "%d B" "$bytes"
    fi
}

TX_RATE=$(get_int "${CACHE_TX}_rate")
TX_BYTES=$(get_int "${CACHE_TX}_total")
TX_TREND=$(get_str "${CACHE_TX}_trend")
TX_RATE_STR="$(format_bytes "$TX_RATE")/s"
TX_TOTAL_STR="$(format_bytes "$TX_BYTES")"

if [ -n "$TX_TREND" ]; then
    echo "\${color3}[\${color3}${TX_RATE_STR} ${TX_TREND}\${color3}]\${color} \${color1}speed\${color} \${color3}[\${color3}${TX_TOTAL_STR}\${color3}]\${color} \${color1}total\${color}"
else
    echo "\${color3}[\${color3}${TX_RATE_STR}\${color3}]\${color} \${color1}speed\${color} \${color3}[\${color3}${TX_TOTAL_STR}\${color3}]\${color} \${color1}total\${color}"
fi
