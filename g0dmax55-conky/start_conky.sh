#!/bin/bash
# Startup script for Conky Dashboard

# Kill existing processes
killall conky 2>/dev/null
killall traffic_logger.sh 2>/dev/null
killall tshark 2>/dev/null
sleep 1

# Start Background Traffic Logger
# We output to a log for debugging if needed, but the script handles the main log
/home/g0dmax55/Desktop/conky/g0dmax55-conky/traffic_logger.sh &

# Start Conky Instances
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conkyrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-networkrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-trafficrc &
