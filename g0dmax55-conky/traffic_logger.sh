#!/bin/bash
# Continuous Traffic Logger for Conky
# Captures ALL packets + detailed DNS info

LOG_FILE="/tmp/conky_traffic.log"
: > "$LOG_FILE"

# Auto-detect interface
IFACE="wlan0"
if [ ! -d "/sys/class/net/wlan0" ] || [ "$(cat /sys/class/net/wlan0/operstate)" != "up" ]; then
    IFACE="eth0"
fi

# Function to clean up on exit
cleanup() {
    kill $(jobs -p) 2>/dev/null
    exit
}
trap cleanup SIGINT SIGTERM

# Maximum line length
MAX_LEN=140

# Capture all traffic with DNS details
tshark -i "$IFACE" -l -t ad -T fields \
    -e frame.time \
    -e ip.src \
    -e ip.dst \
    -e _ws.col.Protocol \
    -e dns.qry.name \
    -e dns.qry.type \
    -e dns.flags.response \
    -e dns.a \
    -e _ws.col.Info \
    2>/dev/null | \
while IFS=$'\t' read -r timestamp src dst proto dns_name qry_type is_response dns_ip info; do
    # Skip empty source
    [ -z "$src" ] && continue
    
    # Extract time
    time_part=$(echo "$timestamp" | sed 's/.*T//' | cut -c1-12)
    
    # Check if DNS
    if [ -n "$dns_name" ]; then
        # DNS packet - show detailed info
        case "$qry_type" in
            1) type_name="A" ;;
            28) type_name="AAAA" ;;
            5) type_name="CNAME" ;;
            65) type_name="HTTPS" ;;
            *) type_name="DNS" ;;
        esac
        
        if [ "$is_response" = "1" ] && [ -n "$dns_ip" ]; then
            line=$(printf "[%s] %-15s [%-5s] %s => %s" "$time_part" "$src" "$type_name" "$dns_name" "$dns_ip")
        elif [ "$is_response" = "1" ]; then
            line=$(printf "[%s] %-15s [%-5s] %s (OK)" "$time_part" "$src" "$type_name" "$dns_name")
        else
            line=$(printf "[%s] %-15s [%-5s] %s ?" "$time_part" "$src" "$type_name" "$dns_name")
        fi
    else
        # Other packet - show protocol and brief info
        # Compress info
        short_info=$(echo "$info" | tr -s ' ' | cut -c1-60)
        line=$(printf "[%s] %-15s -> %-15s [%-5s] %s" "$time_part" "$src" "$dst" "$proto" "$short_info")
    fi
    
    # Truncate
    if [ ${#line} -gt $MAX_LEN ]; then
        line="${line:0:$((MAX_LEN-3))}..."
    fi
    
    echo "$line" >> "$LOG_FILE"
    
    # Keep log manageable
    if [ $(wc -l < "$LOG_FILE") -gt 100 ]; then
        tail -n 50 "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
done
