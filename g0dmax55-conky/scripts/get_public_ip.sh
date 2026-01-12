#!/bin/bash

# Function to fetch IP using a specific DNS resolver
fetch_ip() {
    local target="ifconfig.me"
    local resolver="8.8.8.8"
    
    # Resolve the IP manually
    local resolved_ip=$(dig @$resolver +short $target | head -n 1)
    
    if [ -n "$resolved_ip" ]; then
        # Use the resolved IP with the Host header
        curl -s --max-time 3 --header "Host: $target" "http://$resolved_ip" 2>/dev/null
    else
        # Fallback to standard resolution if dig fails (unlikely if ping works)
        curl -s --max-time 3 "$target" 2>/dev/null
    fi
}

# Try fetching
output=$(fetch_ip)

if [ -n "$output" ]; then
    echo "$output"
else
    echo "..."
fi
