#!/bin/bash

# System Update Watch panel for Conky.
# Replaces LAN discovery with package/update health details.

C6="\${color6}"  # Red - Tree/Brackets
C2="\${color2}"  # Cyan - Values
C3="\${color3}"  # Green - Healthy/No updates
C1="\${color1}"  # Grey - Text
CR="\${color}"   # Reset

PACKAGE_SLOTS=12
PENDING_DETAIL_SLOTS=1
EMPTY="${C6}│  ├─${CR} ${C1}---${CR}"

CACHE_DIR="/tmp/conky_update_watch"
STATUS_CACHE="$CACHE_DIR/status.cache"
PKG_CACHE="$CACHE_DIR/packages.cache"
CACHE_TTL="${CONKY_UPDATE_CACHE_TTL:-60}"
STATUS_CACHE_SCHEMA_VERSION="3"
APT_AUTO_SYNC_ENABLED="${CONKY_APT_AUTO_SYNC:-1}"
APT_AUTO_SYNC_INTERVAL="${CONKY_APT_AUTO_SYNC_INTERVAL:-1800}"
APT_AUTO_SYNC_RETRY_INTERVAL="${CONKY_APT_AUTO_SYNC_RETRY_INTERVAL:-900}"
APT_SYNC_LOCK_DIR="$CACHE_DIR/apt-sync.lock"
APT_SYNC_STAMP="$CACHE_DIR/apt-sync.stamp"
APT_SYNC_RESULT_CACHE="$CACHE_DIR/apt-sync-result.cache"
APT_STATE_DIR="$CACHE_DIR/apt-state"
APT_LISTS_DIR="$APT_STATE_DIR/lists"
APT_CACHE_DIR="$CACHE_DIR/apt-cache"
APT_ARCHIVES_DIR="$APT_CACHE_DIR/archives"
APT_UPDATE_STAMP="$CACHE_DIR/apt-update-success.stamp"

mkdir -p "$CACHE_DIR"

prepare_private_apt_state() {
    mkdir -p \
        "$APT_STATE_DIR" \
        "$APT_LISTS_DIR/partial" \
        "$APT_CACHE_DIR" \
        "$APT_ARCHIVES_DIR/partial"

    rm -f \
        "$APT_CACHE_DIR/pkgcache.bin" \
        "$APT_CACHE_DIR/srcpkgcache.bin"
}

run_private_apt_command() {
    local timeout_seconds tool

    timeout_seconds="$1"
    tool="$2"
    shift 2

    prepare_private_apt_state

    timeout "${timeout_seconds}s" "$tool" \
        -o "Dir::State=$APT_STATE_DIR" \
        -o "Dir::State::status=/var/lib/dpkg/status" \
        -o "Dir::State::extended_states=/var/lib/apt/extended_states" \
        -o "Dir::State::lists=$APT_LISTS_DIR" \
        -o "Dir::Cache=$APT_CACHE_DIR" \
        -o "Dir::Cache::archives=$APT_ARCHIVES_DIR" \
        -o "Dir::Cache::pkgcache=$APT_CACHE_DIR/pkgcache.bin" \
        -o "Dir::Cache::srcpkgcache=$APT_CACHE_DIR/srcpkgcache.bin" \
        "$@"
}

private_apt_metadata_present() {
    [ -f "$APT_UPDATE_STAMP" ] && return 0
    ls "$APT_LISTS_DIR"/*_InRelease "$APT_LISTS_DIR"/*_Release >/dev/null 2>&1
}

pending_section_label() {
    case "$1:$2" in
        apt:security_updates) echo "SECURITY_UPDATES" ;;
        apt:apt_related) echo "APT_RELATED" ;;
        flatpak:flatpak_updates) echo "FLATPAK_UPDATES" ;;
        snap:snap_updates) echo "SNAP_UPDATES" ;;
        pacman:packages) echo "PACMAN_UPDATES" ;;
        dnf:packages) echo "DNF_UPDATES" ;;
        zypper:packages) echo "ZYPPER_UPDATES" ;;
        *) echo "UPDATES" ;;
    esac
}

pending_source_label() {
    case "$1:$2" in
        apt:security_updates) echo "apt-get -s upgrade [security]" ;;
        apt:apt_related) echo "apt list --upgradable" ;;
        flatpak:flatpak_updates) echo "flatpak remote-ls --updates" ;;
        snap:snap_updates) echo "snap refresh --list" ;;
        pacman:packages) echo "pacman -Qu / checkupdates" ;;
        dnf:packages) echo "dnf check-update" ;;
        zypper:packages) echo "zypper list-updates" ;;
        *) echo "unknown" ;;
    esac
}

pending_section_total() {
    case "$1:$2" in
        apt:security_updates) echo "${SECURITY_UPDATES:-0}" ;;
        apt:apt_related) echo "${APT_PENDING_TOTAL:-0}" ;;
        flatpak:flatpak_updates) echo "${FLATPAK_UPDATES:-0}" ;;
        snap:snap_updates) echo "${SNAP_UPDATES:-0}" ;;
        pacman:packages|dnf:packages|zypper:packages) echo "${TOTAL_UPDATES:-0}" ;;
        *) echo "0" ;;
    esac
}

emit_pending_details() {
    local source="$1" section="$2" total="$3"
    local detail_count=0 detail_line pkg_source pkg_section pkg oldv newv repo

    if [ -s "$PKG_CACHE" ]; then
        while IFS='|' read -r pkg_source pkg_section pkg oldv newv repo; do
            [ "$pkg_source" = "$source" ] || continue
            [ "$pkg_section" = "$section" ] || continue
            [ -n "$pkg" ] || continue

            detail_count=$((detail_count + 1))
            detail_line="$pkg"

            if [ -n "$oldv" ] && [ -n "$newv" ]; then
                detail_line="${detail_line}: ${oldv} -> ${newv}"
            elif [ -n "$newv" ]; then
                detail_line="${detail_line}: ${newv}"
            elif [ -n "$oldv" ]; then
                detail_line="${detail_line}: ${oldv}"
            fi

            if [ -n "$repo" ]; then
                detail_line="${detail_line} [${repo}]"
            fi

            if [ "${#detail_line}" -gt 72 ]; then
                detail_line="${detail_line:0:69}..."
            fi

            echo "${C6}│  ├─${CR} ${C1}pending_${detail_count}:${CR} ${C6}[${C2}${detail_line}${C6}]${CR}"

            [ "$detail_count" -ge "$PENDING_DETAIL_SLOTS" ] && break
        done < "$PKG_CACHE"
    fi

    if [ "$detail_count" -eq 0 ]; then
        echo "${C6}│  ├─${CR} ${C1}pending_1:${CR} ${C6}[${C2}details unavailable${C6}]${CR}"
    fi

    if [ "$total" -gt "$detail_count" ]; then
        echo "${C6}│  ├─${CR} ${C1}pending_more:${CR} ${C6}[${C2}+$(($total - $detail_count))${C6}]${CR}"
    fi
}

count_color() {
    if [ "${1:-0}" -gt 0 ] 2>/dev/null; then
        echo "$C6"
    else
        echo "$C3"
    fi
}

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
        "$APT_UPDATE_STAMP" \
        "$APT_LISTS_DIR"/*_InRelease \
        "$APT_LISTS_DIR"/*_Release \
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

    now="$(date +%s)"
    last_attempt="$(stat -c %Y "$APT_SYNC_STAMP" 2>/dev/null || echo 0)"
    interval="$APT_AUTO_SYNC_INTERVAL"
    last_result="$(cat "$APT_SYNC_RESULT_CACHE" 2>/dev/null)"

    if [ "$last_attempt" -gt 0 ] && [ "$last_result" != "ok" ]; then
        interval="$APT_AUTO_SYNC_RETRY_INTERVAL"
    fi

    if ! private_apt_metadata_present; then
        [ $(( now - last_attempt )) -ge "$interval" ]
        return
    fi

    latest_repo_mtime="$(latest_apt_state_mtime)"
    [ $(( now - latest_repo_mtime )) -ge "$APT_AUTO_SYNC_INTERVAL" ] || return 1
    [ $(( now - last_attempt )) -ge "$interval" ]
}

run_apt_auto_sync() {
    DEBIAN_FRONTEND=noninteractive run_private_apt_command 240 apt-get update -o Acquire::Retries=1 >/dev/null 2>&1 || return 1
    touch "$APT_UPDATE_STAMP"
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
    local last_upgrade last_check raw
    local held_packages kernel_updates last_sync download_size repo_overview
    local kept_back_updates autoremove_count full_upgrade_extra
    local apt_need_line apt_stamp_file apt_sim apt_full_sim upgrade_ready_count
    local apt_auto_list full_upgrade_updates cache_schema_version apt_upgradable_total
    local latest_list_file security_packages flatpak_raw snap_raw pkg_cache_tmp status_cache_tmp

    pkg_mgr="$(detect_package_manager)"
    total_updates=0
    security_updates=0
    flatpak_updates=0
    snap_updates=0
    reboot_required="NO"
    last_upgrade="--"
    held_packages=0
    kernel_updates=0
    last_sync="--"
    download_size="--"
    repo_overview="--"
    kept_back_updates=0
    autoremove_count=0
    full_upgrade_extra=0
    status_cache_tmp="${STATUS_CACHE}.$$"
    pkg_cache_tmp="${PKG_CACHE}.$$"

    : > "$pkg_cache_tmp"

    case "$pkg_mgr" in
        apt)
            raw="$(LC_ALL=C run_private_apt_command 12 apt list --upgradable 2>/dev/null | awk 'NR > 1 && /upgradable from:/')"
            apt_sim="$(LC_ALL=C run_private_apt_command 12 apt-get -s upgrade 2>/dev/null)"
            apt_full_sim="$(LC_ALL=C run_private_apt_command 12 apt-get -s full-upgrade 2>/dev/null)"

            apt_upgradable_total=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)

            kept_back_updates="$(printf "%s\n" "$apt_sim" | awk '/^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./ {print $(NF-2); exit}')"
            [ -z "$kept_back_updates" ] && kept_back_updates=0

            upgrade_ready_count="$(printf "%s\n" "$apt_sim" | awk '/^[0-9]+ upgraded, [0-9]+ newly installed, [0-9]+ to remove and [0-9]+ not upgraded\./ {print $1; exit}')"
            [ -z "$upgrade_ready_count" ] && upgrade_ready_count=0
            total_updates="${upgrade_ready_count:-0}"
            if [ "$kept_back_updates" -eq 0 ] && [ "$apt_upgradable_total" -gt "$upgrade_ready_count" ]; then
                kept_back_updates=$(( apt_upgradable_total - upgrade_ready_count ))
            fi

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
            security_packages="$(printf "%s\n" "$apt_sim" | awk 'BEGIN{IGNORECASE=1} /^Inst / && /security/ {print $2}')"

            if [ "$apt_upgradable_total" -gt 0 ]; then
                if [ -n "$security_packages" ]; then
                    printf "%s\n" "$raw" | awk -v security_packages="$security_packages" '
                        BEGIN {
                            split(security_packages, sec_list, "\n")
                            for (i in sec_list) {
                                if (sec_list[i] != "") {
                                    security_pkg[sec_list[i]] = 1
                                }
                            }
                        }
                        /upgradable from:/ {
                            pkgrepo=$1
                            newv=$2
                            split(pkgrepo, a, "/")
                            pkg=a[1]
                            repo=a[2]
                            old=$0
                            sub(/.*upgradable from: /, "", old)
                            sub(/\].*/, "", old)
                            if (security_pkg[pkg]) {
                                printf "apt|security_updates|%s|%s|%s|%s\n", pkg, old, newv, repo
                            }
                        }
                    ' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
                fi

                printf "%s\n" "$raw" | awk '
                    /upgradable from:/ {
                        pkgrepo=$1
                        newv=$2
                        split(pkgrepo, a, "/")
                        pkg=a[1]
                        repo=a[2]
                        old=$0
                        sub(/.*upgradable from: /, "", old)
                        sub(/\].*/, "", old)
                        printf "apt|apt_related|%s|%s|%s|%s\n", pkg, old, newv, repo
                    }
                ' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
            fi
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

            apt_need_line="$(printf "%s\n" "$apt_sim" | awk '/Need to get/ {print; exit}')"
            if [ -z "$apt_need_line" ] && [ "$apt_upgradable_total" -gt 0 ]; then
                apt_need_line="$(printf "%s\n" "$apt_full_sim" | awk '/Need to get/ {print; exit}')"
            fi
            download_size="$(printf "%s\n" "$apt_need_line" | sed -n 's/.*Need to get \([^ ]\+ [^ ]\+\).*/\1/p')"
            [ -z "$download_size" ] && download_size="--"

            apt_stamp_file="$APT_UPDATE_STAMP"
            if [ -f "$apt_stamp_file" ]; then
                last_sync="$(date -d "@$(stat -c %Y "$apt_stamp_file" 2>/dev/null)" '+%Y-%m-%d %H:%M' 2>/dev/null)"
                [ -z "$last_sync" ] && last_sync="--"
            else
                latest_list_file="$(ls -1t "$APT_LISTS_DIR"/*_InRelease "$APT_LISTS_DIR"/*_Release 2>/dev/null | head -n 1)"
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
            printf "%s\n" "$raw" | awk 'NF {printf "pacman|packages|%s|||\n", $1}' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
            ;;
        dnf)
            raw="$(timeout 12s dnf -q check-update 2>/dev/null | awk 'NF && $1 !~ /^Last/ && $1 !~ /^Obsoleting/ {print}')"
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            printf "%s\n" "$raw" | awk 'NF {printf "dnf|packages|%s|||\n", $1}' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
            ;;
        zypper)
            raw="$(timeout 12s zypper --non-interactive list-updates 2>/dev/null | awk '$1 ~ /^[v|]/ {print $5}')"
            total_updates=$(printf "%s\n" "$raw" | sed '/^[[:space:]]*$/d' | wc -l)
            printf "%s\n" "$raw" | awk 'NF {printf "zypper|packages|%s|||\n", $1}' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
            ;;
    esac

    if command -v flatpak >/dev/null 2>&1; then
        flatpak_raw="$(timeout 10s flatpak remote-ls --updates --columns=application,name,version,branch,origin 2>/dev/null)"
        flatpak_updates=$(printf "%s\n" "$flatpak_raw" | sed '/^[[:space:]]*$/d' | wc -l)
        if [ "$flatpak_updates" -gt 0 ]; then
            printf "%s\n" "$flatpak_raw" | awk 'BEGIN { FS="\t" } NF {
                app=$1
                name=$2
                version=$3
                branch=$4
                origin=$5
                pkg=name
                if (pkg == "") {
                    pkg=app
                } else if (app != "" && app != name) {
                    pkg=sprintf("%s (%s)", name, app)
                }
                detail=version
                if (branch != "") {
                    if (detail != "") {
                        detail=detail " / " branch
                    } else {
                        detail=branch
                    }
                }
                printf "flatpak|flatpak_updates|%s||%s|%s\n", pkg, detail, origin
            }' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
        fi
    fi

    if command -v snap >/dev/null 2>&1; then
        snap_raw="$(timeout 10s snap refresh --list 2>/dev/null)"
        snap_updates=$(printf "%s\n" "$snap_raw" | awk 'NR > 1 && NF {c++} END{print c+0}')
        if [ "$snap_updates" -gt 0 ]; then
            printf "%s\n" "$snap_raw" | awk 'NR > 1 && NF {
                name=$1
                version=$2
                revision=$3
                repo=""
                if (revision != "") {
                    repo="rev " revision
                }
                printf "snap|snap_updates|%s||%s|%s\n", name, version, repo
            }' | head -n "$PACKAGE_SLOTS" >> "$pkg_cache_tmp"
        fi
    fi

    if [ -f /var/run/reboot-required ]; then
        reboot_required="YES"
    fi

    last_check="$(date '+%d-%b %I:%M %p')"
    cache_schema_version="$STATUS_CACHE_SCHEMA_VERSION"

    printf "%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s|%s\n" \
        "$pkg_mgr" "$total_updates" "$security_updates" "$flatpak_updates" \
        "$snap_updates" "$reboot_required" "$last_upgrade" "$last_check" \
        "$held_packages" "$kernel_updates" "$last_sync" "$download_size" "$repo_overview" \
        "$kept_back_updates" "$autoremove_count" "$full_upgrade_extra" "$cache_schema_version" > "$status_cache_tmp"
    mv "$status_cache_tmp" "$STATUS_CACHE"

    mv "$pkg_cache_tmp" "$PKG_CACHE"
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
CACHE_SCHEMA_VERSION="$STATUS_CACHE_SCHEMA_VERSION"
APT_PENDING_TOTAL="0"
PRIMARY_UPDATES_TOTAL="0"
PENDING_DETAIL_SOURCE=""
PENDING_DETAIL_SECTION=""
PENDING_DETAIL_TOTAL="0"

IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA CACHE_SCHEMA_VERSION < "$STATUS_CACHE"

# Cache schema migration: older cache has fewer fields.
STATUS_PIPE_COUNT=$(head -n 1 "$STATUS_CACHE" 2>/dev/null | tr -cd '|' | wc -c)
if [ "$STATUS_PIPE_COUNT" -lt 16 ]; then
    refresh_cache
    IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA CACHE_SCHEMA_VERSION < "$STATUS_CACHE"
fi

if [ "${CACHE_SCHEMA_VERSION:-}" != "$STATUS_CACHE_SCHEMA_VERSION" ]; then
    refresh_cache
    IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA CACHE_SCHEMA_VERSION < "$STATUS_CACHE"
fi

HELD_PACKAGES="${HELD_PACKAGES:-0}"
KERNEL_UPDATES="${KERNEL_UPDATES:-0}"
LAST_SYNC="${LAST_SYNC:---}"
DOWNLOAD_SIZE="${DOWNLOAD_SIZE:---}"
REPO_OVERVIEW="${REPO_OVERVIEW:---}"
KEPT_BACK_UPDATES="${KEPT_BACK_UPDATES:-0}"
AUTOREMOVE_COUNT="${AUTOREMOVE_COUNT:-0}"
FULL_UPGRADE_EXTRA="${FULL_UPGRADE_EXTRA:-0}"

# Cache format migration: older cache stored package lines without source/section fields.
if [ -s "$PKG_CACHE" ]; then
    PKG_PIPE_COUNT=$(head -n 1 "$PKG_CACHE" 2>/dev/null | tr -cd '|' | wc -c)
    if [ "$PKG_PIPE_COUNT" -lt 5 ]; then
        refresh_cache
        IFS='|' read -r PKG_MANAGER TOTAL_UPDATES SECURITY_UPDATES FLATPAK_UPDATES SNAP_UPDATES REBOOT_REQUIRED LAST_UPGRADE LAST_CHECK HELD_PACKAGES KERNEL_UPDATES LAST_SYNC DOWNLOAD_SIZE REPO_OVERVIEW KEPT_BACK_UPDATES AUTOREMOVE_COUNT FULL_UPGRADE_EXTRA CACHE_SCHEMA_VERSION < "$STATUS_CACHE"
    fi
fi

if [ "$PKG_MANAGER" = "apt" ]; then
    APT_PENDING_TOTAL=$((TOTAL_UPDATES + KEPT_BACK_UPDATES))
    PRIMARY_UPDATES_TOTAL="$APT_PENDING_TOTAL"
else
    PRIMARY_UPDATES_TOTAL="$TOTAL_UPDATES"
fi

PENDING_TOTAL=$((PRIMARY_UPDATES_TOTAL + FLATPAK_UPDATES + SNAP_UPDATES))
PENDING_SCOPE=""
APT_COLOR="$(count_color "$TOTAL_UPDATES")"
SECURITY_COLOR="$(count_color "$SECURITY_UPDATES")"
FLATPAK_COLOR="$(count_color "$FLATPAK_UPDATES")"
SNAP_COLOR="$(count_color "$SNAP_UPDATES")"
PENDING_COLOR="$(count_color "$PENDING_TOTAL")"

if [ "$PKG_MANAGER" = "apt" ] && [ "$TOTAL_UPDATES" -gt 0 ]; then
    PENDING_SCOPE="apt ${TOTAL_UPDATES}"
elif [ "$PKG_MANAGER" != "apt" ] && [ "$PRIMARY_UPDATES_TOTAL" -gt 0 ]; then
    PENDING_SCOPE="${PKG_MANAGER} ${PRIMARY_UPDATES_TOTAL}"
fi

if [ "$PKG_MANAGER" = "apt" ] && [ "$KEPT_BACK_UPDATES" -gt 0 ]; then
    [ -n "$PENDING_SCOPE" ] && PENDING_SCOPE="${PENDING_SCOPE}, "
    PENDING_SCOPE="${PENDING_SCOPE}kept_back ${KEPT_BACK_UPDATES}"
fi

if [ "$FLATPAK_UPDATES" -gt 0 ]; then
    [ -n "$PENDING_SCOPE" ] && PENDING_SCOPE="${PENDING_SCOPE}, "
    PENDING_SCOPE="${PENDING_SCOPE}flatpak ${FLATPAK_UPDATES}"
fi

if [ "$SNAP_UPDATES" -gt 0 ]; then
    [ -n "$PENDING_SCOPE" ] && PENDING_SCOPE="${PENDING_SCOPE}, "
    PENDING_SCOPE="${PENDING_SCOPE}snap ${SNAP_UPDATES}"
fi

if [ "$SECURITY_UPDATES" -gt 0 ]; then
    PENDING_DETAIL_SOURCE="apt"
    PENDING_DETAIL_SECTION="security_updates"
elif [ "$PKG_MANAGER" = "apt" ] && [ "$APT_PENDING_TOTAL" -gt 0 ]; then
    PENDING_DETAIL_SOURCE="apt"
    PENDING_DETAIL_SECTION="apt_related"
elif [ "$PRIMARY_UPDATES_TOTAL" -gt 0 ] && [ "$PKG_MANAGER" != "none" ]; then
    PENDING_DETAIL_SOURCE="$PKG_MANAGER"
    PENDING_DETAIL_SECTION="packages"
elif [ "$FLATPAK_UPDATES" -gt 0 ]; then
    PENDING_DETAIL_SOURCE="flatpak"
    PENDING_DETAIL_SECTION="flatpak_updates"
elif [ "$SNAP_UPDATES" -gt 0 ]; then
    PENDING_DETAIL_SOURCE="snap"
    PENDING_DETAIL_SECTION="snap_updates"
fi

if [ -n "$PENDING_DETAIL_SOURCE" ] && [ -n "$PENDING_DETAIL_SECTION" ]; then
    PENDING_DETAIL_TOTAL="$(pending_section_total "$PENDING_DETAIL_SOURCE" "$PENDING_DETAIL_SECTION")"
fi

echo "${C6}├─${CR} ${C6}[${C2}SYSTEM_UPDATES${C6}]${CR} ${C1}::${CR} ${C6}[${C2}${PKG_MANAGER^^}${C6}]${CR} ${C6}[${C2}${LAST_CHECK}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}summary:${CR} ${C6}[${APT_COLOR}apt ${TOTAL_UPDATES}${C6}]${CR} ${C6}[${SECURITY_COLOR}sec ${SECURITY_UPDATES}${C6}]${CR} ${C6}[${FLATPAK_COLOR}flatpak ${FLATPAK_UPDATES}${C6}]${CR} ${C6}[${SNAP_COLOR}snap ${SNAP_UPDATES}${C6}]${CR}"
echo "${C6}│  ├─${CR} ${C1}system:${CR} ${C6}[${C2}reboot ${REBOOT_REQUIRED}${C6}]${CR} ${C6}[${C2}upgrade ${LAST_UPGRADE}${C6}]${CR}"
if [ "$PKG_MANAGER" = "apt" ]; then
    echo "${C6}│  ├─${CR} ${C1}apt_state:${CR} ${C6}[${C2}sync ${LAST_SYNC}${C6}]${CR} ${C6}[${C2}dl ${DOWNLOAD_SIZE}${C6}]${CR} ${C6}[${C2}repo ${REPO_OVERVIEW}${C6}]${CR}"
    echo "${C6}│  ├─${CR} ${C1}apt_queue:${CR} ${C6}[${C2}held ${HELD_PACKAGES}${C6}]${CR} ${C6}[${C2}kernel ${KERNEL_UPDATES}${C6}]${CR} ${C6}[${C2}kept_back ${KEPT_BACK_UPDATES}${C6}]${CR} ${C6}[${C2}auto ${AUTOREMOVE_COUNT}${C6}]${CR}"
fi

if [ "$PENDING_TOTAL" -eq 0 ]; then
    echo "${C6}│  ├─${CR} ${C1}status:${CR} ${C6}[${C3}NO_UPDATES${C6}]${CR}"
else
    STATUS_LABEL="UPDATES_AVAILABLE"
    if [ "$PKG_MANAGER" = "apt" ] && [ "$TOTAL_UPDATES" -eq 0 ] && [ "$KEPT_BACK_UPDATES" -gt 0 ] && [ "$FLATPAK_UPDATES" -eq 0 ] && [ "$SNAP_UPDATES" -eq 0 ]; then
        STATUS_LABEL="KEPT_BACK_ONLY"
    fi

    echo "${C6}│  ├─${CR} ${C1}pending:${CR} ${C6}[${PENDING_COLOR}${STATUS_LABEL}${C6}]${CR} ${C6}[${PENDING_COLOR}total ${PENDING_TOTAL}${C6}]${CR} ${C6}[${PENDING_COLOR}${PENDING_SCOPE}${C6}]${CR}"

    if [ -n "$PENDING_DETAIL_SOURCE" ] && [ -n "$PENDING_DETAIL_SECTION" ] && [ "$PENDING_DETAIL_TOTAL" -gt 0 ]; then
        echo "${C6}│  ├─${CR} ${C1}pending_from:${CR} ${C6}[${PENDING_COLOR}$(pending_section_label "$PENDING_DETAIL_SOURCE" "$PENDING_DETAIL_SECTION")${C6}]${CR} ${C6}[${PENDING_COLOR}$(pending_source_label "$PENDING_DETAIL_SOURCE" "$PENDING_DETAIL_SECTION")${C6}]${CR}"
        emit_pending_details "$PENDING_DETAIL_SOURCE" "$PENDING_DETAIL_SECTION" "$PENDING_DETAIL_TOTAL"
    fi
fi

echo "${C6}└─${CR}"
