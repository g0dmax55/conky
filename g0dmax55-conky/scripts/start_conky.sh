#!/bin/bash
# Startup script for Conky Dashboard

# Kill existing processes
killall conky 2>/dev/null
pkill -f netstat_radar.sh 2>/dev/null
pkill -f netdiscover.sh 2>/dev/null
pkill -f market_tracker.sh 2>/dev/null
pkill -f ssh_remote_daemon.sh 2>/dev/null
sleep 1

# Start Daemons
/home/g0dmax55/Desktop/conky/g0dmax55-conky/scripts/ssh_remote_daemon.sh &


# Start Conky Instances
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conkyrc &
sleep 1
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-networkrc &
sleep 1
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-netstatrc &
sleep 1
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-netdiscoverrc &
sleep 1
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-marketsrc &
sleep 1
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-sshrc &
