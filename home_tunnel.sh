#!/bin/bash
# ============================================================
#  Tony's Home Tunnel
#  Reverse HTTPS Proxy via Cloudflare Tunnel
#  Author: Tony, 2026
#  Double-click HomeTunnel.command to start
# ============================================================

# NOTE: intentionally NOT using "set -e" — we handle all errors
# ourselves so the health-monitor loop can restart processes
# without the whole script dying on a non-zero exit.

# ── Colours ──────────────────────────────────────────────────
RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'
BLU='\033[0;34m'; CYN='\033[0;36m'; MAG='\033[0;35m'
BLD='\033[1m'; DIM='\033[2m'; RST='\033[0m'

log_info()  { echo -e "${BLU}[INFO]${RST}  $*"; }
log_ok()    { echo -e "${GRN}[  OK]${RST}  $*"; }
log_warn()  { echo -e "${YLW}[WARN]${RST}  $*"; }
log_err()   { echo -e "${RED}[ ERR]${RST}  $*"; }
log_step()  { echo -e "\n${BLD}${CYN}▶ $*${RST}"; }

# ── Config ────────────────────────────────────────────────────
PROXY_PORT="${PROXY_PORT:-8888}"
URL_FILE="/tmp/hometunnel_url.txt"
PID_FILE_PROXY="/tmp/hometunnel_proxy.pid"
PID_FILE_CF="/tmp/hometunnel_cf.pid"
PID_FILE_CAFF="/tmp/hometunnel_caff.pid"
PROXY_SCRIPT="/tmp/hometunnel_proxy.py"
CONN_LOG="/tmp/hometunnel_connections.log"   # live connection feed (FIFO)
LOG_FILE="$HOME/Library/Logs/HomeTunnel/tunnel.log"
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ── Banner ────────────────────────────────────────────────────
clear
echo -e "${BLD}${CYN}"
cat << 'BANNER'
  _____              _  _  _       _   _
 TONY'S HOME TUNNEL 2026

BANNER
echo -e "${RST}${BLD}  Tony's Home Tunnel  ·  Reverse HTTPS Proxy  ·  2026${RST}"
echo -e "  ─────────────────────────────────────────────────────\n"

# ── Cleanup (runs on Ctrl+C / EXIT) ──────────────────────────
cleanup() {
  trap - INT TERM EXIT
  echo -e "\n${YLW}[STOP]${RST}  Shutting down Tony's Home Tunnel…"

  if [[ -f "$PID_FILE_CAFF" ]]; then
    CAFF_PID=$(cat "$PID_FILE_CAFF" 2>/dev/null || true)
    [[ -n "$CAFF_PID" ]] && kill "$CAFF_PID" 2>/dev/null || true
    rm -f "$PID_FILE_CAFF"
    log_ok "Sleep prevention removed"
  fi
  if [[ -f "$PID_FILE_CF" ]]; then
    CF_PID=$(cat "$PID_FILE_CF" 2>/dev/null || true)
    [[ -n "$CF_PID" ]] && kill "$CF_PID" 2>/dev/null || true
    rm -f "$PID_FILE_CF"
  fi
  pkill -f "cloudflared tunnel" 2>/dev/null || true
  if [[ -f "$PID_FILE_PROXY" ]]; then
    PROXY_PID=$(cat "$PID_FILE_PROXY" 2>/dev/null || true)
    [[ -n "$PROXY_PID" ]] && kill "$PROXY_PID" 2>/dev/null || true
    rm -f "$PID_FILE_PROXY"
  fi
  rm -f "$URL_FILE" "$PROXY_SCRIPT" "$CONN_LOG"
  echo -e "${GRN}[STOP]${RST}  All stopped. Goodbye, Tony! 👋"
}
trap cleanup INT TERM EXIT

# ── Step 1 — macOS check ─────────────────────────────────────
log_step "Checking environment"
if [[ "$(uname)" != "Darwin" ]]; then
  log_err "This script requires macOS."; exit 1
fi
log_ok "macOS $(sw_vers -productVersion) on $(uname -m)"

# ── Step 2 — Homebrew ────────────────────────────────────────
if ! command -v brew &>/dev/null; then
  log_warn "Homebrew not found — installing…"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || { log_err "Homebrew install failed. Visit https://brew.sh"; exit 1; }
  eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
  eval "$(/usr/local/bin/brew shellenv 2>/dev/null || true)"
fi
log_ok "Homebrew: $(brew --version | head -1)"

# ── Step 3 — cloudflared ─────────────────────────────────────
if ! command -v cloudflared &>/dev/null; then
  log_warn "cloudflared not found — installing via Homebrew…"
  brew install cloudflared \
    || { log_err "Could not install cloudflared."; exit 1; }
fi
log_ok "cloudflared: $(cloudflared --version 2>&1 | head -1)"

# ── Step 4 — Kill leftovers ───────────────────────────────────
log_step "Cleaning up any previous tunnel"
for pf in "$PID_FILE_PROXY" "$PID_FILE_CF" "$PID_FILE_CAFF"; do
  if [[ -f "$pf" ]]; then
    OLD=$(cat "$pf" 2>/dev/null || true)
    [[ -n "$OLD" ]] && kill "$OLD" 2>/dev/null || true
    rm -f "$pf"
  fi
done
pkill -f "cloudflared tunnel"  2>/dev/null || true
pkill -f "hometunnel_proxy.py" 2>/dev/null || true

kill_port() {
  local PORT="$1" PIDS
  PIDS=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
  if [[ -n "$PIDS" ]]; then
    log_warn "Port $PORT held by PID(s) $PIDS — killing…"
    echo "$PIDS" | xargs kill -9 2>/dev/null || true
    sleep 1
    local STILL; STILL=$(lsof -ti tcp:"$PORT" 2>/dev/null || true)
    if [[ -n "$STILL" ]]; then
      log_err "Could not free port $PORT (PID $STILL still alive)."; return 1
    fi
    log_ok "Port $PORT is now free"
  fi
}

kill_port "$PROXY_PORT" || {
  log_err "Try closing whatever is using port $PROXY_PORT, or run:"
  log_err "  PROXY_PORT=9999 bash '$SCRIPT_PATH'"
  exit 1
}
sleep 1; log_ok "Clean"

# ── Step 5 — Prevent Mac from sleeping ───────────────────────
log_step "Preventing Mac from sleeping"
caffeinate -dims &
CAFF_PID=$!
echo "$CAFF_PID" > "$PID_FILE_CAFF"
kill -0 "$CAFF_PID" 2>/dev/null \
  && log_ok "Sleep prevention active (PID $CAFF_PID)" \
  || log_warn "caffeinate failed — tunnel may drop if Mac sleeps"

# ── Step 6 — Write & start the Python proxy ──────────────────
log_step "Starting local HTTP proxy on port $PROXY_PORT"
mkdir -p "$HOME/Library/Logs/HomeTunnel"

# The proxy writes one structured line per event to CONN_LOG (a regular
# file used as a tail-able feed). Format:
#   CONNECT  <client_ip>  <host>  <bytes_sent> <bytes_recv>  <duration_ms>
#   HTTP     <client_ip>  <method> <host><path> <status> <bytes> <duration_ms>
#   ERROR    <client_ip>  <host>  <message>

cat > "$PROXY_SCRIPT" << PYEOF
import http.server, socketserver, urllib.request, ssl, select, socket
import time, threading, os, sys

PORT   = $PROXY_PORT
LOGF   = "$CONN_LOG"

_log_lock = threading.Lock()
def log_conn(*fields):
    line = "\t".join(str(f) for f in fields)
    with _log_lock:
        with open(LOGF, "a") as f:
            f.write(line + "\n")
            f.flush()

def human_bytes(n):
    for unit in ("B","KB","MB","GB"):
        if n < 1024: return f"{n:.0f}{unit}"
        n /= 1024
    return f"{n:.1f}GB"

class ProxyHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args): pass   # silence default output

    def client_ip(self):
        return self.client_address[0]

    # ── HTTPS CONNECT (tunnelled TLS) ────────────────────────
    def do_CONNECT(self):
        host_port = self.path
        host = host_port.rsplit(":", 1)[0]
        t0 = time.time()
        sent = recv = 0
        try:
            h, p = host_port.rsplit(":", 1)
            remote = socket.create_connection((h, int(p)), timeout=20)
            self.send_response(200, "Connection established")
            self.end_headers()
            log_conn("OPEN", self.client_ip(), host_port, "")
            sent, recv = self._splice(self.connection, remote)
            ms = int((time.time() - t0) * 1000)
            log_conn("DONE", self.client_ip(), host_port,
                     f"↑{human_bytes(sent)} ↓{human_bytes(recv)} {ms}ms")
        except Exception as e:
            ms = int((time.time() - t0) * 1000)
            log_conn("ERR ", self.client_ip(), host_port, str(e)[:60])
            try: self.send_error(502, str(e))
            except: pass

    def _splice(self, a, b):
        sent = recv = 0
        sockets = [a, b]
        while True:
            try:
                r, _, x = select.select(sockets, [], sockets, 10)
                if x: break
                if not r: continue
                for s in r:
                    other = b if s is a else a
                    try:
                        data = s.recv(65536)
                        if not data: return sent, recv
                        other.sendall(data)
                        if s is a: sent += len(data)
                        else:      recv += len(data)
                    except: return sent, recv
            except: break
        return sent, recv

    # ── Plain HTTP forwarding ────────────────────────────────
    def do_GET(self):     self._fwd()
    def do_POST(self):    self._fwd()
    def do_PUT(self):     self._fwd()
    def do_DELETE(self):  self._fwd()
    def do_HEAD(self):    self._fwd()
    def do_OPTIONS(self): self._fwd()
    def do_PATCH(self):   self._fwd()

    def _fwd(self):
        t0 = time.time()
        url = self.path
        if not url.startswith("http"):
            url = "http://" + self.headers.get("Host", "") + url
        host = self.headers.get("Host", url)
        skip = {"proxy-connection", "proxy-authorization", "connection"}
        hdrs = {k: v for k, v in self.headers.items() if k.lower() not in skip}
        try:
            req = urllib.request.Request(url, headers=hdrs, method=self.command)
            ctx = ssl.create_default_context()
            with urllib.request.urlopen(req, context=ctx, timeout=20) as resp:
                body = resp.read()
                self.send_response(resp.status)
                for k, v in resp.headers.items():
                    if k.lower() not in ("transfer-encoding", "connection"):
                        self.send_header(k, v)
                self.end_headers()
                self.wfile.write(body)
                ms = int((time.time() - t0) * 1000)
                log_conn("HTTP", self.client_ip(),
                         f"{self.command} {host}", resp.status,
                         human_bytes(len(body)), f"{ms}ms")
        except Exception as e:
            ms = int((time.time() - t0) * 1000)
            log_conn("ERR ", self.client_ip(),
                     f"{self.command} {host}", str(e)[:60], "", f"{ms}ms")
            try: self.send_error(502, str(e))
            except: pass

socketserver.ThreadingTCPServer.allow_reuse_address = True
with socketserver.ThreadingTCPServer(("0.0.0.0", PORT), ProxyHandler) as s:
    s.serve_forever()
PYEOF

# Create the connection log file (regular file, tailed later)
: > "$CONN_LOG"

start_proxy() {
  python3 "$PROXY_SCRIPT" &
  PROXY_PID=$!
  echo "$PROXY_PID" > "$PID_FILE_PROXY"
  sleep 2
  kill -0 "$PROXY_PID" 2>/dev/null
}

if ! start_proxy; then
  log_err "Proxy failed to start — is port $PROXY_PORT already in use?"
  log_warn "Try: PROXY_PORT=9999 bash '$SCRIPT_PATH'"
  exit 1
fi
log_ok "Local proxy listening on 0.0.0.0:$PROXY_PORT (LAN + localhost)"

FW_STATE=$(defaults read /Library/Preferences/com.apple.alf globalstate 2>/dev/null || echo "0")
if [[ "$FW_STATE" == "2" ]]; then
  log_warn "macOS firewall is blocking ALL incoming connections — LAN proxy won't work."
  log_warn "Fix: System Settings → Network → Firewall → Options → remove 'Block all'"
elif [[ "$FW_STATE" == "1" ]]; then
  log_info "macOS firewall is on — click 'Allow' if prompted for python3."
fi

# ── Step 7 — Start cloudflared ───────────────────────────────
log_step "Creating Cloudflare HTTPS tunnel"
log_info "Protocol: HTTP/2 over TCP  (QUIC/UDP disabled — avoids router/ISP blocks)"

start_cloudflared() {
  rm -f "$URL_FILE"
  echo "--- tunnel start $(date) ---" >> "$LOG_FILE"
  cloudflared tunnel \
    --url "http://127.0.0.1:$PROXY_PORT" \
    --no-autoupdate \
    --protocol http2 \
    >> "$LOG_FILE" 2>&1 &
  CF_PID=$!
  echo "$CF_PID" > "$PID_FILE_CF"
  local WAIT=0 URL=""
  while [[ $WAIT -lt 45 ]]; do
    sleep 1; ((WAIT++))
    kill -0 "$CF_PID" 2>/dev/null || { echo ""; return 1; }
    URL=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$LOG_FILE" 2>/dev/null | tail -1 || true)
    [[ -n "$URL" ]] && { echo "$URL"; return 0; }
  done
  echo ""; return 1
}

TUNNEL_URL=$(start_cloudflared)
if [[ -z "$TUNNEL_URL" ]]; then
  log_err "Tunnel did not register after 45 seconds."
  log_err "Last log lines:"
  tail -10 "$LOG_FILE" | while read -r l; do echo -e "  ${RED}$l${RST}"; done
  exit 1
fi

echo "$TUNNEL_URL" > "$URL_FILE"
HOST="${TUNNEL_URL#https://}"

LAN_IP=$(ipconfig getifaddr en0 2>/dev/null \
      || ipconfig getifaddr en1 2>/dev/null \
      || route get default 2>/dev/null \
         | awk '/interface:/{print $2}' \
         | xargs -I{} ipconfig getifaddr {} 2>/dev/null \
      || echo "")

# ── Live banner ───────────────────────────────────────────────
print_banner() {
  local URL="$1" H="${1#https://}"
  echo ""
  echo -e "${GRN}${BLD}╔══════════════════════════════════════════════════════════╗${RST}"
  echo -e "${GRN}${BLD}║  ✅  TONY'S TUNNEL IS LIVE!                              ║${RST}"
  echo -e "${GRN}${BLD}╠══════════════════════════════════════════════════════════╣${RST}"
  echo -e "${GRN}${BLD}║${RST}  ${BLD}$URL${RST}"
  echo -e "${GRN}${BLD}║${RST}  Port: ${BLD}443${RST}   Protocol: ${BLD}HTTPS/HTTP2${RST}   Sleep: ${BLD}PREVENTED${RST}"
  echo -e "${GRN}${BLD}╚══════════════════════════════════════════════════════════╝${RST}"
  echo ""
  echo -e "  ${CYN}${BLD}🌐 AWAY FROM HOME  (work network / mobile data)${RST}"
  echo -e "  ─────────────────────────────────────────────────────"
  echo -e "  Server : ${BLD}$H${RST}   Port: ${BLD}443${RST}"
  echo -e "  Work Mac  → System Settings → Network → Proxies → Secure Web Proxy (HTTPS)"
  echo -e "  iPhone    → Settings → Wi-Fi → ⓘ → Configure Proxy → Manual"
  echo -e "  Android   → Settings → Wi-Fi → long-press → Modify → Advanced → Proxy: Manual"
  echo ""
  echo -e "  ${YLW}${BLD}🏠 ON YOUR HOME NETWORK  (phone on same Wi-Fi as this Mac)${RST}"
  echo -e "  ─────────────────────────────────────────────────────"
  if [[ -n "$LAN_IP" ]]; then
    echo -e "  Server : ${BLD}$LAN_IP${RST}   Port: ${BLD}$PROXY_PORT${RST}   ← direct, no Cloudflare"
    echo -e "  ${DIM}Tip: set a DHCP reservation in your router to keep this IP permanent.${RST}"
  else
    echo -e "  ${RED}LAN IP not detected.${RST} Check System Settings → Network → Wi-Fi → IP Address"
    echo -e "  Use that IP + port ${BLD}$PROXY_PORT${RST} on your phone."
  fi
  echo ""
  echo -e "  ${YLW}⚠️  Cloudflare URL changes every restart — copy it now!${RST}"
  echo -e "  ${BLD}Press Ctrl+C to stop.${RST}"
  echo ""
}

print_banner "$TUNNEL_URL"

# ── Connection activity display ───────────────────────────────
# Tails the connection log written by the Python proxy and prints
# each event as a neat one-liner.  Runs in background so the health
# monitor loop can run in the foreground.

display_connections() {
  local prev_client="" session_line=""

  tail -f "$CONN_LOG" 2>/dev/null | while IFS=$'\t' read -r type client target extra1 extra2 extra3; do
    TS=$(date '+%H:%M:%S')

    case "$type" in

      OPEN)
        # New HTTPS tunnel opened — print a "connecting" line and
        # remember the client so DONE can update it on the same visual row.
        # We can't overwrite in a terminal that scrolls, so just print open + close.
        echo -e "  ${GRN}▶${RST} ${DIM}$TS${RST}  ${BLD}${client}${RST}  ${CYN}⟶${RST}  ${BLD}$target${RST}"
        ;;

      DONE)
        # HTTPS tunnel closed — show data totals
        # extra1 = "↑xKB ↓yKB Zms"
        echo -e "  ${BLU}✓${RST} ${DIM}$TS${RST}  ${BLD}${client}${RST}  ${BLD}$target${RST}  ${DIM}$extra1${RST}"
        ;;

      HTTP)
        # Plain HTTP request — target = "METHOD host", extra1 = status, extra2 = size, extra3 = time
        local status="$extra1" size="$extra2" ms="$extra3"
        local col="$GRN"
        [[ "$status" =~ ^[45] ]] && col="$RED"
        [[ "$status" =~ ^3    ]] && col="$YLW"
        echo -e "  ${col}●${RST} ${DIM}$TS${RST}  ${BLD}${client}${RST}  ${target}  ${col}${status}${RST}  ${DIM}${size} ${ms}${RST}"
        ;;

      ERR*)
        echo -e "  ${RED}✗${RST} ${DIM}$TS${RST}  ${BLD}${client}${RST}  ${target}  ${RED}${extra1}${RST}"
        ;;
    esac
  done
}

# Print the activity header
echo -e "${BLD}${DIM}  ── Live Activity ─────────────────────────────────────────────────────${RST}"
echo -e "${DIM}     time      client          destination                   status  size  ms${RST}"
echo -e "${BLD}${DIM}  ───────────────────────────────────────────────────────────────────────${RST}"

display_connections &
DISPLAY_PID=$!

# ── Health monitor ────────────────────────────────────────────
RESTART_COUNT=0
MAX_CF_RESTARTS=10

while true; do
  sleep 20

  # Caffeinate
  CAFF_PID=$(cat "$PID_FILE_CAFF" 2>/dev/null || true)
  if ! kill -0 "$CAFF_PID" 2>/dev/null; then
    caffeinate -dims &
    CAFF_PID=$!
    echo "$CAFF_PID" > "$PID_FILE_CAFF"
    log_warn "caffeinate restarted (PID $CAFF_PID)"
  fi

  # Proxy
  PROXY_PID=$(cat "$PID_FILE_PROXY" 2>/dev/null || true)
  if ! kill -0 "$PROXY_PID" 2>/dev/null; then
    log_warn "Local proxy died — restarting…"
    if start_proxy; then
      log_ok "Proxy restarted (PID $(cat "$PID_FILE_PROXY"))"
    else
      log_err "Proxy could not restart. Please relaunch the tunnel."
      exit 1
    fi
  fi

  # cloudflared
  CF_PID=$(cat "$PID_FILE_CF" 2>/dev/null || true)
  if ! kill -0 "$CF_PID" 2>/dev/null; then
    ((RESTART_COUNT++))
    if [[ $RESTART_COUNT -gt $MAX_CF_RESTARTS ]]; then
      log_err "cloudflared has crashed $MAX_CF_RESTARTS times. Giving up."
      exit 1
    fi
    log_warn "cloudflared died — restart #$RESTART_COUNT of $MAX_CF_RESTARTS…"
    NEW_URL=$(start_cloudflared)
    if [[ -n "$NEW_URL" ]]; then
      echo "$NEW_URL" > "$URL_FILE"
      TUNNEL_URL="$NEW_URL"
      HOST="${NEW_URL#https://}"
      log_ok "Tunnel restarted with new URL:"
      print_banner "$NEW_URL"
    else
      log_err "Tunnel restart failed — no URL after 45s. Will retry in 20s."
    fi
  fi

  # display_connections watcher
  if ! kill -0 "$DISPLAY_PID" 2>/dev/null; then
    display_connections &
    DISPLAY_PID=$!
  fi

done
