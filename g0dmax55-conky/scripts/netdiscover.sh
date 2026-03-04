#!/bin/bash

# System Update Watch panel for Conky.
# Replaces LAN discovery with package/update health details.

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

PACKAGE_SLOTS=12
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"

CACHE_DIR="/tmp/conky_update_watch"
STATUS_CACHE="$CACHE_DIR/status.cache"
PKG_CACHE="$CACHE_DIR/packages.cache"
CACHE_TTL=900

mkdir -p "$CACHE_DIR"

output_fixed_lines() {
    local total=$1
    local count=0
    while IFS= read -r line; do
        echo "$line"
        count=$((count + 1))
    done
    while [ "$count" -lt "$total" ]; do
        echo "$EMPTY"
        count=$((count + 1))
    done
}

cache_fresh() {
    if [ ! -f "$STATUS_CACHE" ]; then
        return 1
    fi
    local age
    age=$(( $(date +%s) - $(stat -c %Y "$STATUS_CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$CACHE_TTL" ]
}

detect_package_manager() {
    if command -v apt >/dev/null 2>&1; then
        echo "apt"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    else
        echo "none"
    fi
}

refresh_cache() {
    local pkg_mgr total_updates security_updates flatpak_updates snap_updates reboot_required
    local last_upgrade last_check package_lines raw
    local held_packages kernel_updates last_sync download_size repo_overview
    local apt_need_line apt_stamp_file

    pkg_mgr="$(detect_package_manager)"
    total_updates=0
    security_updates=0
    flatpak_updates=0
    snap_updates=0
    reboot_required="NO"
    last_upgrade="--"
    package_lines=""
    held_packages=0
    kernel_updates=0
    last_sync="--"
    download_size="--"
    repo_overview="--"

    case "$pkg_mgr" in
        apt)
            raw="$(timeout 12s apt list --upgradable 2>/dev/null | awk 'NR > 1 && /upgradable from:/')"
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            security_updates=$(timeout 12s apt-get -s upgrade 2>/dev/null | awk 'BEGIN{IGNORECASE=1} /^Inst / && /security/ {c++} END{print c+0}')
            package_lines="$(printf "%s\n" "$raw" | awk '
                /upgradable from:/ {
                    pkgrepo=$1
                    newv=$2
                    split(pkgrepo, a, "/")
                    pkg=a[1]
                    repo=a[2]
                    old=$0
                    sub(/.*upgradable from: /, "", old)
                    sub(/\].*/, "", old)
                    printf "%s|%s|%s|%s\n", pkg, old, newv, repo
                }
            ' | head -n "$PACKAGE_SLOTS")"
            last_upgrade="$(awk -F': ' '/^End-Date:/ {d=$2} END {if (d) print d; else print "--"}' /var/log/apt/history.log 2>/dev/null)"
            held_packages=$(timeout 6s apt-mark showhold 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)
            kernel_updates=$(printf "%s\n" "$raw" | awk '
                {
                    split($1, a, "/")
                    pkg=a[1]
                    if (pkg ~ /^(linux-image|linux-headers|linux-modules|linux-kbuild|linux-libc-dev|linux-perf)/) c++
                }
                END {print c+0}
            ')
            repo_overview=$(printf "%s\n" "$raw" | awk '
                {
                    split($1, a, "/")
                    if (a[2] != "") print a[2]
                }
            ' | sort | uniq -c | sort -nr | head -n 2 | awk '{printf "%s(%s),", $2, $1}' | sed 's/,$//')
            [ -z "$repo_overview" ] && repo_overview="--"

            apt_need_line="$(timeout 12s sh -c 'LC_ALL=C apt-get -s upgrade 2>/dev/null' | awk '/Need to get/ {print; exit}')"
            download_size="$(printf "%s\n" "$apt_need_line" | sed -n 's/.*Need to get \([^ ]\+ [^ ]\+\).*/\1/p')"
            [ -z "$download_size" ] && download_size="--"

            apt_stamp_file="/var/lib/apt/periodic/update-success-stamp"
            if [ -f "$apt_stamp_file" ]; then
                last_sync="$(date -d "@$(stat -c %Y "$apt_stamp_file" 2>/dev/null)" '+%Y-%m-%d %H:%M' 2>/dev/null)"
                [ -z "$last_sync" ] && last_sync="--"
            else
                latest_list_file="$(ls -1t /var/lib/apt/lists/*_InRelease /var/lib/apt/lists/*_Release 2>/dev/null | head -n 1)"
                if [ -n "$latest_list_file" ]; then
                    last_sync="$(date -d "@$(stat -c %Y "$latest_list_file" 2>/dev/null)" '+%Y-%m-%d %H:%M' 2>/dev/null)"
                    [ -z "$last_sync" ] && last_sync="--"
                fi
            fi
            ;;
        pacman)
            if command -v checkupdates >/dev/null 2>&1; then
                raw="$(timeout 12s checkupdates 2>/dev/null)"
            else
                raw="$(timeout 12s pacman -Qu 2>/dev/null)"
            fi
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            package_lines="$(printf "%s\n" "$raw" | awk 'NF {print $1}' | head -n "$PACKAGE_SLOTS")"
            ;;
        dnf)
            raw="$(timeout 12s dnf -q check-update 2>/dev/null | awk 'NF && $1 !~ /^Last/ && $1 !~ /^Obsoleting/ {print}')"
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            package_lines="$(printf "%s\n" "$raw" | awk 'NF {print $1}' | head -n "$PACKAGE_SLOTS")"
            ;;
        zypper)
            raw="$(timeout 12s zypper --non-interactive list-updates 2>/dev/null | awk '$1 ~ /^[v|]/ {print $5}')"
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            package_lines="$(printf "%s\n" "$raw" | head -n "$PACKAGE_SLOTS")"
            ;;
        *)
            package_lines="Unsupported package manager"
            ;;
    esac

    if command -v flatpak >/dev/null 2>&1; then
        flatpak_updates=$(timeout 10s flatpak remote-ls --updates --columns=application 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)
    fi

    if command -v snap >/dev/null 2>&1; then
        snap_updates=$(timeout 10s snap refresh --list 2>/dev/null | awk 'NR > 1 && NF {c++} END{print c+0}')
    fi

    if [ -f /var/run/reboot-required ]; then
        reboot_required="YES"
    fi

    last_check="$(date '+%d-%b %I:%M %p')"

    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$pkg_mgr" "$total_updates" "$security_updates" "$flatpak_updates" \
        "$snap_updates" "$reboot_required" "$last_upgrade" "$last_check" \
        "$held_packages" "$kernel_updates" "$last_sync" "$download_size" "$repo_overview" > "${STATUS_CACHE}.tmp"
    mv "${STATUS_CACHE}.tmp" "$STATUS_CACHE"

    printf "%s\n" "$package_lines" > "${PKG_CACHE}.tmp"
    mv "${PKG_CACHE}.tmp" "$PKG_CACHE"
}

if ! cache_fresh; then
    refresh_cache
fi

if [ ! -f "$STATUS_CACHE" ]; then
    refresh_cache
fi

PKG_MANAGER="none"
TOTAL_UPDATES="0"
SECURITY_UPDATES="0"
FLATPAK_UPDATES="0"
SNAP_UPDATES="0"
REBOOT_REQUIRED="NO"
LAST_UPGRADE="--"
LAST_CHECK="--"
HELD_PACKAGES="0"
KERNEL_UPDATES="0"
LAST_SYNC="--"
DOWNLOAD_SIZE="--"
REPO_OVERVIEW="--"

IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW < "$STATUS_CACHE"

# Cache schema migration: older cache has fewer fields.
STATUS_PIPE_COUNT=$(head -n 1 "$STATUS_CACHE" 2>/dev/null | tr -cd '|' | wc -c)
if [ "$STATUS_PIPE_COUNT" -lt 12 ]; then
    refresh_cache
    IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW < "$STATUS_CACHE"
fi

HELD_PACKAGES="${HELD_PACKAGES:-0}"
KERNEL_UPDATES="${KERNEL_UPDATES:-0}"
LAST_SYNC="${LAST_SYNC:---}"
DOWNLOAD_SIZE="${DOWNLOAD_SIZE:---}"
REPO_OVERVIEW="${REPO_OVERVIEW:---}"

# Cache format migration: older cache had package names only.
if [ "$PKG_MANAGER" = "apt" ] && [ "$TOTAL_UPDATES" -gt 0 ] && [ -s "$PKG_CACHE" ]; then
    if ! head -n 1 "$PKG_CACHE" | grep -q '|'; then
        refresh_cache
        IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW < "$STATUS_CACHE"
    fi
fi

echo "${C6}├─${CR} ${C6}[${C2}SYSTEM_UPDATES${C6}]${CR} ${C1}::${CR} ${C6}[${C2}${PKG_MANAGER^^}${C6}]${CR} ${C6}[${C2}${LAST_CHECK}${C6}]${CR}"
echo "${C6}│${CR}"
echo "${C6}├─${CR} ${C1}status${CR} ${C6}─┤${CR}"
echo "${C6}│  ├─${CR} ${C1}updates:${CR} ${C6}[${C2}${TOTAL_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}security:${CR} ${C6}[${C2}${SECURITY_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}flatpak:${CR} ${C6}[${C2}${FLATPAK_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}snap:${CR} ${C6}[${C2}${SNAP_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}reboot_required:${CR} ${C6}[${C2}${REBOOT_REQUIRED}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}last_upgrade:${CR} ${C6}[${C2}${LAST_UPGRADE}${C6}]${CR}"
if [ "$PKG_MANAGER" = "apt" ]; then
    echo "${C6}│  ├─${CR} ${C1}apt_sync:${CR} ${C6}[${C2}${LAST_SYNC}${C6}]${CR} ${C6}[${C2}download ${DOWNLOAD_SIZE}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}apt_meta:${CR} ${C6}[${C2}held ${HELD_PACKAGES}${C6}]${CR} ${C6}[${C2}kernel ${KERNEL_UPDATES}${C6}]${CR} ${C6}[${C2}${REPO_OVERVIEW}${C6}]${CR}"
fi

PENDING_SOURCE="unknown"
case "$PKG_MANAGER" in
    apt) PENDING_SOURCE="apt list --upgradable" ;;
    pacman) PENDING_SOURCE="pacman -Qu / checkupdates" ;;
    dnf) PENDING_SOURCE="dnf check-update" ;;
    zypper) PENDING_SOURCE="zypper list-updates" ;;
esac

echo "${C6}│  ├─${CR} ${C1}pending_source:${CR} ${C6}[${C2}${PENDING_SOURCE}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}pending_updates:${CR} ${C6}[${C2}${TOTAL_UPDATES}${C6}]${CR}"

DETAIL_COUNT=0
if [ "$TOTAL_UPDATES" -gt 0 ] && [ -s "$PKG_CACHE" ]; then
    while IFS='|' read -r pkg oldv newv repo; do
        [ -z "$pkg" ] && continue
        DETAIL_COUNT=$((DETAIL_COUNT + 1))

        DETAIL_LINE="$pkg"
        if [ -n "$oldv" ] && [ -n "$newv" ]; then
            DETAIL_LINE="${DETAIL_LINE}: ${oldv} -> ${newv}"
        fi
        if [ -n "$repo" ]; then
            DETAIL_LINE="${DETAIL_LINE} [${repo}]"
        fi

        if [ "${#DETAIL_LINE}" -gt 72 ]; then
            DETAIL_LINE="${DETAIL_LINE:0:69}..."
        fi

        echo "${C6}│  ├─${CR} ${C1}pending_${DETAIL_COUNT}:${CR} ${C6}[${C2}${DETAIL_LINE}${C6}]${CR}"
    done < <(head -n 3 "$PKG_CACHE")
fi

if [ "$TOTAL_UPDATES" -gt "$DETAIL_COUNT" ]; then
    echo "${C6}│  ├─${CR} ${C1}pending_more:${CR} ${C6}[${C2}+$(($TOTAL_UPDATES - $DETAIL_COUNT))${C6}]${CR}"
fi

echo "${C6}└─${CR}"
