#!/bin/bash
# High-Performance FreeRDP Launcher for VPS

# Ensure local SSH tunnel is up if needed
if ! nc -z 127.0.0.1 3389 2>/dev/null; then
    echo "Starting SSH tunnel on port 3389..."
    ssh -p 2222 -N -f -L 3389:127.0.0.1:3389 hacker@31.97.205.45
    sleep 1
fi

echo "Launching optimized FreeRDP (Hardware GDI + RemoteFX + AVC444)..."
exec xfreerdp \
  /v:127.0.0.1:3389 \
  /u:hacker \
  /p:hari12345s1@ \
  /network:auto \
  /rfx \
  /gfx:avc444 \
  /gdi:hw \
  /bpp:24 \
  /compression-level:2 \
  +clipboard \
  +dynamic-resolution \
  "$@"
