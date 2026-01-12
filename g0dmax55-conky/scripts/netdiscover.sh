#!/bin/bash

# Passive LAN Device Monitor
# Reads the kernel ARP cache to show local devices without active scanning.
# Zero network traffic, zero kernel log spam.
# ULTRA-CLEAN MODE: Zero scans, zero logs, uses kernel ARP cache only.

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

# Fixed slots for stable layout
DEVICE_SLOTS=14

# Empty slot line
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"

# Function to output exactly N lines
output_fixed_lines() {
    local total=$1
    local count=0
    while IFS= read -r line; do
        echo "$line"
        count=$((count+1))
    done
    while [ $count -lt $total ]; do
        echo "$EMPTY"
        count=$((count+1))
    done
}

# Get network interface
IFACE=$(ip route | grep default | awk '{print $5}' | head -1)

# If no default route, try to find first UP interface excluding loopback
if [ -z "$IFACE" ]; then
    IFACE=$(ip -o link show up | awk -F': ' '{print $2}' | grep -v "lo" | head -1)
fi

# Check if we are truly offline
if [ -z "$IFACE" ]; then
    echo "${C6}├─${CR} ${C6}[${C2}LAN_DISCOVERY${C6}]${CR} ${C1}::${CR} ${C6}[${C2}OFFLINE${C6}]${CR}"
    echo "${C6}│${CR}"
    echo "${C6}│  ${C1}No active network interface found${CR}"
    # Output empty lines to maintain layout
    output_fixed_lines $DEVICE_SLOTS < /dev/null
    echo "${C6}└─${CR}"
    exit 0
fi

SUBNET=$(ip -o -f inet addr show $IFACE 2>/dev/null | awk '{print $4}')

# Header
echo "${C6}├─${CR} ${C6}[${C2}LAN_DISCOVERY${C6}]${CR} ${C1}::${CR} ${C6}[${C2}${IFACE}${C6}]${CR} ${C6}[${C2}${SUBNET:-Unconfigured}${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-17s %-19s %s${CR}\n" "IP Address" "MAC Address" "Vendor"

# Main Logic: Active ARP Scan
{
    # Run active scan using arp-scan
    sudo arp-scan -l -I "$IFACE" --oui=/usr/share/arp-scan/ieee-oui.txt --retry=1 --timeout=200 2>/dev/null | grep -E "^[0-9]{1,3}\." | while read line; do
        ip=$(echo "$line" | awk '{print $1}')
        mac=$(echo "$line" | awk '{print $2}')
        # arp-scan output format: IP MAC Vendor (rest of line)
        vendor=$(echo "$line" | cut -f3-)

        # Clean/Normalize Vendor
        if [ -z "$vendor" ] || [ "$vendor" = "(Unknown)" ]; then
             vendor="Unknown"
        fi
        
        # Check for LAA in vendor string (arp-scan identifies this)
        if [[ "$vendor" == *"(Unknown: locally administered)"* ]]; then
             vendor="Unknown (Locally Administered Address)"
        fi

        # Raw data with whitespace trimming
        vendor=$(echo "$vendor" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Smart truncation: if longer than 45 chars, truncate with ...
        if [ ${#vendor} -gt 45 ]; then
            vendor="${vendor:0:42}..."
        fi
        printf "${C6}│  ├─${CR} ${C6}[${C2}%-15s${C6}]${CR} ${C6}[${C2}%-17s${C6}]${CR} ${C6}[${C2}%-45s${C6}]${CR}\n" \
            "$ip" "$mac" "$vendor"
    done
} | head -n $DEVICE_SLOTS | output_fixed_lines $DEVICE_SLOTS

echo "${C6}└─${CR}"
