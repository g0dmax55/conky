#!/bin/bash

# Conky Colors (matching main conky theme):
# color6 = Red   - Tree structure & Brackets
# color2 = Cyan  - Values (IPs, domains, ports)
# color1 = Grey  - Labels & text

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

# FIXED SLOT COUNTS
TCP_SLOTS=23
UDP_SLOTS=4
LISTEN_SLOTS=14
ROUTE_SLOTS=6

# Empty slot line
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"

# Function to output exactly N lines - pads with empty lines if needed
output_fixed_lines() {
    local total=$1
    local count=0
    while IFS= read -r line; do
        echo "$line"
        count=$((count+1))
    done
    # Fill remaining with empty lines
    while [ $count -lt $total ]; do
        echo "$EMPTY"
        count=$((count+1))
    done
}

# 1. STATISTICS (optimized: single netstat call, cached)
echo "${C6}├─${CR} ${C6}[${C2}STATISTICS${C6}]${CR}"
# Cache netstat output to avoid multiple calls
NETSTAT_TN=$(netstat -tn 2>/dev/null)
TCP_EST=$(echo "$NETSTAT_TN" | grep -c ESTABLISHED)
TCP_WAIT=$(echo "$NETSTAT_TN" | grep -c TIME_WAIT)
TCP_LISTEN=$(netstat -tln 2>/dev/null | tail -n +3 | wc -l)
UDP_TOTAL=$(netstat -un 2>/dev/null | tail -n +3 | wc -l)
echo "${C6}│  ├─${CR} ${C1}established:${C6}[${C2}${TCP_EST}${C6}]${CR} ${C1}time_wait:${C6}[${C2}${TCP_WAIT}${C6}]${CR} ${C1}listening:${C6}[${C2}${TCP_LISTEN}${C6}]${CR} ${C1}udp_total:${C6}[${C2}${UDP_TOTAL}${C6}]${CR}"
echo "${C6}│${CR}"

# 2. ROUTING
echo "${C6}├─${CR} ${C6}[${C2}ROUTING${C6}]${CR}"
# Routing table
netstat -r 2>/dev/null | tail -n +3 | tail -n $ROUTE_SLOTS | while read dest gateway mask flags metric ref use iface; do
    [ -z "$dest" ] && continue
    printf "${C6}│  ├─${CR} ${C6}[${C2}%-15s${C6}]${CR}  ${C6}[${C2}%-15s${C6}]${CR}  ${C6}[${C2}%s${C6}]${CR}\n" \
        "$dest" "$gateway" "$iface"
done | output_fixed_lines $ROUTE_SLOTS
echo "${C6}│${CR}"

# 3. ACTIVE_CONNECTIONS
echo "${C6}├─${CR} ${C6}[${C2}ACTIVE_CONNECTIONS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-5s %-5s %-27s %-52s %s${CR}\n" "Proto" "R-Q" "S-Q" "Local Address" "Foreign Address" "State"
# TCP connections - process and pad to exactly TCP_SLOTS lines
netstat -Wt 2>/dev/null | tail -n +3 | tail -n $TCP_SLOTS | while read proto recvq sendq local foreign state; do
    [ -z "$proto" ] && continue
    printf "${C6}│  ├─${CR} ${C6}[${C2}%-4s${C6}]${CR} ${C6}[${C2}%3s${C6}]${CR} ${C6}[${C2}%3s${C6}]${CR} ${C6}[${C2}%-25.25s${C6}]${CR} ${C6}[${C2}%-50.50s${C6}]${CR} ${C6}[${C1}%s${C6}]${CR}\n" \
        "$proto" "$recvq" "$sendq" "$local" "$foreign" "$state"
done | output_fixed_lines $TCP_SLOTS
echo "${C6}│${CR}"

# 4. UDP_CONNECTIONS
echo "${C6}├─${CR} ${C6}[${C2}UDP_CONNECTIONS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-5s %-5s %-27s %-27s %s${CR}\n" "Proto" "R-Q" "S-Q" "Local Address" "Foreign Address" "State"
# UDP connections
netstat -un 2>/dev/null | tail -n +3 | tail -n $UDP_SLOTS | while read proto recvq sendq local foreign state; do
    [ -z "$proto" ] && continue
    printf "${C6}│  ├─${CR} ${C6}[${C2}%-4s${C6}]${CR} ${C6}[${C2}%3s${C6}]${CR} ${C6}[${C2}%3s${C6}]${CR} ${C6}[${C2}%-25s${C6}]${CR} ${C6}[${C2}%-25s${C6}]${CR} ${C6}[${C1}%s${C6}]${CR}\n" \
        "$proto" "$recvq" "$sendq" "$local" "$foreign" "${state:-ESTABLISHED}"
done | output_fixed_lines $UDP_SLOTS
echo "${C6}│${CR}"

# 5. LISTENING_PORTS
echo "${C6}├─${CR} ${C6}[${C2}LISTENING_PORTS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-7s %-17s %s${CR}\n" "Proto" "Port" "Address" "Program"
# Listening sockets - use ss for full program names
ss -tlnp 2>/dev/null | tail -n +2 | tail -n $LISTEN_SLOTS | while read state recvq sendq local peer process; do
    [ -z "$state" ] && continue
    # Extract port and address
    port=$(echo "$local" | rev | cut -d: -f1 | rev)
    addr=$(echo "$local" | rev | cut -d: -f2- | rev)
    [ "$addr" = "*" ] && addr="0.0.0.0"
    [ "$addr" = "[::]" ] && addr="::"
    prog=$(echo "$process" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
    [ -z "$prog" ] && prog="-"
    printf "${C6}│  ├─${CR} ${C6}[${C2}%-4s${C6}]${CR} ${C6}[${C2}%5s${C6}]${CR} ${C6}[${C2}%-15s${C6}]${CR} ${C6}[${C1}%s${C6}]${CR}\n" "tcp" "$port" "$addr" "$prog"
done | output_fixed_lines $LISTEN_SLOTS

echo "${C6}└─${CR}"
