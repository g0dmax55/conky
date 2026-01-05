#!/bin/bash
# Reads high-speed raw log and adds lines to display log at a steady pace
# This creates a "smooth scrolling" animation effect

RAW_LOG="/tmp/conky_traffic.log"
DISPLAY_LOG="/tmp/conky_display.log"

# Clean start
: > "$DISPLAY_LOG"

# Wait for raw log
while [ ! -f "$RAW_LOG" ]; do sleep 1; done

# Tail the raw log indefinitely
tail -F "$RAW_LOG" 2>/dev/null | while read -r line; do
    # 1. Output the line to display log
    echo "$line" >> "$DISPLAY_LOG"
    
    # 2. Trim display log to keep only last 15 lines (keeps it light)
    if [ $(wc -l < "$DISPLAY_LOG") -gt 15 ]; then
        tail -n 15 "$DISPLAY_LOG" > "$DISPLAY_LOG.tmp" && mv "$DISPLAY_LOG.tmp" "$DISPLAY_LOG"
    fi
    
    # 3. THE MAGIC: Sleep to throttle the speed
    # 0.25s = ~4 lines per second (Readable speed)
    sleep 0.25
done
