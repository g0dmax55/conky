#!/bin/bash
val=$(cat /tmp/.g0dmax55_conky_remote_ssh_rx_rate 2>/dev/null | tr -dc '0-9')
echo "${val:-0}"
