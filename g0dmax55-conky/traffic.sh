#!/bin/bash
# Captures live packets using tshark
# Format: Source -> Destination [Protocol] Info
# Captures ALL traffic (DNS, TCP, UDP, etc.)

# Check which interface is up
IFACE="wlan0"
if [ ! -d "/sys/class/net/wlan0" ] || [ "$(cat /sys/class/net/wlan0/operstate)" != "up" ]; then
    IFACE="eth0"
fi

# Run tshark capture
# -i: interface
# -c: stop after 5 packets
# -a duration:1 : stop after 1 second
# -f "": No capture filter (capture everything)
# -T fields ... : Output specific fields
# 2>/dev/null to hide capture stderr info

# Note: We output Src, Dst, Proto, and Info (Info gives details like "Standard Query A google.com")
tshark -i $IFACE -c 5 -a duration:1 -T fields -e ip.src -e ip.dst -e _ws.col.Protocol -e _ws.col.Info 2>/dev/null | head -n 5 | awk -F'\t' '{
    src=$1
    dst=$2
    proto=$3
    info=$4
    
    # Skip empty lines
    if (src == "") next
    
    # Truncate Info if too long
    if (length(info) > 30) info = substr(info, 1, 27) "..."

    printf "%-13s -> %-13s [%s] %s\n", src, dst, proto, info
}'

# Fill empty lines if no traffic captured
# We simply count lines output so far to pad
# This is handled by Conky usually, but good for testing
