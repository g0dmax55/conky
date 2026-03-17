#!/bin/bash

# Conky Colors (matching main conky theme):
# color6 = Red   - Tree structure & Brackets
# color2 = Cyan  - Values (IPs, domains, ports)
# color1 = Grey  - Labels & text

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

# FIXED SLOT COUNTS
TCP_SLOTS=23
UDP_SLOTS=4
LISTEN_SLOTS=14
ROUTE_SLOTS=6
CACHE_DIR="${CACHE_DIR:-/tmp/.g0dmax55_conky_netstat_radar}"

# Empty slot line
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"
mkdir -p "$CACHE_DIR"

pad_remaining_lines() {
    local count=$1
    local total=$2

    while [ "$count" -lt "$total" ]; do
        echo "$EMPTY"
        count=$((count + 1))
    done
}

is_new_entry() {
    local cache_file=$1
    local key=$2

    [ -s "$cache_file" ] && ! grep -Fqx -- "$key" "$cache_file"
}

format_route_line() {
    local dest=$1
    local gateway=$2
    local iface=$3
    local value_color=$4
    local bracket_color=$5

    printf "${C6}│  ├─${CR} ${bracket_color}[${value_color}%-15s${bracket_color}]${CR}  ${bracket_color}[${value_color}%-15s${bracket_color}]${CR}  ${bracket_color}[${value_color}%s${bracket_color}]${CR}\n" \
        "$dest" "$gateway" "$iface"
}

format_active_line() {
    local proto=$1
    local recvq=$2
    local sendq=$3
    local local_addr=$4
    local foreign_addr=$5
    local state=$6
    local value_color=$7
    local text_color=$8
    local bracket_color=$9

    printf "${C6}│  ├─${CR} ${bracket_color}[${value_color}%-4s${bracket_color}]${CR} ${bracket_color}[${value_color}%3s${bracket_color}]${CR} ${bracket_color}[${value_color}%3s${bracket_color}]${CR} ${bracket_color}[${value_color}%-25.25s${bracket_color}]${CR} ${bracket_color}[${value_color}%-50.50s${bracket_color}]${CR} ${bracket_color}[${text_color}%s${bracket_color}]${CR}\n" \
        "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state"
}

format_udp_line() {
    local proto=$1
    local recvq=$2
    local sendq=$3
    local local_addr=$4
    local foreign_addr=$5
    local state=$6
    local value_color=$7
    local text_color=$8
    local bracket_color=$9

    printf "${C6}│  ├─${CR} ${bracket_color}[${value_color}%-4s${bracket_color}]${CR} ${bracket_color}[${value_color}%3s${bracket_color}]${CR} ${bracket_color}[${value_color}%3s${bracket_color}]${CR} ${bracket_color}[${value_color}%-25s${bracket_color}]${CR} ${bracket_color}[${value_color}%-25s${bracket_color}]${CR} ${bracket_color}[${text_color}%s${bracket_color}]${CR}\n" \
        "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state"
}

format_listening_line() {
    local proto=$1
    local port=$2
    local addr=$3
    local prog=$4
    local value_color=$5
    local text_color=$6
    local bracket_color=$7

    printf "${C6}│  ├─${CR} ${bracket_color}[${value_color}%-4s${bracket_color}]${CR} ${bracket_color}[${value_color}%5s${bracket_color}]${CR} ${bracket_color}[${value_color}%-25.25s${bracket_color}]${CR} ${bracket_color}[${text_color}%s${bracket_color}]${CR}\n" \
        "$proto" "$port" "$addr" "$prog"
}

emit_route_rows() {
    netstat -r 2>/dev/null | tail -n +3 | while read -r dest gateway mask flags metric ref use iface; do
        [ -z "$dest" ] && continue
        printf "%s\t%s\t%s\n" "$dest" "$gateway" "$iface"
    done
}

emit_active_rows() {
    netstat -Wt 2>/dev/null | tail -n +3 | while read -r proto recvq sendq local foreign state; do
        [ -z "$proto" ] && continue
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$proto" "$recvq" "$sendq" "$local" "$foreign" "$state"
    done
}

emit_udp_rows() {
    netstat -un 2>/dev/null | tail -n +3 | while read -r proto recvq sendq local foreign state; do
        [ -z "$proto" ] && continue
        printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$proto" "$recvq" "$sendq" "$local" "$foreign" "${state:-ESTABLISHED}"
    done
}

emit_listening_family_rows() {
    local proto=$1
    local family_flag=$2
    local port addr prog

    ss -H -ltnp "$family_flag" 2>/dev/null | while read -r state recvq sendq local peer process; do
        [ "$state" != "LISTEN" ] && continue
        [ -z "$local" ] && continue

        port="${local##*:}"
        addr="${local%:*}"
        [ "$addr" = "$local" ] && continue

        case "$addr" in
            "*")
                if [ "$proto" = "tcp6" ]; then
                    addr="::"
                else
                    addr="0.0.0.0"
                fi
                ;;
            "[::]")
                addr="::"
                ;;
        esac
        addr="${addr#[}"
        addr="${addr%]}"

        prog=$(echo "$process" | sed -n 's/.*users:(("\([^"]*\)".*/\1/p')
        [ -z "$prog" ] && prog="no-pid"

        printf "%s\t%s\t%s\t%s\n" "$proto" "$port" "$addr" "$prog"
    done
}

emit_listening_rows() {
    emit_listening_family_rows "tcp4" "-4"
    emit_listening_family_rows "tcp6" "-6"
}

render_routing_section() {
    local cache_file="$CACHE_DIR/routing.cache"
    local tmp_cache="${cache_file}.$$"
    local count=0
    local dest gateway iface key

    : > "$tmp_cache"
    while IFS=$'\t' read -r dest gateway iface; do
        key="${dest}|${gateway}|${iface}"
        printf '%s\n' "$key" >> "$tmp_cache"
        if is_new_entry "$cache_file" "$key"; then
            format_route_line "$dest" "$gateway" "$iface" "$C6" "$C1"
        else
            format_route_line "$dest" "$gateway" "$iface" "$C2" "$C6"
        fi
        count=$((count + 1))
    done < <(emit_route_rows | tail -n "$ROUTE_SLOTS")

    pad_remaining_lines "$count" "$ROUTE_SLOTS"
    mv "$tmp_cache" "$cache_file"
}

render_active_connections() {
    local cache_file="$CACHE_DIR/active.cache"
    local tmp_cache="${cache_file}.$$"
    local count=0
    local proto recvq sendq local_addr foreign_addr state key

    : > "$tmp_cache"
    while IFS=$'\t' read -r proto recvq sendq local_addr foreign_addr state; do
        key="${proto}|${local_addr}|${foreign_addr}|${state}"
        printf '%s\n' "$key" >> "$tmp_cache"
        if is_new_entry "$cache_file" "$key"; then
            format_active_line "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state" "$C6" "$C6" "$C1"
        else
            format_active_line "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state" "$C2" "$C1" "$C6"
        fi
        count=$((count + 1))
    done < <(emit_active_rows | tail -n "$TCP_SLOTS")

    pad_remaining_lines "$count" "$TCP_SLOTS"
    mv "$tmp_cache" "$cache_file"
}

render_udp_connections() {
    local cache_file="$CACHE_DIR/udp.cache"
    local tmp_cache="${cache_file}.$$"
    local count=0
    local proto recvq sendq local_addr foreign_addr state key

    : > "$tmp_cache"
    while IFS=$'\t' read -r proto recvq sendq local_addr foreign_addr state; do
        key="${proto}|${local_addr}|${foreign_addr}|${state}"
        printf '%s\n' "$key" >> "$tmp_cache"
        if is_new_entry "$cache_file" "$key"; then
            format_udp_line "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state" "$C6" "$C6" "$C1"
        else
            format_udp_line "$proto" "$recvq" "$sendq" "$local_addr" "$foreign_addr" "$state" "$C2" "$C1" "$C6"
        fi
        count=$((count + 1))
    done < <(emit_udp_rows | tail -n "$UDP_SLOTS")

    pad_remaining_lines "$count" "$UDP_SLOTS"
    mv "$tmp_cache" "$cache_file"
}

render_listening_section() {
    local cache_file="$CACHE_DIR/listening.cache"
    local tmp_cache="${cache_file}.$$"
    local count=0
    local proto port addr prog key

    : > "$tmp_cache"
    while IFS=$'\t' read -r proto port addr prog; do
        key="${proto}|${port}|${addr}|${prog}"
        printf '%s\n' "$key" >> "$tmp_cache"
        if is_new_entry "$cache_file" "$key"; then
            format_listening_line "$proto" "$port" "$addr" "$prog" "$C6" "$C6" "$C1"
        else
            format_listening_line "$proto" "$port" "$addr" "$prog" "$C2" "$C1" "$C6"
        fi
        count=$((count + 1))
    done < <(emit_listening_rows | tail -n "$LISTEN_SLOTS")

    pad_remaining_lines "$count" "$LISTEN_SLOTS"
    mv "$tmp_cache" "$cache_file"
}

# 1. STATISTICS (optimized: single netstat call, cached)
echo "${C6}├─${CR} ${C6}[${C2}STATISTICS${C6}]${CR}"
# Cache netstat output to avoid multiple calls
NETSTAT_TN=$(netstat -tn 2>/dev/null)
TCP_EST=$(echo "$NETSTAT_TN" | grep -c ESTABLISHED)
TCP_WAIT=$(echo "$NETSTAT_TN" | grep -c TIME_WAIT)
TCP_LISTEN=$(netstat -tln 2>/dev/null | tail -n +3 | wc -l)
UDP_TOTAL=$(netstat -un 2>/dev/null | tail -n +3 | wc -l)
echo "${C6}│  ├─${CR} ${C1}established:${C6}[${C2}${TCP_EST}${C6}]${CR} ${C1}time_wait:${C6}[${C2}${TCP_WAIT}${C6}]${CR} ${C1}listening:${C6}[${C2}${TCP_LISTEN}${C6}]${CR} ${C1}udp_total:${C6}[${C2}${UDP_TOTAL}${C6}]${CR}"
echo "${C6}│${CR}"

# 2. ROUTING
echo "${C6}├─${CR} ${C6}[${C2}ROUTING${C6}]${CR}"
render_routing_section
echo "${C6}│${CR}"

# 3. ACTIVE_CONNECTIONS
echo "${C6}├─${CR} ${C6}[${C2}ACTIVE_CONNECTIONS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-5s %-5s %-27s %-52s %s${CR}\n" "Proto" "R-Q" "S-Q" "Local Address" "Foreign Address" "State"
render_active_connections
echo "${C6}│${CR}"

# 4. UDP_CONNECTIONS
echo "${C6}├─${CR} ${C6}[${C2}UDP_CONNECTIONS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-5s %-5s %-27s %-27s %s${CR}\n" "Proto" "R-Q" "S-Q" "Local Address" "Foreign Address" "State"
render_udp_connections
echo "${C6}│${CR}"

# 5. LISTENING_PORTS
echo "${C6}├─${CR} ${C6}[${C2}LISTENING_PORTS${C6}]${CR}"
printf "${C6}│  ├─${CR} ${C1}%-6s %-7s %-27s %s${CR}\n" "Proto" "Port" "Address" "Program"
render_listening_section

echo "${C6}└─${CR}"
