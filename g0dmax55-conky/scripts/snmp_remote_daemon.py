#!/usr/bin/env python3
"""
High-Precision Robust SNMP Bandwidth Monitor Daemon for Conky
Features:
- Internet Connectivity Detection & Fallback (NO_INTERNET / RECONNECTING / OFFLINE)
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
import threading
import json
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

app_probe_proc = None
socket_live_rx_rate = 0.0
socket_live_tx_rate = 0.0


def read_env():
    env = {
        "SERVER_IP": "",
        "SSH_PORT": "22",
        "USERNAME": "",
        "PASSWORD": "",
        "SNMP_COMMUNITY": "public",
        "SNMP_VERSION": "2c",
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


def rate_to_pct(rate):
    """Logarithmic dynamic scaling from 16 B/s (0%) to 100 MB/s (100%)."""
    if rate <= 16:
        return 0
    min_log = math.log10(16)
    max_log = math.log10(100 * 1024 * 1024)
    cur_log = math.log10(rate)
    pct = int(round(((cur_log - min_log) / (max_log - min_log)) * 100))
    return max(5, min(100, pct))


def detect_trend(current_rate, prev_rate, is_decaying=False):
    """Detects bandwidth rate variations and returns a formatted Conky badge."""
    if current_rate <= 32:
        return ""

    if is_decaying:
        return "${color6}▼ DROPPING${color}"

    delta = current_rate - prev_rate

    if delta >= 500 * 1024 or (prev_rate > 1024 and current_rate >= prev_rate * 1.4):
        return "${color4}▲ SPIKE${color}"
    elif delta >= 50 * 1024 or (prev_rate > 32 and current_rate >= prev_rate * 1.3):
        return "${color3}▲ RISING${color}"
    elif delta <= -500 * 1024 or (current_rate <= prev_rate * 0.6 and prev_rate > 500 * 1024):
        return "${color6}▼ DROPPING${color}"
    elif delta <= -50 * 1024 or (current_rate <= prev_rate * 0.7 and prev_rate > 1024):
        return "${color1}▼ FALLING${color}"
    else:
        return "${color2}━ STEADY${color}"


def remote_app_probe_worker(stop_event):
    global app_probe_proc, socket_live_rx_rate, socket_live_tx_rate

    REMOTE_PYTHON_PROBE = r'''
import subprocess, re, time, sys, json, os

def resolve_proc_name(pid, comm):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            raw = f.read()
        args = [a.decode("utf-8", errors="ignore").strip() for a in raw.split(b"\x00") if a.strip()]
        if not args:
            return (comm or "system").split(":")[0].strip()
        first_arg = args[0]
        if first_arg.startswith("sshd:") or first_arg.startswith("sshd ") or comm == "sshd":
            return "sshd"
        exe = os.path.basename(first_arg).split(":")[0].strip()
        interpreters = {"python", "python3", "python2", "pypy", "node", "nodejs", "bash", "sh", "zsh", "perl", "ruby", "php"}
        is_interp = any(exe == interp or exe.startswith(interp + ".") or exe.startswith(interp + "-") for interp in interpreters)
        if is_interp and len(args) > 1:
            for i, arg in enumerate(args[1:], start=1):
                if arg == "-m" and i + 1 < len(args):
                    return os.path.basename(args[i + 1]).split(":")[0].strip()
                if arg.startswith("-"):
                    continue
                script = os.path.basename(arg).split(":")[0].strip()
                if script and not script.startswith("-"):
                    return script
        if exe == "sshd":
            return "sshd"
        return exe or (comm or "system").split(":")[0].strip()
    except Exception:
        return (comm or "system").split(":")[0].strip()

def sample():
    p = subprocess.run(["ss", "-tupien", "state", "established"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    sockets = {}
    cur_proc = None
    cur_key = None
    for line in p.stdout.splitlines():
        line_str = line.strip()
        if not line_str or line_str.startswith("Failed") or line_str.startswith("Netid") or line_str.startswith("State") or line_str.startswith("Recv-Q"):
            continue
        if not line.startswith("\t") and not line.startswith(" "):
            parts = line_str.split()
            if len(parts) >= 5:
                cur_key = f"{parts[3]}->{parts[4]}"
            else:
                cur_key = line_str
            m = re.search(r'users:\(\("([^"]+)",pid=(\d+)', line_str)
            if m:
                cur_proc = resolve_proc_name(m.group(2), m.group(1))
            else:
                cur_proc = None
        else:
            bs_m = re.search(r'bytes_sent:(\d+)', line_str)
            br_m = re.search(r'bytes_received:(\d+)', line_str)
            bs = int(bs_m.group(1)) if bs_m else 0
            br = int(br_m.group(1)) if br_m else 0
            if cur_key:
                sockets[cur_key] = (cur_proc, bs, br)
    return sockets

prev_sockets = sample()
while True:
    time.sleep(1)
    cur_sockets = sample()
    rx_by_proc = {}
    tx_by_proc = {}
    for k, (proc, bs, br) in cur_sockets.items():
        if k in prev_sockets:
            _, p_bs, p_br = prev_sockets[k]
            d_tx = max(0, bs - p_bs)
            d_rx = max(0, br - p_br)
            pname = proc or "system"
            if d_rx > 0:
                rx_by_proc[pname] = rx_by_proc.get(pname, 0) + d_rx
            if d_tx > 0:
                tx_by_proc[pname] = tx_by_proc.get(pname, 0) + d_tx
                
    rx_candidates = [p for p in rx_by_proc.items() if p[0] != "system"] or list(rx_by_proc.items())
    tx_candidates = [p for p in tx_by_proc.items() if p[0] != "system"] or list(tx_by_proc.items())
    
    top_rx = max(rx_candidates, key=lambda x: x[1]) if rx_candidates else ("---", 0)
    top_tx = max(tx_candidates, key=lambda x: x[1]) if tx_candidates else ("---", 0)
    
    out = {"rx_app": top_rx[0], "rx_rate": top_rx[1], "tx_app": top_tx[0], "tx_rate": top_tx[1]}
    sys.stdout.write(json.dumps(out) + "\n")
    sys.stdout.flush()
    prev_sockets = cur_sockets
'''

    last_active_time = 0.0

    while not stop_event.is_set():
        env = read_env()
        if not env["SERVER_IP"] or not env["USERNAME"]:
            time.sleep(2)
            continue

        if not has_internet_connection():
            atomic_write(CACHE_RX_APP, "---")
            atomic_write(CACHE_TX_APP, "---")
            time.sleep(3)
            continue

        # Deploy/run remote probe cleanly via file
        remote_probe_setup = f"cat << 'EOF' > /tmp/.g0dmax55_conky_remote_probe.py\n{REMOTE_PYTHON_PROBE.strip()}\nEOF\n"
        if env.get("PASSWORD"):
            remote_cmd = f"{remote_probe_setup}echo '{env['PASSWORD']}' | sudo -S python3 -u /tmp/.g0dmax55_conky_remote_probe.py"
            ssh_cmd = [
                "sshpass", "-p", env["PASSWORD"],
                "ssh",
                "-p", str(env["SSH_PORT"]),
                "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=5",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=2",
                f"{env['USERNAME']}@{env['SERVER_IP']}",
                remote_cmd
            ]
        else:
            remote_cmd = f"{remote_probe_setup}sudo -n python3 -u /tmp/.g0dmax55_conky_remote_probe.py"
            ssh_cmd = [
                "ssh",
                "-p", str(env["SSH_PORT"]),
                "-o", "StrictHostKeyChecking=no",
                "-o", "ConnectTimeout=5",
                "-o", "ServerAliveInterval=5",
                "-o", "ServerAliveCountMax=2",
                f"{env['USERNAME']}@{env['SERVER_IP']}",
                remote_cmd
            ]

        try:
            app_probe_proc = subprocess.Popen(
                ssh_cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                bufsize=1
            )

            while not stop_event.is_set():
                line = app_probe_proc.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if not line or not line.startswith("{"):
                    continue

                try:
                    data = json.loads(line)
                    rx_app = data.get("rx_app", "---")
                    rx_rate = data.get("rx_rate", 0)
                    tx_app = data.get("tx_app", "---")
                    tx_rate = data.get("tx_rate", 0)

                    socket_live_rx_rate = float(rx_rate)
                    socket_live_tx_rate = float(tx_rate)

                    now = time.time()
                    APP_MIN_THRESHOLD = 100  # High-sensitivity threshold (100 B/s)

                    is_rx_active = (rx_rate >= APP_MIN_THRESHOLD) and (rx_app not in ("---", "system"))
                    is_tx_active = (tx_rate >= APP_MIN_THRESHOLD) and (tx_app not in ("---", "system"))

                    if is_rx_active or is_tx_active:
                        # If one direction is active and the other is empty/idle, mirror the active app so BOTH lines show the name
                        final_rx = rx_app if is_rx_active else tx_app
                        final_tx = tx_app if is_tx_active else rx_app

                        atomic_write(CACHE_RX_APP, final_rx)
                        atomic_write(CACHE_TX_APP, final_tx)
                        last_active_time = now
                    else:
                        if now - last_active_time > 4.0:
                            atomic_write(CACHE_RX_APP, "---")
                            atomic_write(CACHE_TX_APP, "---")

                except Exception:
                    pass

            if app_probe_proc and app_probe_proc.poll() is None:
                app_probe_proc.terminate()
                app_probe_proc.wait(timeout=1.0)
        except Exception:
            pass
        finally:
            socket_live_rx_rate = 0.0
            socket_live_tx_rate = 0.0
            atomic_write(CACHE_RX_APP, "---")
            atomic_write(CACHE_TX_APP, "---")
            if app_probe_proc and app_probe_proc.poll() is None:
                try:
                    app_probe_proc.kill()
                except Exception:
                    pass

        if not stop_event.is_set():
            time.sleep(2)


def main():
    init_cache("RECONNECTING")

    stop_event = threading.Event()
    probe_thread = threading.Thread(target=remote_app_probe_worker, args=(stop_event,), daemon=True)
    probe_thread.start()

    baseline_rx = None
    baseline_tx = None

    history = deque()
    WINDOW_SECONDS = 2.5

    display_rx_rate = 0.0
    display_tx_rate = 0.0

    prev_rate_rx = 0
    prev_rate_tx = 0
    session_peak_rx = 0
    session_peak_tx = 0
    fail_count = 0
    backoff_delay = 1.0

    while True:
        env = read_env()
        if not env["SERVER_IP"] or not env["USERNAME"] or not env["IF_INDEX"]:
            init_cache("OFFLINE")
            time.sleep(3)
            continue

        tunnel_port = env["LOCAL_TUNNEL_PORT"]
        poll_interval = float(env.get("POLL_INTERVAL", 1.0))
        oid_rx = f"{OID_RX_BASE}.{env['IF_INDEX']}"
        oid_tx = f"{OID_TX_BASE}.{env['IF_INDEX']}"

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
                time.sleep(backoff_delay)
                continue

        next_tick = time.time() + poll_interval

        snmp_target = f"tcp:localhost:{tunnel_port}"
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

        try:
            res = subprocess.run(snmp_cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2.2, text=True)
            output_lines = [l.strip().strip('"') for l in res.stdout.strip().splitlines() if l.strip()]
        except Exception:
            output_lines = []

        if len(output_lines) >= 2:
            try:
                rx_bytes = int(''.join(filter(str.isdigit, output_lines[0])))
                tx_bytes = int(''.join(filter(str.isdigit, output_lines[1])))
                valid = True
            except ValueError:
                valid = False
        else:
            valid = False

        now = time.time()

        if valid and rx_bytes > 0:
            fail_count = 0
            backoff_delay = 1.0
            atomic_write(CACHE_STATUS, "CONNECTED")

            if baseline_rx is None:
                baseline_rx = rx_bytes
                baseline_tx = tx_bytes

            session_rx = max(0, rx_bytes - baseline_rx)
            session_tx = max(0, tx_bytes - baseline_tx)

            atomic_write(f"{CACHE_RX}_total", session_rx)
            atomic_write(f"{CACHE_TX}_total", session_tx)

            history.append((now, rx_bytes, tx_bytes))

            while len(history) > 2 and (now - history[0][0]) > WINDOW_SECONDS:
                history.popleft()

            if len(history) >= 2:
                oldest_time, oldest_rx, oldest_tx = history[0]
                time_span = now - oldest_time

                if time_span > 0.2:
                    delta_rx = max(0, rx_bytes - oldest_rx)
                    delta_tx = max(0, tx_bytes - oldest_tx)

                    raw_rx_rate = delta_rx / time_span
                    raw_tx_rate = delta_tx / time_span
                else:
                    raw_rx_rate = display_rx_rate
                    raw_tx_rate = display_tx_rate
            else:
                raw_rx_rate = 0.0
                raw_tx_rate = 0.0

            effective_rx_rate = max(raw_rx_rate, socket_live_rx_rate)
            effective_tx_rate = max(raw_tx_rate, socket_live_tx_rate)

            # Graceful Decay Hold Algorithm (smooth fadeout)
            is_rx_decaying = False
            if effective_rx_rate >= 10:
                display_rx_rate = effective_rx_rate
            else:
                if display_rx_rate >= 10:
                    display_rx_rate *= 0.72
                    is_rx_decaying = True
                    if display_rx_rate < 10:
                        display_rx_rate = 0.0
                else:
                    display_rx_rate = 0.0

            is_tx_decaying = False
            if effective_tx_rate >= 10:
                display_tx_rate = effective_tx_rate
            else:
                if display_tx_rate >= 10:
                    display_tx_rate *= 0.72
                    is_tx_decaying = True
                    if display_tx_rate < 10:
                        display_tx_rate = 0.0
                else:
                    display_tx_rate = 0.0

            final_rx_rate = int(round(display_rx_rate))
            final_tx_rate = int(round(display_tx_rate))

            # Track session peaks
            if final_rx_rate > session_peak_rx:
                session_peak_rx = final_rx_rate
                atomic_write(f"{CACHE_RX}_peak", session_peak_rx)
            if final_tx_rate > session_peak_tx:
                session_peak_tx = final_tx_rate
                atomic_write(f"{CACHE_TX}_peak", session_peak_tx)

            # Detect Variation & Trend Badges
            rx_trend_badge = detect_trend(final_rx_rate, prev_rate_rx, is_rx_decaying)
            tx_trend_badge = detect_trend(final_tx_rate, prev_rate_tx, is_tx_decaying)
            prev_rate_rx = final_rx_rate
            prev_rate_tx = final_tx_rate

            atomic_write(f"{CACHE_RX}_trend", rx_trend_badge)
            atomic_write(f"{CACHE_TX}_trend", tx_trend_badge)

            # Prominent logarithmic percentage (0-100%) for Conky graph
            rx_pct = rate_to_pct(final_rx_rate)
            tx_pct = rate_to_pct(final_tx_rate)

            atomic_write(CACHE_RX, rx_pct)
            atomic_write(CACHE_TX, tx_pct)
            atomic_write(f"{CACHE_RX}_rate", final_rx_rate)
            atomic_write(f"{CACHE_TX}_rate", final_tx_rate)

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
                history.clear()
                display_rx_rate = 0.0
                display_tx_rate = 0.0
                cleanup_tunnel(tunnel_port)
                time.sleep(min(6.0, 1.5 * fail_count))

        sleep_dur = max(0.05, next_tick - time.time())
        time.sleep(sleep_dur)


if __name__ == "__main__":
    def handle_exit(signum, frame):
        global app_probe_proc
        if app_probe_proc and app_probe_proc.poll() is None:
            try:
                app_probe_proc.kill()
            except Exception:
                pass
        env = read_env()
        cleanup_tunnel(env.get("LOCAL_TUNNEL_PORT", "1161"))
        init_cache("OFFLINE")
        sys.exit(0)

    signal.signal(signal.SIGTERM, handle_exit)
    signal.signal(signal.SIGINT, handle_exit)

    main()
