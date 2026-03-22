#!/bin/bash
# ── HomeTunnel Launcher ───────────────────────────────────────
# This file can be double-clicked in Finder to open a Terminal
# window and run the tunnel. macOS will ask for permission the
# first time — click Open.
# ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$SCRIPT_DIR/home_tunnel.sh"
