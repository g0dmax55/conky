#!/bin/bash
# Reads the tail of the live traffic log
# Adds color codes that Conky will parse

LOG_FILE="/tmp/conky_traffic.log"
FIXED_WIDTH=140

# Ensure the log exists and has content
if [ ! -f "$LOG_FILE" ] || [ ! -s "$LOG_FILE" ]; then
    printf "\${color1}▸ %-${FIXED_WIDTH}s" "Waiting for packets..."
    exit
fi

# Get last 10 non-empty lines
line_num=0
tail -n 10 "$LOG_FILE" | grep -v '^$' | tac | while read -r line; do
    [ -z "$line" ] && continue
    
    # Compress whitespace
    line=$(echo "$line" | tr -s ' ')
    
    # Truncate to max width
    if [ ${#line} -gt $FIXED_WIDTH ]; then
        line="${line:0:$((FIXED_WIDTH-3))}..."
    fi
    
    # Pad to exact width FIRST
    padded=$(printf "%-${FIXED_WIDTH}s" "$line")
    
    # Now add colors to the padded string
    colored=$(echo "$padded" | sed \
        -e 's/\[/\${color6}[/g' \
        -e 's/\]/]\${color2}/g' \
        -e 's/ -> / \${color1}->\${color2} /g')
    
    # Output with arrow
    if [ $line_num -eq 0 ]; then
        echo "\${color2}▶ $colored"
    else
        echo "\${color1}▷\${color2} $colored"
    fi
    ((line_num++))
done | tac
