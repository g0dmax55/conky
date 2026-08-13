#!/bin/bash

# Reads the cached rates from the remote daemon and formats for Conky text output

CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"
CACHE_STATUS="/tmp/.g0dmax55_conky_remote_ssh_status"

STATUS=$(cat "$CACHE_STATUS" 2>/dev/null | tr -d '[:space:]')
if [ "$STATUS" = "CONNECTED" ]; then
    STATUS_TEXT="\${color3}CONNECTED"
elif [ "$STATUS" = "DISCONNECTED" ]; then
    STATUS_TEXT="\${color6}DISCONNECTED"
elif [ "$STATUS" = "WAITING" ]; then
    STATUS_TEXT="\${color4}WAITING"
else
    STATUS_TEXT="\${color6}OFFLINE"
fi

get_int() {
    local val
    val=$(cat "$1" 2>/dev/null | tr -dc '0-9')
    echo "${val:-0}"
}

RX_RATE=$(get_int "${CACHE_RX}_rate")
TX_RATE=$(get_int "${CACHE_TX}_rate")
RX_BYTES=$(get_int "${CACHE_RX}_total")
TX_BYTES=$(get_int "${CACHE_TX}_total")

# Format function
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

RX_RATE_STR=$(format_bytes "$RX_RATE")"/s"
TX_RATE_STR=$(format_bytes "$TX_RATE")"/s"
RX_TOTAL_STR=$(format_bytes "$RX_BYTES")
TX_TOTAL_STR=$(format_bytes "$TX_BYTES")

# Print Conky block
echo "\${voffset 5}"
echo "\${alignr}\${color1}SSH\${color} \${color6}[${STATUS_TEXT}\${color6}]\${color}"
echo "\${alignr}\${color1}REMOTE SSH DOWNLOAD\${color}"
echo "\${alignr}\${color6}[\${color2}${RX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/conky/g0dmax55-conky/scripts/ssh_remote_rx.sh 35,400 220044 9900FF -l -t}"
echo "\${voffset 3}"
echo "\${alignr}\${color1}REMOTE SSH UPLOAD\${color}"
echo "\${alignr}\${color6}[\${color2}${TX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${TX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/conky/g0dmax55-conky/scripts/ssh_remote_tx.sh 35,400 002200 00AA44 -l -t}"
