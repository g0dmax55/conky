#!/bin/bash
STATUS=$(cat /tmp/.g0dmax55_conky_remote_ssh_status 2>/dev/null | tr -d '[:space:]')
if [ "$STATUS" = "CONNECTED" ]; then
    echo "\${color6}[\${color3}CONNECTED\${color6}]\${color}"
elif [ "$STATUS" = "DISCONNECTED" ]; then
    echo "\${color6}[\${color6}DISCONNECTED\${color6}]\${color}"
elif [ "$STATUS" = "WAITING" ]; then
    echo "\${color6}[\${color4}WAITING\${color6}]\${color}"
else
    echo "\${color6}[\${color6}OFFLINE\${color6}]\${color}"
fi
