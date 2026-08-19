#!/bin/bash
CACHE_STATUS="/tmp/.g0dmax55_conky_remote_snmp_status"
CACHE_APP="/tmp/.g0dmax55_conky_remote_snmp_tx_app"

STATUS="OFFLINE"
if [ -f "$CACHE_STATUS" ]; then
    read -r STATUS < "$CACHE_STATUS" 2>/dev/null
fi
STATUS="${STATUS//[[:space:]]/}"

if [ "$STATUS" != "CONNECTED" ]; then
    echo "\${color6}[\${color1}PROGRAM: \${color6}---\${color6}]\${color}"
    exit 0
fi

APP="---"
if [ -f "$CACHE_APP" ]; then
    read -r APP < "$CACHE_APP" 2>/dev/null
fi
APP="${APP//[[:space:]]/}"
APP="${APP:-"---"}"

# Truncate if longer than 18 characters
if [ "${#APP}" -gt 18 ]; then
    APP="${APP:0:17}…"
fi

if [ "$APP" = "---" ]; then
    echo "\${color6}[\${color1}PROGRAM: \${color1}---\${color6}]\${color}"
else
    echo "\${color6}[\${color1}PROGRAM: \${color3}${APP}\${color6}]\${color}"
fi
