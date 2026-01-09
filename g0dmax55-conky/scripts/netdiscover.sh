#!/bin/bash

# Network Discovery Script using netdiscover/arp-scan
# Shows devices on LAN with MAC vendor info

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

# Try arp-scan first (faster, also needs sudo but can be set NOPASSWD)
# Fall back to arp cache with MAC vendor lookup
{
    # Try netdiscover first
    OUTPUT=""
    if command -v netdiscover &> /dev/null; then
         # Try to run netdiscover. 
         # We use a timeout to prevent hanging if it waits for something
         # and we check if it produces any output.
         # 2>/dev/null to suppress stderr (password prompts etc) which would ruin conky parsing
         OUTPUT=$(timeout 5s sudo -n netdiscover -i "$IFACE" -r "$SUBNET" -P -N 2>/dev/null)
    fi

    if [ -n "$OUTPUT" ]; then
        echo "$OUTPUT" | grep -E '^[ 0-9]+\.' | head -n $DEVICE_SLOTS | while read ip mac count len vendor; do
            [ -z "$ip" ] && continue
            vendor=${vendor:-"Unknown"}
            # Raw data with whitespace trimming AND collapsing multiple spaces (plus TABS)
            vendor=$(echo "$vendor" | tr '\t' ' ' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # If vendor matches MAC address pattern, set to Unknown
            if [[ "$vendor" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                vendor="Unknown"
            fi
            
            # Smart truncation: if longer than 45 chars, truncate with ...
            if [ ${#vendor} -gt 45 ]; then
                vendor="${vendor:0:42}..."
            fi
            printf "${C6}│  ├─${CR} ${C6}[${C2}%-15s${C6}]${CR} ${C6}[${C2}%-17s${C6}]${CR} ${C6}[${C1}%-45s${C6}]${CR}\n" \
                "$ip" "$mac" "$vendor"
        done
    else
        # Fall back to ARP cache
        arp -an -i "$IFACE" 2>/dev/null | grep -v incomplete | while read line; do
            ip=$(echo "$line" | grep -oP '\(\K[^)]+')
            mac=$(echo "$line" | awk '{print $4}')
            [ -z "$ip" ] && continue
            [ "$mac" = "<incomplete>" ] && continue
            
            # Try to get vendor from MAC (first 3 octets)
            vendor=$(grep -i "^${mac:0:8}" /usr/share/arp-scan/ieee-oui.txt 2>/dev/null | cut -f2 || echo "-")
            [ -z "$vendor" ] && vendor="-"
            # Raw data with whitespace trimming AND collapsing multiple spaces (plus TABS)
            vendor=$(echo "$vendor" | tr '\t' ' ' | tr -s ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            
            # If vendor matches MAC address pattern, set to Unknown
            if [[ "$vendor" =~ ^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$ ]]; then
                vendor="Unknown"
            fi
            
            # Smart truncation: if longer than 45 chars, truncate with ...
            if [ ${#vendor} -gt 45 ]; then
                vendor="${vendor:0:42}..."
            fi
            printf "${C6}│  ├─${CR} ${C6}[${C2}%-15s${C6}]${CR} ${C6}[${C2}%-17s${C6}]${CR} ${C6}[${C1}%-45s${C6}]${CR}\n" \
                "$ip" "$mac" "$vendor"
        done
    fi
} | head -n $DEVICE_SLOTS | output_fixed_lines $DEVICE_SLOTS

echo "${C6}└─${CR}"
