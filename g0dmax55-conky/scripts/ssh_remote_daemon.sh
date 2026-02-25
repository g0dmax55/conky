#!/bin/bash

# ==========================================
# SSH Server Configuration
# ==========================================
SERVER_IP="REDACTED"      # Replace with your server IP
USERNAME="root"                # Replace with your username
PASSWORD="REDACTED"       # Replace with your password
INTERFACE="eth0"               # Replace with your remote server's active network interface (e.g., eth0, ens33)
UPDATE_INTERVAL=1             # How often to check in seconds
# ==========================================

# Files to store rates for Conky to read
CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"

OLD_RX=0
OLD_TX=0
OLD_TIME=$(date +%s%3N)

while true; do
    # Open a persistent SSH stream to fetch statistics every second without re-authenticating
    CMD="while true; do cat /sys/class/net/$INTERFACE/statistics/rx_bytes /sys/class/net/$INTERFACE/statistics/tx_bytes; sleep $UPDATE_INTERVAL; done"
    
    if command -v sshpass &>/dev/null; then
        EXEC_SSH=(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=5 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP")
    else
        EXEC_SSH=(ssh -o ConnectTimeout=5 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP")
    fi

    # Execute stream and parse line by line
    "${EXEC_SSH[@]}" "$CMD" 2>/dev/null | while read -r RX_BYTES && read -r TX_BYTES; do
        NOW_MS=$(date +%s%3N)
        
        # Clean the input to ensure integers only
        RX_BYTES=$(echo "$RX_BYTES" | tr -dc '0-9')
        TX_BYTES=$(echo "$TX_BYTES" | tr -dc '0-9')
        
        if [[ "$RX_BYTES" =~ ^[0-9]+$ ]] && [[ "$TX_BYTES" =~ ^[0-9]+$ ]]; then
            TIME_DIFF_MS=$((NOW_MS - OLD_TIME))
            
            if [ "$TIME_DIFF_MS" -gt 0 ] && [ "$OLD_RX" -gt 0 ]; then
                RX_RATE=$(( (RX_BYTES - OLD_RX) * 1000 / TIME_DIFF_MS ))
                TX_RATE=$(( (TX_BYTES - OLD_TX) * 1000 / TIME_DIFF_MS ))
                
                # Format checks
                if [ "$RX_RATE" -lt 0 ]; then RX_RATE=0; fi
                if [ "$TX_RATE" -lt 0 ]; then TX_RATE=0; fi
                
                # Scale graphs (Max: 10KB/s — makes idle SSH traffic visible)
                MAX_BW=10000
                RX_PCT=$(( RX_RATE * 100 / MAX_BW ))
                TX_PCT=$(( TX_RATE * 100 / MAX_BW ))
                
                if [ "$RX_PCT" -gt 100 ]; then RX_PCT=100; fi
                if [ "$TX_PCT" -gt 100 ]; then TX_PCT=100; fi
                
                # Write to caches for Conky
                echo "$RX_PCT" > "$CACHE_RX"
                echo "$TX_PCT" > "$CACHE_TX"
                
                echo "$RX_RATE" > "${CACHE_RX}_rate"
                echo "$TX_RATE" > "${CACHE_TX}_rate"
                echo "$RX_BYTES" > "${CACHE_RX}_total"
                echo "$TX_BYTES" > "${CACHE_TX}_total"
            fi
            
            OLD_RX=$RX_BYTES
            OLD_TX=$TX_BYTES
            OLD_TIME=$NOW_MS
        fi
    done

    # If stream breaks or disconnects, reset values to zero
    echo "0" > "$CACHE_RX"
    echo "0" > "$CACHE_TX"
    echo "0" > "${CACHE_RX}_rate"
    echo "0" > "${CACHE_TX}_rate"
    
    # Wait before attempting to reconnect
    sleep 2
done
