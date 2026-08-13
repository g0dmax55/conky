#!/bin/bash

# Cache file to store previous values
CACHE_FILE="/tmp/.g0dmax55_conky_ssh_bw.cache"

# Get current stats from ss
# We look for connections on port 22 (SSH)
STATS=$(ss -itn '( sport = :22 or dport = :22 )')

# Sum up bytes
RX_BYTES=$(echo "$STATS" | grep -oP 'bytes_received:\K\d+' | awk '{s+=$1} END {print s+0}')
TX_BYTES=$(echo "$STATS" | grep -oP 'bytes_sent:\K\d+' | awk '{s+=$1} END {print s+0}')
CONNECTIONS=$(echo "$STATS" | grep -c ESTAB)

# If no connections, they are 0
if [ -z "$RX_BYTES" ]; then RX_BYTES=0; fi
if [ -z "$TX_BYTES" ]; then TX_BYTES=0; fi

NOW_MS=$(date +%s%3N)

if [ -f "$CACHE_FILE" ]; then
    read OLD_TIME OLD_RX OLD_TX < "$CACHE_FILE"
    
    TIME_DIFF_MS=$((NOW_MS - OLD_TIME))
    if [ "$TIME_DIFF_MS" -gt 0 ]; then
        # Rate per second = (bytes * 1000) / diff_ms
        RX_RATE=$(( (RX_BYTES - OLD_RX) * 1000 / TIME_DIFF_MS ))
        TX_RATE=$(( (TX_BYTES - OLD_TX) * 1000 / TIME_DIFF_MS ))
    else
        RX_RATE=0
        TX_RATE=0
    fi
    
    # Handle negative rates (connections closed/reset)
    if [ "$RX_RATE" -lt 0 ]; then RX_RATE=$RX_BYTES; fi
    if [ "$TX_RATE" -lt 0 ]; then TX_RATE=$TX_BYTES; fi
else
    RX_RATE=0
    TX_RATE=0
fi

echo "$NOW_MS $RX_BYTES $TX_BYTES" > "$CACHE_FILE"

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

echo "$RX_RATE" > /tmp/.g0dmax55_conky_ssh_rx_rate
echo "$TX_RATE" > /tmp/.g0dmax55_conky_ssh_tx_rate

echo "\${voffset 5}"
echo "\${alignr}\${color1}SSH SERVER DOWNLOAD (\${color2}${CONNECTIONS}\${color1} CONNs)\${color}"
echo "\${alignr}\${color6}[\${color2}${RX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${RX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/conky/g0dmax55-conky/scripts/ssh_rx.sh 35,300 440000 FF0000 -l -t}"
echo "\${voffset 3}"
echo "\${alignr}\${color1}SSH SERVER UPLOAD\${color}"
echo "\${alignr}\${color6}[\${color2}${TX_RATE_STR}\${color6}]\${color} \${color1}speed\${color} \${color6}[\${color2}${TX_TOTAL_STR}\${color6}]\${color} \${color1}total\${color}"
echo "\${execgraph /home/g0dmax55/conky/g0dmax55-conky/scripts/ssh_tx.sh 35,300 440000 FF0000 -l -t}"
