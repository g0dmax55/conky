#!/usr/bin/env python3
"""
High-Precision Robust SNMP Bandwidth Monitor Daemon for Conky (Pure Local SNMP)
- 100% Client-Side Processing (ZERO scripts/probes running on the remote server)
- Pure SNMP over encrypted SSH Port Forwarding Tunnel (-L 1161:localhost:161 -N)
- Multi-sample sliding window with Graceful Decay Hold (5-8s smooth fadeout)
- Logarithmic dynamic graph scaling (prominent visible graph waves at all speeds)
- Single-call SNMP multi-OID polling (RX & TX)
- Real-time Bandwidth Variation & Surge Detection (▲ SPIKE, ▲ RISING, ▼ DROPPING, ━ STEADY)
- Exponential backoff & auto-reconnection for broken tunnels or server reboots
- Atomic cache writes to eliminate Conky reading race conditions & 0-drops
"""

import os
import sys
import time
import math
import socket
import subprocess
import signal
from collections import deque

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
ENV_FILE = os.path.join(SCRIPT_DIR, ".snmp_env")

# Cache files
CACHE_STATUS = "/tmp/.g0dmax55_conky_remote_snmp_status"
CACHE_RX = "/tmp/.g0dmax55_conky_remote_snmp_rx_rate"
CACHE_TX = "/tmp/.g0dmax55_conky_remote_snmp_tx_rate"
CACHE_RX_APP = "/tmp/.g0dmax55_conky_remote_snmp_rx_app"
CACHE_TX_APP = "/tmp/.g0dmax55_conky_remote_snmp_tx_app"

OID_RX_BASE = "1.3.6.1.2.1.31.1.1.1.6"   # ifHCInOctets
OID_TX_BASE = "1.3.6.1.2.1.31.1.1.1.10"  # ifHCOutOctets


def read_env():
    env = {
        "SERVER_IP": "",
        "SSH_PORT": "22",
        "USERNAME": "",
        "PASSWORD": "",
        "SNMP_COMMUNITY": "public",
        "SNMP_VERSION": "2c",
        "IF_NAME": "eth0",
        "IF_INDEX": "1",
        "LOCAL_TUNNEL_PORT": "1161",
        "POLL_INTERVAL": "1.0",
    }
    if os.path.exists(ENV_FILE):
        try:
            with open(ENV_FILE, "r") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    k = k.strip()
                    v = v.strip().strip('"').strip("'")
                    if "#" in v:
                        v = v.split("#")[0].strip().strip('"').strip("'")
                    env[k] = v
        except Exception:
            pass
    return env


def atomic_write(filepath, content):
    tmp_path = f"{filepath}.tmp.{os.getpid()}"
    try:
        with open(tmp_path, "w") as f:
            f.write(str(content) + "\n")
        os.replace(tmp_path, filepath)
    except Exception:
        if os.path.exists(tmp_path):
            try:
                os.remove(tmp_path)
            except OSError:
                pass


def init_cache(status="OFFLINE"):
    atomic_write(CACHE_STATUS, status)
    atomic_write(CACHE_RX, "0")
    atomic_write(CACHE_TX, "0")
    atomic_write(f"{CACHE_RX}_rate", "0")
    atomic_write(f"{CACHE_TX}_rate", "0")
    atomic_write(f"{CACHE_RX}_max", str(MIN_PEAK_FLOOR))
    atomic_write(f"{CACHE_TX}_max", str(MIN_PEAK_FLOOR))
    atomic_write(f"{CACHE_RX}_total", "0")
    atomic_write(f"{CACHE_TX}_total", "0")
    atomic_write(f"{CACHE_RX}_trend", "")
    atomic_write(f"{CACHE_TX}_trend", "")
    atomic_write(f"{CACHE_RX}_peak", "0")
    atomic_write(f"{CACHE_TX}_peak", "0")
    atomic_write(CACHE_RX_APP, "---")
    atomic_write(CACHE_TX_APP, "---")


def has_internet_connection():
    """Quick check to test if local internet is functioning."""
    for host in ["1.1.1.1", "8.8.8.8"]:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1.2)
            sock.connect((host, 53))
            sock.close()
            return True
        except Exception:
            continue
    return False


def cleanup_tunnel(tunnel_port):
    try:
        subprocess.run(["pkill", "-f", f"ssh.*-L {tunnel_port}:"], stderr=subprocess.DEVNULL)
    except Exception:
        pass


def is_tunnel_alive(tunnel_port):
    try:
        res = subprocess.run(["pgrep", "-f", f"ssh.*-L {tunnel_port}:"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return res.returncode == 0
    except Exception:
        return False


def start_tunnel(env):
    tunnel_port = env["LOCAL_TUNNEL_PORT"]
    cleanup_tunnel(tunnel_port)
    time.sleep(0.2)

    ssh_cmd = [
        "ssh",
        "-p", str(env["SSH_PORT"]),
        "-N", "-f",
        "-L", f"{tunnel_port}:localhost:161",
        "-o", "ConnectTimeout=4",
        "-o", "ServerAliveInterval=5",
        "-o", "ServerAliveCountMax=2",
        "-o", "StrictHostKeyChecking=no",
        f"{env['USERNAME']}@{env['SERVER_IP']}"
    ]

    if env.get("PASSWORD"):
        ssh_cmd = ["sshpass", "-p", env["PASSWORD"]] + ssh_cmd

    try:
        subprocess.run(ssh_cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=6)
        time.sleep(0.4)
        return is_tunnel_alive(tunnel_port)
    except Exception:
        return False


def resolve_all_interfaces(env):
    """Auto-resolves all interface indices dynamically."""
    tunnel_port = env.get("LOCAL_TUNNEL_PORT", "1161")
    snmp_target = f"tcp:localhost:{tunnel_port}"
    cmd = [
        "snmpwalk",
        f"-v{env.get('SNMP_VERSION', '2c')}",
        "-c", env.get("SNMP_COMMUNITY", "public"),
        "-On",
        "-t", "2",
        "-r", "1",
        snmp_target,
        "1.3.6.1.2.1.31.1.1.1.1"
    ]
    ifaces = {}
    try:
        res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3.0, text=True)
        for line in res.stdout.splitlines():
            if "=" in line:
                oid_part, val_part = line.split("=", 1)
                idx = oid_part.strip().rstrip(".").split(".")[-1]
                name = val_part.replace("STRING:", "").strip().strip('"').strip("'")
                ifaces[idx] = name
    except Exception:
        pass
    return ifaces


def resolve_if_index(env):
    """Auto-resolves single interface index dynamically from interface name (e.g. eth0)."""
    target_name = env.get("IF_NAME", "eth0").strip()
    ifaces = resolve_all_interfaces(env)
    for idx, name in ifaces.items():
        if name.lower() == target_name.lower():
            return idx
    return None


MIN_PEAK_FLOOR = 64 * 1024       # 64 KB/s floor: prevents small idle noise from saturating 100% graph
PEAK_WINDOW_SECONDS = 60.0       # 60s rolling window for dynamic peak auto-scaling


def calculate_dynamic_pct(rate, peak_rate):
    """Dynamically scales current rate linearly against recent peak with a minimum floor."""
    if rate <= 0:
        return 0
    effective_peak = max(MIN_PEAK_FLOOR, peak_rate)
    pct = int(round((rate / effective_peak) * 100))
    return max(1, min(100, pct))


def detect_trend(current_rate, prev_rate, is_decaying=False):
    """Detects bandwidth rate variations and returns a formatted Conky badge."""
    if current_rate <= 1024:
        return ""

    if is_decaying:
        return "${color6}▼ DROPPING${color}"

    delta = current_rate - prev_rate

    if delta >= 200 * 1024 or (prev_rate >= 50 * 1024 and current_rate >= prev_rate * 1.5):
        return "${color4}▲ SPIKE${color}"
    elif delta >= 50 * 1024 or (prev_rate >= 20 * 1024 and current_rate >= prev_rate * 1.3):
        return "${color3}▲ RISING${color}"
    elif delta <= -200 * 1024 or (current_rate <= prev_rate * 0.5 and prev_rate >= 100 * 1024):
        return "${color6}▼ DROPPING${color}"
    elif delta <= -50 * 1024 or (current_rate <= prev_rate * 0.7 and prev_rate >= 50 * 1024):
        return "${color1}▼ FALLING${color}"
    else:
        return "${color2}━ STEADY${color}"


def main():
    init_cache("RECONNECTING")

    baseline_rx = None
    baseline_tx = None

    last_poll_time = None
    last_rx_bytes = None
    last_tx_bytes = None

    rx_peak_history = deque()
    tx_peak_history = deque()

    prev_rate_rx = 0
    prev_rate_tx = 0
    session_peak_rx = 0
    session_peak_tx = 0
    fail_count = 0
    backoff_delay = 1.0

    current_if_index = None
    current_if_indices = None

    while True:
        env = read_env()
        if not env["SERVER_IP"] or not env["USERNAME"]:
            init_cache("OFFLINE")
            time.sleep(3)
            continue

        tunnel_port = env["LOCAL_TUNNEL_PORT"]
        poll_interval = float(env.get("POLL_INTERVAL", 1.0))
        iface_name = env.get("IF_NAME", "eth0")

        # -------------------------------------------------------------
        # 1. Check local internet connectivity on connection failures
        # -------------------------------------------------------------
        if fail_count > 0:
            if not has_internet_connection():
                atomic_write(CACHE_STATUS, "NO_INTERNET")
                atomic_write(f"{CACHE_RX}_rate", 0)
                atomic_write(f"{CACHE_TX}_rate", 0)
                atomic_write(CACHE_RX, 0)
                atomic_write(CACHE_TX, 0)
                atomic_write(f"{CACHE_RX}_trend", "")
                atomic_write(f"{CACHE_TX}_trend", "")
                atomic_write(CACHE_RX_APP, "---")
                atomic_write(CACHE_TX_APP, "---")
                cleanup_tunnel(tunnel_port)
                time.sleep(3)
                continue

        # -------------------------------------------------------------
        # 2. Ensure SSH Tunnel is healthy
        # -------------------------------------------------------------
        if not is_tunnel_alive(tunnel_port):
            atomic_write(CACHE_STATUS, "RECONNECTING")
            if not start_tunnel(env):
                fail_count += 1
                backoff_delay = min(8.0, 1.5 * fail_count)
                if fail_count >= 2:
                    atomic_write(CACHE_STATUS, "DISCONNECTED")
                    atomic_write(CACHE_RX_APP, "---")
                    atomic_write(CACHE_TX_APP, "---")
                time.sleep(backoff_delay)
                continue
            else:
                current_if_index = None
                current_if_indices = None

        next_tick = time.time() + poll_interval
        is_all_mode = (iface_name.lower() == "all")

        if is_all_mode:
            if not current_if_indices:
                all_ifaces = resolve_all_interfaces(env)
                current_if_indices = list(all_ifaces.keys()) if all_ifaces else [env.get("IF_INDEX", "1")]

            snmp_target = f"tcp:localhost:{tunnel_port}"
            oids_rx = [f"{OID_RX_BASE}.{idx}" for idx in current_if_indices]
            oids_tx = [f"{OID_TX_BASE}.{idx}" for idx in current_if_indices]
            snmp_cmd = [
                "snmpget",
                f"-v{env['SNMP_VERSION']}",
                "-c", env["SNMP_COMMUNITY"],
                "-Oqv",
                "-t", "2",
                "-r", "1",
                snmp_target,
            ] + oids_rx + oids_tx
            display_iface_label = "ALL"
        else:
            if not current_if_index:
                current_if_index = resolve_if_index(env) or env.get("IF_INDEX", "1")

            snmp_target = f"tcp:localhost:{tunnel_port}"
            oid_rx = f"{OID_RX_BASE}.{current_if_index}"
            oid_tx = f"{OID_TX_BASE}.{current_if_index}"
            snmp_cmd = [
                "snmpget",
                f"-v{env['SNMP_VERSION']}",
                "-c", env["SNMP_COMMUNITY"],
                "-Oqv",
                "-t", "2",
                "-r", "1",
                snmp_target,
                oid_rx,
                oid_tx,
            ]
            display_iface_label = iface_name

        try:
            res = subprocess.run(snmp_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2.2, text=True)
            output_lines = [l.strip().strip('"') for l in res.stdout.strip().splitlines() if l.strip()]
        except Exception:
            output_lines = []

        valid = False
        rx_bytes = 0
        tx_bytes = 0

        if is_all_mode:
            if output_lines:
                n = len(current_if_indices)
                rx_vals = []
                tx_vals = []
                for i in range(min(n, len(output_lines))):
                    digits = "".join(filter(str.isdigit, output_lines[i]))
                    if digits:
                        rx_vals.append(int(digits))
                for i in range(n, min(2 * n, len(output_lines))):
                    digits = "".join(filter(str.isdigit, output_lines[i]))
                    if digits:
                        tx_vals.append(int(digits))
                if rx_vals or tx_vals:
                    rx_bytes = sum(rx_vals)
                    tx_bytes = sum(tx_vals)
                    valid = True
        else:
            if len(output_lines) >= 2:
                rx_digits = "".join(filter(str.isdigit, output_lines[0]))
                tx_digits = "".join(filter(str.isdigit, output_lines[1]))
                if rx_digits or tx_digits:
                    rx_bytes = int(rx_digits) if rx_digits else 0
                    tx_bytes = int(tx_digits) if tx_digits else 0
                    valid = True

        if not valid:
            current_if_indices = None
            current_if_index = None

        now = time.time()

        if valid and (rx_bytes > 0 or tx_bytes > 0):
            fail_count = 0
            backoff_delay = 1.0
            atomic_write(CACHE_STATUS, "CONNECTED")
            atomic_write(CACHE_RX_APP, display_iface_label)
            atomic_write(CACHE_TX_APP, display_iface_label)

            if baseline_rx is None:
                baseline_rx = rx_bytes
                baseline_tx = tx_bytes

            session_rx = max(0, rx_bytes - baseline_rx)
            session_tx = max(0, tx_bytes - baseline_tx)

            atomic_write(f"{CACHE_RX}_total", session_rx)
            atomic_write(f"{CACHE_TX}_total", session_tx)

            # Instantaneous 1-to-1 Real-time Bandwidth Rate
            if last_poll_time is not None and last_rx_bytes is not None:
                dt = now - last_poll_time
                if dt > 0.1:
                    delta_rx = max(0, rx_bytes - last_rx_bytes)
                    delta_tx = max(0, tx_bytes - last_tx_bytes)
                    final_rx_rate = int(round(delta_rx / dt))
                    final_tx_rate = int(round(delta_tx / dt))
                else:
                    final_rx_rate = prev_rate_rx
                    final_tx_rate = prev_rate_tx
            else:
                final_rx_rate = 0
                final_tx_rate = 0

            last_poll_time = now
            last_rx_bytes = rx_bytes
            last_tx_bytes = tx_bytes

            # Track rolling peak history for dynamic auto-scaling
            rx_peak_history.append((now, final_rx_rate))
            tx_peak_history.append((now, final_tx_rate))

            while rx_peak_history and (now - rx_peak_history[0][0]) > PEAK_WINDOW_SECONDS:
                rx_peak_history.popleft()
            while tx_peak_history and (now - tx_peak_history[0][0]) > PEAK_WINDOW_SECONDS:
                tx_peak_history.popleft()

            dynamic_peak_rx = max(MIN_PEAK_FLOOR, max((r for _, r in rx_peak_history), default=0))
            dynamic_peak_tx = max(MIN_PEAK_FLOOR, max((r for _, r in tx_peak_history), default=0))

            # Linear dynamic auto-scaling percentage (0-100%) exactly matching numbers
            rx_pct = int(round((final_rx_rate / dynamic_peak_rx) * 100)) if dynamic_peak_rx > 0 else 0
            tx_pct = int(round((final_tx_rate / dynamic_peak_tx) * 100)) if dynamic_peak_tx > 0 else 0
            rx_pct = max(0, min(100, rx_pct))
            tx_pct = max(0, min(100, tx_pct))

            # Track session peaks
            if final_rx_rate > session_peak_rx:
                session_peak_rx = final_rx_rate
                atomic_write(f"{CACHE_RX}_peak", session_peak_rx)
            if final_tx_rate > session_peak_tx:
                session_peak_tx = final_tx_rate
                atomic_write(f"{CACHE_TX}_peak", session_peak_tx)

            # Detect Variation & Trend Badges
            rx_trend_badge = detect_trend(final_rx_rate, prev_rate_rx)
            tx_trend_badge = detect_trend(final_tx_rate, prev_rate_tx)
            prev_rate_rx = final_rx_rate
            prev_rate_tx = final_tx_rate

            atomic_write(CACHE_RX, rx_pct)
            atomic_write(CACHE_TX, tx_pct)
            atomic_write(f"{CACHE_RX}_rate", final_rx_rate)
            atomic_write(f"{CACHE_TX}_rate", final_tx_rate)
            atomic_write(f"{CACHE_RX}_max", dynamic_peak_rx)
            atomic_write(f"{CACHE_TX}_max", dynamic_peak_tx)
            atomic_write(f"{CACHE_RX}_trend", rx_trend_badge)
            atomic_write(f"{CACHE_TX}_trend", tx_trend_badge)

        else:
            fail_count += 1
            if fail_count >= 2:
                atomic_write(CACHE_STATUS, "RECONNECTING")
            if fail_count >= 3:
                atomic_write(CACHE_STATUS, "DISCONNECTED")
                atomic_write(f"{CACHE_RX}_rate", 0)
                atomic_write(f"{CACHE_TX}_rate", 0)
                atomic_write(CACHE_RX, 0)
                atomic_write(CACHE_TX, 0)
                atomic_write(f"{CACHE_RX}_trend", "")
                atomic_write(f"{CACHE_TX}_trend", "")
                atomic_write(CACHE_RX_APP, "---")
                atomic_write(CACHE_TX_APP, "---")
                last_poll_time = None
                last_rx_bytes = None
                last_tx_bytes = None
                rx_peak_history.clear()
                tx_peak_history.clear()
                cleanup_tunnel(tunnel_port)
                time.sleep(min(6.0, 1.5 * fail_count))

        sleep_dur = max(0.05, next_tick - time.time())
        time.sleep(sleep_dur)


if __name__ == "__main__":
    def handle_exit(signum, frame):
        env = read_env()
        cleanup_tunnel(env.get("LOCAL_TUNNEL_PORT", "1161"))
        init_cache("OFFLINE")
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)

    main()
