#!/bin/bash
CACHE_RX="/tmp/.g0dmax55_conky_remote_snmp_rx_rate"

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

RX_RATE=$(get_int "${CACHE_RX}_rate")
RX_MAX=$(get_int "${CACHE_RX}_max")
RX_BYTES=$(get_int "${CACHE_RX}_total")
RX_TREND=$(get_str "${CACHE_RX}_trend")
RX_RATE_STR="$(format_bytes "$RX_RATE")/s"
RX_MAX_STR="$(format_bytes "$RX_MAX")/s"
RX_TOTAL_STR="$(format_bytes "$RX_BYTES")"

if [ -n "$RX_TREND" ]; then
    echo "\${color6}[\${color2}${RX_RATE_STR} ${RX_TREND}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color1}max \${color2}${RX_MAX_STR}\${color6}]\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
else
    echo "\${color6}[\${color2}${RX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color1}max \${color2}${RX_MAX_STR}\${color6}]\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
fi
