#!/bin/bash
CACHE_STATUS="/tmp/.g0dmax55_conky_remote_snmp_status"
CACHE_APP="/tmp/.g0dmax55_conky_remote_snmp_tx_app"

STATUS="OFFLINE"
if [ -f "$CACHE_STATUS" ]; then
    read -r STATUS < "$CACHE_STATUS" 2>/dev/null
fi
STATUS="${STATUS//[[:space:]]/}"

if [ "$STATUS" != "CONNECTED" ]; then
    echo "\${color6}[\${color1}IFACE: \${color6}---\${color6}]\${color}"
    exit 0
fi

IFACE="eth0"
if [ -f "$CACHE_APP" ]; then
    read -r IFACE < "$CACHE_APP" 2>/dev/null
fi
IFACE="${IFACE//[[:space:]]/}"
IFACE="${IFACE:-"eth0"}"

# Truncate if longer than 18 characters
if [ "${#IFACE}" -gt 18 ]; then
    IFACE="${IFACE:0:17}…"
fi

if [ "$IFACE" = "---" ]; then
    echo "\${color6}[\${color1}IFACE: \${color1}---\${color6}]\${color}"
else
    echo "\${color6}[\${color1}IFACE: \${color2}${IFACE}\${color6}]\${color}"
fi
