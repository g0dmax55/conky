#!/bin/bash
# Captures live packets using tshark
# Priorities: DNS Queries, then HTTP/HTTPS, then others.

# Check which interface is up
IFACE="wlan0"
if [ ! -d "/sys/class/net/wlan0" ] || [ "$(cat /sys/class/net/wlan0/operstate)" != "up" ]; then
    IFACE="eth0"
fi

# Capture packets
# We capture: IP Src, Proto, DNS Query Name, Info
tshark -i $IFACE -c 15 -a duration:1 -T fields -e ip.src -e _ws.col.Protocol -e dns.qry.name -e _ws.col.Info 2>/dev/null | head -n 10 | awk -F'\t' '{
    src=$1
    proto=$2
    dns_query=$3
    info=$4
    
    if (src == "") next

    # If it is a DNS query, show the domain nicely
    if (dns_query != "") {
        # Truncate if too long
        if (length(dns_query) > 35) dns_query = substr(dns_query, 1, 32) "..."
        printf "%-15s [DNS] %s\n", src, dns_query
    } 
    else {
        # For non-DNS, show Proto and Info (truncated)
        if (length(info) > 40) info = substr(info, 1, 37) "..."
        printf "%-15s [%s] %s\n", src, proto, info
    }
}'

# Fill empty lines
# (Conky handles this usually, but safe to keep script consistent)
