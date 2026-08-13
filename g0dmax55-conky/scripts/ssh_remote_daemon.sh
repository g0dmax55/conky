#!/bin/bash

# ==========================================
# SSH Server Configuration — loaded from .ssh_env
# ==========================================
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.ssh_env" ]; then
    source "$SCRIPT_DIR/.ssh_env"
fi
UPDATE_INTERVAL=1             # How often to check in seconds
# ==========================================

# Files to store rates for Conky to read
CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"
CACHE_STATUS="/tmp/.g0dmax55_conky_remote_ssh_status"

init_cache() {
    echo "OFFLINE" > "$CACHE_STATUS"
    echo "0" > "$CACHE_RX"
    echo "0" > "$CACHE_TX"
    echo "0" > "${CACHE_RX}_rate"
    echo "0" > "${CACHE_TX}_rate"
    echo "0" > "${CACHE_RX}_total"
    echo "0" > "${CACHE_TX}_total"
}

OLD_RX=0
OLD_TX=0
OLD_TIME=$(date +%s%3N)

while true; do
    # Reload environment if present
    if [ -f "$SCRIPT_DIR/.ssh_env" ]; then
        source "$SCRIPT_DIR/.ssh_env"
    fi

    # Check if server IP and username are configured
    if [ -z "$SERVER_IP" ] || [ -z "$USERNAME" ]; then
        init_cache
        sleep 5
        continue
    fi

    local_interface="${INTERFACE:-eth0}"

    # Open a persistent SSH stream to fetch statistics every second without re-authenticating
    CMD="while true; do cat /sys/class/net/$local_interface/statistics/rx_bytes /sys/class/net/$local_interface/statistics/tx_bytes; sleep $UPDATE_INTERVAL; done"
    
    if [ -n "$PASSWORD" ] && command -v sshpass &>/dev/null; then
        EXEC_SSH=(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=5 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP")
    else
        EXEC_SSH=(ssh -o ConnectTimeout=5 -o ServerAliveInterval=10 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP")
    fi

    # Execute stream and parse line by line
    echo "CONNECTED" > "$CACHE_STATUS"
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
                
                # Auto-scale: track peak rate, use it as ceiling (min floor: 1KB/s)
                PEAK_RATE=${PEAK_RATE:-1000}
                if [ "$RX_RATE" -gt "$PEAK_RATE" ]; then PEAK_RATE=$RX_RATE; fi
                if [ "$TX_RATE" -gt "$PEAK_RATE" ]; then PEAK_RATE=$TX_RATE; fi

                # Slowly decay peak so graph adapts to quieter periods
                DECAY_COUNT=${DECAY_COUNT:-0}
                DECAY_COUNT=$((DECAY_COUNT + 1))
                if [ "$DECAY_COUNT" -ge 30 ]; then
                    PEAK_RATE=$(( PEAK_RATE * 90 / 100 ))
                    if [ "$PEAK_RATE" -lt 1000 ]; then PEAK_RATE=1000; fi
                    DECAY_COUNT=0
                fi

                RX_PCT=$(( RX_RATE * 100 / PEAK_RATE ))
                TX_PCT=$(( TX_RATE * 100 / PEAK_RATE ))
                
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
    echo "DISCONNECTED" > "$CACHE_STATUS"
    echo "0" > "$CACHE_RX"
    echo "0" > "$CACHE_TX"
    echo "0" > "${CACHE_RX}_rate"
    echo "0" > "${CACHE_TX}_rate"
    
    # Wait before attempting to reconnect
    sleep 2
done
