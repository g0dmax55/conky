#!/bin/bash
# Startup script for Conky Dashboard

# Kill existing processes
killall conky 2>/dev/null
pkill -f netstat_radar.sh 2>/dev/null
pkill -f system_updates.sh 2>/dev/null
pkill -f market_tracker.sh 2>/dev/null
pkill -f snmp_remote_daemon 2>/dev/null
pkill -f ssh_remote_daemon.sh 2>/dev/null
sleep 1

# Start Daemons
setsid /home/g0dmax55/conky/g0dmax55-conky/scripts/snmp_remote_daemon.sh >/dev/null 2>&1 &

# Start Conky Instances
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conkyrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-networkrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-netstatrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-system-updatesrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-versionsrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-marketsrc >/dev/null 2>&1 &
sleep 1
setsid conky -c /home/g0dmax55/conky/g0dmax55-conky/.g0dmax55-conky-snmprc >/dev/null 2>&1 &
sleep 1
