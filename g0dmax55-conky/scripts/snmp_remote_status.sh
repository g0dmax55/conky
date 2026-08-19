#!/bin/bash
STATUS="OFFLINE"
if [ -f "/tmp/.g0dmax55_conky_remote_snmp_status" ]; then
    read -r STATUS < "/tmp/.g0dmax55_conky_remote_snmp_status" 2>/dev/null
fi
STATUS="${STATUS//[[:space:]]/}"

case "$STATUS" in
    "CONNECTED")
        echo "\${color6}[\${color3}CONNECTED\${color6}]\${color}"
        ;;
    "CONNECTING"|"RECONNECTING")
        echo "\${color6}[\${color4}RECONNECTING\${color6}]\${color}"
        ;;
    "NO_INTERNET")
        echo "\${color6}[\${color6}NO INTERNET\${color6}]\${color}"
        ;;
    "DISCONNECTED")
        echo "\${color6}[\${color6}DISCONNECTED\${color6}]\${color}"
        ;;
    *)
        echo "\${color6}[\${color6}OFFLINE\${color6}]\${color}"
        ;;
esac
