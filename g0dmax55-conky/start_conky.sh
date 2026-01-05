#!/bin/bash
killall conky
sleep 2
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conkyrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-networkrc &
conky -c /home/g0dmax55/Desktop/conky/g0dmax55-conky/.g0dmax55-conky-trafficrc &
