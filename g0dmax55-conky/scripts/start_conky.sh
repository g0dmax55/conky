#!/bin/bash
# Startup script for Conky Dashboard

# Kill existing processes
killall conky 2>/dev/null
pkill -f netstat_radar.sh 2>/dev/null
pkill -f netdiscover.sh 2>/dev/null
sleep 1

# Start Conky Instances
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conkyrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-networkrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-netstatrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-netdiscoverrc &
