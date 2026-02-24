#!/bin/bash

# ==========================================
# SSH Server Configuration
# ==========================================
SERVER_IP="REDACTED"      # Replace with your server IP
USERNAME=""                # Replace with your username
PASSWORD=""       # Replace with your password
INTERFACE="eth0"               # Replace with your remote server's active network interface (e.g., eth0, ens33)
UPDATE_INTERVAL=2              # How often to check in seconds
# ==========================================

# Files to store rates for Conky to read
CACHE_RX="/tmp/.g0dmax55_conky_remote_ssh_rx_rate"
CACHE_TX="/tmp/.g0dmax55_conky_remote_ssh_tx_rate"

OLD_RX=0
OLD_TX=0
OLD_TIME=$(date +%s%3N)

while true; do
    # Fetch RX and TX bytes from the remote server
    # We read /sys/class/net/$INTERFACE/statistics/rx_bytes and tx_bytes
    if command -v sshpass &>/dev/null; then
        # We redirect stderr to dev/null so warnings like "Could not chdir to home directory" do not corrupt stdout
        STATS=$(sshpass -p "$PASSWORD" ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" "cat /sys/class/net/$INTERFACE/statistics/rx_bytes /sys/class/net/$INTERFACE/statistics/tx_bytes" 2>/dev/null)
    else
        STATS=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$USERNAME@$SERVER_IP" "cat /sys/class/net/$INTERFACE/statistics/rx_bytes /sys/class/net/$INTERFACE/statistics/tx_bytes" 2>/dev/null)
    fi

    NOW_MS=$(date +%s%3N)

    if [ -n "$STATS" ]; then
        RX_BYTES=$(echo "$STATS" | sed -n '1p' | tr -dc '0-9')
        TX_BYTES=$(echo "$STATS" | sed -n '2p' | tr -dc '0-9')
        
        # Ensure they are numbers
        if [[ "$RX_BYTES" =~ ^[0-9]+$ ]] && [[ "$TX_BYTES" =~ ^[0-9]+$ ]]; then
            TIME_DIFF_MS=$((NOW_MS - OLD_TIME))
            
            if [ "$TIME_DIFF_MS" -gt 0 ] && [ "$OLD_RX" -gt 0 ]; then
                RX_RATE=$(( (RX_BYTES - OLD_RX) * 1000 / TIME_DIFF_MS ))
                TX_RATE=$(( (TX_BYTES - OLD_TX) * 1000 / TIME_DIFF_MS ))
                
                # Handle potential wrap-around or interface resets
                if [ "$RX_RATE" -lt 0 ]; then RX_RATE=0; fi
                if [ "$TX_RATE" -lt 0 ]; then TX_RATE=0; fi
                
                # Save raw rates for the graph
                echo "$RX_RATE" > "$CACHE_RX"
                echo "$TX_RATE" > "$CACHE_TX"
                
                # Also save the raw totals for text display
                echo "$RX_BYTES" > "${CACHE_RX}_total"
                echo "$TX_BYTES" > "${CACHE_TX}_total"
            fi
            
            OLD_RX=$RX_BYTES
            OLD_TX=$TX_BYTES
        fi
    else
        # If connection fails, output 0 rate to drop the graph to zero
        echo "0" > "$CACHE_RX"
        echo "0" > "$CACHE_TX"
    fi
    
    OLD_TIME=$NOW_MS
    sleep $UPDATE_INTERVAL
done
