#!/bin/bash

# System Update Watch panel for Conky.
# Replaces LAN discovery with package/update health details.

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C3="\${color3}"  # Green - Healthy/No updates
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

PACKAGE_SLOTS=12
PENDING_DETAIL_SLOTS=2
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"

CACHE_DIR="/tmp/conky_update_watch"
STATUS_CACHE="$CACHE_DIR/status.cache"
PKG_CACHE="$CACHE_DIR/packages.cache"
CACHE_TTL="${CONKY_UPDATE_CACHE_TTL:-60}"
APT_AUTO_SYNC_ENABLED="${CONKY_APT_AUTO_SYNC:-1}"
APT_AUTO_SYNC_INTERVAL="${CONKY_APT_AUTO_SYNC_INTERVAL:-1800}"
APT_AUTO_SYNC_RETRY_INTERVAL="${CONKY_APT_AUTO_SYNC_RETRY_INTERVAL:-900}"
APT_SYNC_LOCK_DIR="$CACHE_DIR/apt-sync.lock"
APT_SYNC_STAMP="$CACHE_DIR/apt-sync.stamp"
APT_SYNC_RESULT_CACHE="$CACHE_DIR/apt-sync-result.cache"

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
    if [ ! -f "$STATUS_CACHE" ] || [ ! -f "$PKG_CACHE" ]; then
        return 1
    fi

    # Refresh immediately when apt state changes (for example right after apt update/upgrade).
    if cache_outdated_by_repo_sync; then
        return 1
    fi

    local age
    age=$(( $(date +%s) - $(stat -c %Y "$STATUS_CACHE" 2>/dev/null || echo 0) ))
    [ "$age" -lt "$CACHE_TTL" ]
}

latest_apt_state_mtime() {
    local latest=0 file mtime

    for file in \
        /var/lib/apt/periodic/update-success-stamp \
        /var/lib/apt/lists/*_InRelease \
        /var/lib/apt/lists/*_Release \
        /var/lib/dpkg/status \
        /var/lib/dpkg/status-old \
        /var/log/apt/history.log; do
        [ -e "$file" ] || continue
        mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
        [ "$mtime" -gt "$latest" ] && latest="$mtime"
    done

    echo "$latest"
}

apt_auto_sync_due() {
    local now latest_repo_mtime last_attempt interval last_result

    [ "$APT_AUTO_SYNC_ENABLED" != "0" ] || return 1

    latest_repo_mtime="$(latest_apt_state_mtime)"
    now="$(date +%s)"
    last_attempt="$(stat -c %Y "$APT_SYNC_STAMP" 2>/dev/null || echo 0)"
    interval="$APT_AUTO_SYNC_INTERVAL"
    last_result="$(cat "$APT_SYNC_RESULT_CACHE" 2>/dev/null)"

    if [ "$last_attempt" -gt 0 ] && [ "$last_result" != "ok" ]; then
        interval="$APT_AUTO_SYNC_RETRY_INTERVAL"
    fi

    [ $(( now - latest_repo_mtime )) -ge "$APT_AUTO_SYNC_INTERVAL" ] || return 1
    [ $(( now - last_attempt )) -ge "$interval" ]
}

run_apt_auto_sync() {
    if [ "$(id -u)" -eq 0 ]; then
        timeout 120s env DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=1 >/dev/null 2>&1
        return
    fi

    if command -v pkcon >/dev/null 2>&1; then
        timeout 180s pkcon refresh force >/dev/null 2>&1
        return
    fi

    if command -v sudo >/dev/null 2>&1 && sudo -n true >/dev/null 2>&1; then
        timeout 120s sudo -n env DEBIAN_FRONTEND=noninteractive apt-get update -o Acquire::Retries=1 >/dev/null 2>&1
        return
    fi

    return 1
}

maybe_schedule_apt_auto_sync() {
    [ "$(detect_package_manager)" = "apt" ] || return
    apt_auto_sync_due || return

    if mkdir "$APT_SYNC_LOCK_DIR" 2>/dev/null; then
        (
            trap 'rmdir "$APT_SYNC_LOCK_DIR" 2>/dev/null || true' EXIT

            touch "$APT_SYNC_STAMP"
            result="fail"

            if run_apt_auto_sync; then
                result="ok"
            fi

            printf "%s\n" "$result" > "${APT_SYNC_RESULT_CACHE}.tmp"
            mv "${APT_SYNC_RESULT_CACHE}.tmp" "$APT_SYNC_RESULT_CACHE"
        ) >/dev/null 2>&1 &
    fi
}

cache_outdated_by_repo_sync() {
    local cache_mtime pkg_mgr latest_repo_mtime=0
    cache_mtime=$(stat -c %Y "$STATUS_CACHE" 2>/dev/null || echo 0)
    pkg_mgr="$(detect_package_manager)"

    case "$pkg_mgr" in
        apt)
            latest_repo_mtime="$(latest_apt_state_mtime)"
            ;;
        *)
            return 1
            ;;
    esac

    [ "$latest_repo_mtime" -gt "$cache_mtime" ]
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
    local kept_back_updates autoremove_count full_upgrade_extra
    local apt_need_line apt_stamp_file apt_sim apt_full_sim upgrade_ready_count
    local apt_auto_list full_upgrade_updates apt_upgrade_names
    local latest_list_file

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
    kept_back_updates=0
    autoremove_count=0
    full_upgrade_extra=0

    case "$pkg_mgr" in
        apt)
            raw="$(LC_ALL=C timeout 12s apt list --upgradable 2>/dev/null | awk 'NR > 1 && /upgradable from:/')"
            apt_sim="$(LC_ALL=C timeout 12s apt-get -s upgrade 2>/dev/null)"
            apt_full_sim="$(LC_ALL=C timeout 12s apt-get -s full-upgrade 2>/dev/null)"

            kept_back_updates="$(printf "%s\n" "$apt_sim" | awk '/^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./ {print $(NF-2); exit}')"
            [ -z "$kept_back_updates" ] && kept_back_updates=0

            upgrade_ready_count="$(printf "%s\n" "$apt_sim" | awk '/^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./ {print $1; exit}')"
            [ -z "$upgrade_ready_count" ] && upgrade_ready_count=0
            # Track only packages that a regular "apt upgrade" would install.
            total_updates="${upgrade_ready_count:-0}"

            full_upgrade_updates="$(printf "%s\n" "$apt_full_sim" | awk '/^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./ {print $1; exit}')"
            [ -z "$full_upgrade_updates" ] && full_upgrade_updates="$upgrade_ready_count"
            full_upgrade_extra=$(( full_upgrade_updates - upgrade_ready_count ))
            [ "$full_upgrade_extra" -lt 0 ] && full_upgrade_extra=0

            security_updates=$(printf "%s\n" "$apt_sim" | awk 'BEGIN{IGNORECASE=1} /^Inst / && /security/ {c++} END{print c+0}')
            apt_auto_list="$(printf "%s\n" "$apt_sim" | awk '
                /^The following packages were automatically installed and are no longer required:/ {in_auto=1; next}
                in_auto && /^Use / {in_auto=0}
                in_auto {print}
            ')"
            autoremove_count=$(printf "%s\n" "$apt_auto_list" | awk '{for (i=1; i<=NF; i++) c++} END{print c+0}')

            apt_upgrade_names="$(printf "%s\n" "$apt_sim" | awk '/^Inst / {print $2}')"
            if [ "$total_updates" -gt 0 ] && [ -n "$apt_upgrade_names" ]; then
                package_lines="$(awk '
                    FNR == NR {
                        if ($1 != "") {
                            wanted[$1] = 1
                        }
                        next
                    }
                    /upgradable from:/ {
                        pkgrepo=$1
                        newv=$2
                        split(pkgrepo, a, "/")
                        pkg=a[1]
                        repo=a[2]

                        if (!(pkg in wanted)) {
                            next
                        }

                        old=$0
                        sub(/.*upgradable from: /, "", old)
                        sub(/\].*/, "", old)
                        printf "%s|%s|%s|%s\n", pkg, old, newv, repo
                    }
                ' <(printf "%s\n" "$apt_upgrade_names") <(printf "%s\n" "$raw") | head -n "$PACKAGE_SLOTS")"
            else
                package_lines=""
            fi
            last_upgrade="$(awk -F': ' '/^End-Date:/ {d=$2} END {if (d) print d; else print "--"}' /var/log/apt/history.log 2>/dev/null)"
            held_packages=$(timeout 6s apt-mark showhold 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l)
            kernel_updates=$(printf "%s\n" "$package_lines" | awk -F'|' '
                {
                    pkg=$1
                    if (pkg ~ /^(linux-image|linux-headers|linux-modules|linux-kbuild|linux-libc-dev|linux-perf)/) c++
                }
                END {print c+0}
            ')
            repo_overview=$(printf "%s\n" "$package_lines" | awk -F'|' '
                {
                    if ($4 != "") print $4
                }
            ' | sort | uniq -c | sort -nr | head -n 2 | awk '{printf "%s(%s),", $2, $1}' | sed 's/,$//')
            [ -z "$repo_overview" ] && repo_overview="--"

            apt_need_line="$(printf "%s\n" "$apt_sim" | awk '/Need to get/ {print; exit}')"
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

    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$pkg_mgr" "$total_updates" "$security_updates" "$flatpak_updates" \
        "$snap_updates" "$reboot_required" "$last_upgrade" "$last_check" \
        "$held_packages" "$kernel_updates" "$last_sync" "$download_size" "$repo_overview" \
        "$kept_back_updates" "$autoremove_count" "$full_upgrade_extra" > "${STATUS_CACHE}.tmp"
    mv "${STATUS_CACHE}.tmp" "$STATUS_CACHE"

    printf "%s\n" "$package_lines" > "${PKG_CACHE}.tmp"
    mv "${PKG_CACHE}.tmp" "$PKG_CACHE"
}

maybe_schedule_apt_auto_sync

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
KEPT_BACK_UPDATES="0"
AUTOREMOVE_COUNT="0"
FULL_UPGRADE_EXTRA="0"

IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA < "$STATUS_CACHE"

# Cache schema migration: older cache has fewer fields.
STATUS_PIPE_COUNT=$(head -n 1 "$STATUS_CACHE" 2>/dev/null | tr -cd '|' | wc -c)
if [ "$STATUS_PIPE_COUNT" -lt 15 ]; then
    refresh_cache
    IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA < "$STATUS_CACHE"
fi

HELD_PACKAGES="${HELD_PACKAGES:-0}"
KERNEL_UPDATES="${KERNEL_UPDATES:-0}"
LAST_SYNC="${LAST_SYNC:---}"
DOWNLOAD_SIZE="${DOWNLOAD_SIZE:---}"
REPO_OVERVIEW="${REPO_OVERVIEW:---}"
KEPT_BACK_UPDATES="${KEPT_BACK_UPDATES:-0}"
AUTOREMOVE_COUNT="${AUTOREMOVE_COUNT:-0}"
FULL_UPGRADE_EXTRA="${FULL_UPGRADE_EXTRA:-0}"

# Cache format migration: older cache had package names only.
if [ "$PKG_MANAGER" = "apt" ] && [ "$TOTAL_UPDATES" -gt 0 ] && [ -s "$PKG_CACHE" ]; then
    if ! head -n 1 "$PKG_CACHE" | grep -q '|'; then
        refresh_cache
        IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA < "$STATUS_CACHE"
    fi
fi

echo "${C6}├─${CR} ${C6}[${C2}SYSTEM_UPDATES${C6}]${CR} ${C1}::${CR} ${C6}[${C2}${PKG_MANAGER^^}${C6}]${CR} ${C6}[${C2}${LAST_CHECK}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}updates:${CR} ${C6}[${C2}${TOTAL_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}security:${CR} ${C6}[${C2}${SECURITY_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}flatpak:${CR} ${C6}[${C2}${FLATPAK_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}snap:${CR} ${C6}[${C2}${SNAP_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}reboot_required:${CR} ${C6}[${C2}${REBOOT_REQUIRED}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}last_upgrade:${CR} ${C6}[${C2}${LAST_UPGRADE}${C6}]${CR}"
if [ "$PKG_MANAGER" = "apt" ]; then
    echo "${C6}│  ├─${CR} ${C1}apt_sync:${CR} ${C6}[${C2}${LAST_SYNC}${C6}]${CR} ${C6}[${C2}download ${DOWNLOAD_SIZE}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}apt_meta:${CR} ${C6}[${C2}held ${HELD_PACKAGES}${C6}]${CR} ${C6}[${C2}kernel ${KERNEL_UPDATES}${C6}]${CR} ${C6}[${C2}${REPO_OVERVIEW}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}apt_queue:${CR} ${C6}[${C2}kept_back ${KEPT_BACK_UPDATES}${C6}]${CR} ${C6}[${C2}autoremove ${AUTOREMOVE_COUNT}${C6}]${CR} ${C6}[${C2}full_extra ${FULL_UPGRADE_EXTRA}${C6}]${CR}"
fi

if [ "$TOTAL_UPDATES" -eq 0 ]; then
    if [ "$PKG_MANAGER" = "apt" ] && [ "$KEPT_BACK_UPDATES" -gt 0 ]; then
        echo "${C6}│  ├─${CR} ${C1}status:${CR} ${C6}[${C2}KEPT_BACK_ONLY${C6}]${CR}"
    else
        echo "${C6}│  ├─${CR} ${C1}status:${CR} ${C6}[${C3}NO_UPDATES${C6}]${CR}"
    fi
else
    PENDING_SOURCE="unknown"
    case "$PKG_MANAGER" in
        apt) PENDING_SOURCE="apt list --upgradable" ;;
        pacman) PENDING_SOURCE="pacman -Qu / checkupdates" ;;
        dnf) PENDING_SOURCE="dnf check-update" ;;
        zypper) PENDING_SOURCE="zypper list-updates" ;;
    esac

    echo "${C6}│  ├─${CR} ${C1}pending_source:${CR} ${C6}[${C2}${PENDING_SOURCE}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}pending_updates:${CR} ${C6}[${C2}${TOTAL_UPDATES}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}pending_status:${CR} ${C6}[${C6}UPDATES_AVAILABLE${C6}]${CR}"

    DETAIL_COUNT=0
    if [ -s "$PKG_CACHE" ]; then
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
        done < <(head -n "$PENDING_DETAIL_SLOTS" "$PKG_CACHE")
    fi

    if [ "$TOTAL_UPDATES" -gt "$DETAIL_COUNT" ]; then
        echo "${C6}│  ├─${CR} ${C1}pending_more:${CR} ${C6}[${C2}+$(($TOTAL_UPDATES - $DETAIL_COUNT))${C6}]${CR}"
    fi
fi

echo "${C6}└─${CR}"
