#!/bin/bash
val=""
if [ -f "/tmp/.g0dmax55_conky_remote_snmp_tx_rate" ]; then
    read -r val < "/tmp/.g0dmax55_conky_remote_snmp_tx_rate" 2>/dev/null
fi
val="${val//[!0-9]/}"
echo "${val:-0}"
