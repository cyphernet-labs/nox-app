#!/usr/bin/env bash
# Brings up a NOX stand for a demo, and prints what to do with it.
#
# The default -addr is loopback, which is right for development and useless
# here: a phone cannot dial 127.0.0.1, so the service page draws no code. This
# binds every interface, which is how a household server actually runs, and the
# link then carries an address a phone can reach.
#
# tor runs BESIDE the server, as the separate service it is on a real machine:
# the server never starts tor and only stores the onion address it is given.
# The stand gets a tor of its own - its own torrc, data directory and onion
# service inside the stand directory - and the server is started with the
# address tor writes. No tor, or a tor that does not come up, leaves a stand
# reachable directly only.
#
# TWO stands can run at once, which is what proves the channel check: a second
# server on a second key, at a second port, is the only way to show that a
# device refuses the machine it did not pair with.
set -euo pipefail

PORT="${PORT:-8080}"
STATUS_PORT="${STATUS_PORT:-8081}"
STAND="${STAND:-/tmp/nox-demo}"
TOR_BIN="${TOR_BIN:-}"
USE_TOR=1
RESET_APP=0
FRESH=0

usage() {
  cat <<USAGE
usage: scripts/demo-stand.sh [--stand DIR] [--port N] [--status-port N]
                             [--tor-bin PATH] [--no-tor] [--fresh] [--reset-app]

  --stand DIR      where the database, the logs and the stand's tor live
                   (default /tmp/nox-demo)
  --port N         the server port (default 8080)
  --status-port N  the service page port, loopback only (default 8081)
  --tor-bin PATH   the tor to run beside the server (default: \$TOR_BIN, else
                   tor on the PATH; 0.4.9 or newer)
  --no-tor         no tor: the stand is reachable directly only
  --fresh          delete the stand first. A FRESH STAND IS A FRESH KEY AND A
                   FRESH ONION ADDRESS: every link ever issued by the old one
                   stops working, and every device paired with it refuses to
                   connect. Off by default - it used to be unconditional, which
                   made every scenario that needs to come BACK to a stand look
                   like a broken build.
  --reset-app      also wipe the macOS app's data, so the next launch is a
                   genuine first install (container + keychain)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --stand) STAND="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --status-port) STATUS_PORT="$2"; shift 2 ;;
    --tor-bin) TOR_BIN="$2"; shift 2 ;;
    --no-tor) USE_TOR=0; shift ;;
    --fresh) FRESH=1; shift ;;
    --reset-app) RESET_APP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> building noxd and the smoke tool"
(cd client_backend && go build -o "$STAND-noxd" . && go build -o "$STAND-smoke" ./cmd/smoke)

echo "==> stopping any stand left from last time"
pkill -f "$STAND-noxd" 2>/dev/null || true
# The stand's OWN tor, found by its own torrc: a tor anybody else runs on this
# machine is none of this script's business. It has to be gone before the next
# one starts, because two tors cannot share one data directory.
pkill -f "$STAND/torrc" 2>/dev/null || true
for _ in $(seq 1 50); do
  pgrep -f "$STAND/torrc" >/dev/null 2>&1 || break
  sleep 0.2
done
sleep 1

if [ "$FRESH" = 1 ]; then
  echo "==> deleting $STAND - the server will mint a NEW key, and tor a NEW onion address"
  rm -rf "$STAND"
fi
mkdir -p "$STAND"
if [ -f "$STAND/nox.db" ]; then
  echo "==> reusing the database in $STAND (same key, old links still work)"
else
  echo "==> new database in $STAND (the server will mint a key)"
fi

if [ "$RESET_APP" = 1 ]; then
  echo "==> wiping the macOS app so the next launch is a first install"
  rm -rf "$HOME/Library/Containers/com.cyphernetlabs.noxapp"
  # The keychain outlives the container, and a leftover entry makes a "clean"
  # install come up already signed in - which is the one thing a demo must not do.
  while security delete-generic-password -s flutter_secure_storage_service >/dev/null 2>&1; do :; done
fi

# tor first: the server is started with the address tor writes. The onion
# service points at the server's port on loopback, which the server holds
# because it binds every interface.
onion=""
tor_note=""
if [ "$USE_TOR" = 0 ]; then
  tor_note="none: --no-tor, so the stand is reachable directly only"
else
  if [ -z "$TOR_BIN" ]; then
    TOR_BIN="$(command -v tor || true)"
  fi
  if [ -z "$TOR_BIN" ] || [ ! -x "$TOR_BIN" ]; then
    tor_note="none: no tor binary (pass --tor-bin, or put tor 0.4.9+ on the PATH), so the stand is reachable directly only"
  elif [[ "$STAND" =~ [[:space:]] ]]; then
    tor_note="none: the stand path holds a space, which a torrc line cannot carry; the stand is reachable directly only"
  else
    echo "==> starting tor beside the server (its own torrc in $STAND)"
    # tor refuses a data or service directory anybody else can read.
    mkdir -p "$STAND/tor" "$STAND/hs"
    chmod 700 "$STAND/tor" "$STAND/hs"
    cat > "$STAND/torrc" <<TORRC
# The stand's tor: one onion service for the server, nothing else.
SocksPort 0
DataDirectory $STAND/tor
HiddenServiceDir $STAND/hs
HiddenServicePort 443 127.0.0.1:$PORT
HiddenServicePoWDefensesEnabled 1
Log notice file $STAND/tor.log
TORRC
    # tor writes the hostname from the service key on every start; removed
    # first, so a file left by the last run cannot pass for this one's.
    rm -f "$STAND/hs/hostname" "$STAND/tor.log"
    "$TOR_BIN" -f "$STAND/torrc" > "$STAND/tor.out" 2>&1 &
    tor_pid=$!
    echo -n "==> waiting for tor to write the onion address"
    for _ in $(seq 1 300); do
      if [ -s "$STAND/hs/hostname" ] || ! kill -0 "$tor_pid" 2>/dev/null; then break; fi
      echo -n "."
      sleep 0.2
    done
    echo
    if [ -s "$STAND/hs/hostname" ] && kill -0 "$tor_pid" 2>/dev/null; then
      onion="$(tr -d '[:space:]' < "$STAND/hs/hostname")"
      tor_note="running, log $STAND/tor.log"
    else
      echo "tor did not write its onion address; the stand goes on reachable directly only:" >&2
      # Before the log file is open, tor complains to its standard output.
      tail -20 "$STAND/tor.log" 2>/dev/null >&2 || true
      tail -20 "$STAND/tor.out" 2>/dev/null >&2 || true
      kill "$tor_pid" 2>/dev/null || true
      tor_note="none: tor did not write its onion address (see $STAND/tor.log and $STAND/tor.out)"
    fi
  fi
fi

echo "==> starting the server"
noxd_args=(-addr "0.0.0.0:$PORT" -db "$STAND/nox.db" -status-addr "127.0.0.1:$STATUS_PORT")
if [ -n "$onion" ]; then
  noxd_args+=(-onion-addr "$onion")
fi
"$STAND-noxd" "${noxd_args[@]}" > "$STAND/server.log" 2>&1 &

# Waiting for OUR server, which is not the same as waiting for the port.
#
# Two traps. A server that cannot start - its port taken, its database written
# by another build - logs an ERROR and exits, and announcing a stand for it
# would hand out a key and a link for a dead process. And probing the port is
# no better on its own: a clash means somebody ELSE answers there, healthily.
# So: wait for our process to settle, refuse on any ERROR it logged, and then
# confirm the machine on that port is the one whose key we just minted.
echo -n "==> waiting for the server"
for _ in $(seq 1 100); do
  if grep -q '"level":"ERROR"' "$STAND/server.log" 2>/dev/null; then
    echo
    echo "the server refused to start:" >&2
    grep '"level":"ERROR"' "$STAND/server.log" >&2
    exit 1
  fi
  if ! pgrep -f "$STAND-noxd" >/dev/null 2>&1; then
    echo
    echo "the server stopped while starting:" >&2
    tail -20 "$STAND/server.log" >&2
    exit 1
  fi
  # OUR log, not the port: on a clash the port answers perfectly - with
  # somebody else's server - and breaking on that is how the clash got missed.
  if grep -q '"msg":"listening"' "$STAND/server.log" 2>/dev/null; then break; fi
  echo -n "."
  sleep 0.2
done
echo

# An ERROR can land between the two greps above - a taken service-page port is
# logged just before "listening", and without the page there is no link to
# hand out - so the log is read once more before the line is believed.
sleep 0.3
if grep -q '"level":"ERROR"' "$STAND/server.log" 2>/dev/null; then
  echo "the server refused to start:" >&2
  grep '"level":"ERROR"' "$STAND/server.log" >&2
  exit 1
fi

server_key="$(grep -oE '"server_key":"[^"]+"' "$STAND/server.log" | head -1 | cut -d'"' -f4 || true)"
if [ -z "$server_key" ]; then
  echo "the server never announced its key:" >&2
  tail -20 "$STAND/server.log" >&2
  exit 1
fi
# The certificate is a throwaway one and names nothing, so the only way to
# know WHICH machine holds the port is the channel check itself, against the
# key this stand just announced.
if ! "$STAND-smoke" -check "127.0.0.1:$PORT" "$server_key" >/dev/null 2>"$STAND/check.err"; then
  echo "port $PORT is answering, but not as THIS stand:" >&2
  cat "$STAND/check.err" >&2
  echo "Another noxd is almost certainly holding the port - stop it, or pass --port." >&2
  tail -5 "$STAND/server.log" >&2
  exit 1
fi

# The link comes from the running server itself, through `noxd link`: the log
# never carries one. Asking issues a fresh link and voids the one before, which
# is what a stand wants - ten minutes from now, not from whenever the page last
# minted one. It is the same link the page shows as a QR code: it names the
# machine's address on the network, which a phone and an app on this machine
# can both dial, and the public and onion addresses when the server has them.
if ! link_out="$("$STAND-noxd" link -status-addr "127.0.0.1:$STATUS_PORT" 2>"$STAND/link.err")"; then
  echo "the server did not hand out a pairing link:" >&2
  cat "$STAND/link.err" >&2
  exit 1
fi
link="$(printf '%s\n' "$link_out" | grep -oE 'nox://pair/[A-Za-z0-9_-]+' | head -1 || true)"
if [ -z "$link" ]; then
  echo "noxd link answered without a link:" >&2
  printf '%s\n' "$link_out" >&2
  exit 1
fi

# The onion address itself is not printed: with no access keys, knowing it is
# all that stands between a stranger and the onion service, and terminal output
# gets pasted into bug reports. It is in the file tor wrote, for whoever needs it.
onion_line="none"
if [ -n "$onion" ]; then
  onion_line="given to the server with -onion-addr; it is in $STAND/hs/hostname"
fi
onion_hint=""
if [ -z "$onion" ]; then
  onion_hint="
  (an onion address stored by an earlier run stays until it is cleared on the
  service page - the devices would be told an address nobody answers at)
"
fi

cat <<INFO

  stand up

  service page   http://127.0.0.1:$STATUS_PORT      (this machine only, plain HTTP by design)
  server         https://0.0.0.0:$PORT        (TLS 1.3 + the channel check against the server key)
  server key     $server_key
  database       $STAND/nox.db
  log            $STAND/server.log
  tor            $tor_note
  onion address  $onion_line
$onion_hint
  pairing link - ten minutes, the same one the page shows as a QR code
  $link

  a new one - the one above stops working (-qr draws it in the terminal too):
      $STAND-noxd link -status-addr 127.0.0.1:$STATUS_PORT

  check it works, without clicking anything:
      (cd client_backend && go run ./cmd/smoke '$link')
      # the smoke test spends the link and leaves its own devices paired:
      # run this script with --fresh again before a demo from scratch

  or run the demo by hand:
      open http://127.0.0.1:$STATUS_PORT
      fvm flutter run -d macos --dart-define-from-file=config/stage.json

  a SECOND stand, on its own key and with its own tor, to show a device refusing the wrong server:
      scripts/demo-stand.sh --stand /tmp/nox-other --port 8090 --status-port 8091

INFO
