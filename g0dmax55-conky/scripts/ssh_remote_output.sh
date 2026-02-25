#!/bin/bash

# Reads the cached rates from the remote daemon and formats for Conky text output

CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"

RX_RATE=$(cat "${CACHE_RX}_rate" 2>/dev/null || echo 0)
TX_RATE=$(cat "${CACHE_TX}_rate" 2>/dev/null || echo 0)
RX_BYTES=$(cat "${CACHE_RX}_total" 2>/dev/null || echo 0)
TX_BYTES=$(cat "${CACHE_TX}_total" 2>/dev/null || echo 0)

# Format function
format_bytes() {
    local bytes=$1
    if [ "$bytes" -lt 1000 ]; then
        echo "${bytes} B"
    elif [ "$bytes" -lt 1000000 ]; then
        echo "$((bytes / 1000)) KB"
    elif [ "$bytes" -lt 1000000000 ]; then
        echo "$((bytes / 1000000)) MB"
    else
        echo "$((bytes / 1000000000)) GB"
    fi
}

RX_RATE_STR=$(format_bytes $RX_RATE)"/s"
TX_RATE_STR=$(format_bytes $TX_RATE)"/s"
RX_TOTAL_STR=$(format_bytes $RX_BYTES)
TX_TOTAL_STR=$(format_bytes $TX_BYTES)

# Print Conky block
echo "\${voffset 5}"
echo "\${alignr}\${color1}REMOTE SSH DOWNLOAD\${color}"
echo "\${alignr}\${color6}[\${color2}${RX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/Desktop/conky/g0dmax55-conky/scripts/ssh_remote_rx.sh 35,400 440000 FF0000 100 -l -t}"
echo "\${voffset 3}"
echo "\${alignr}\${color1}REMOTE SSH UPLOAD\${color}"
echo "\${alignr}\${color6}[\${color2}${TX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${TX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/Desktop/conky/g0dmax55-conky/scripts/ssh_remote_tx.sh 35,400 440000 FF0000 100 -l -t}"
