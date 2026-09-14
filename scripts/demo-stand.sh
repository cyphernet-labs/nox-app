#!/usr/bin/env bash
# Brings up a NOX stand for a demo, and prints what to do with it.
#
# The default -addr is loopback, which is right for development and useless
# here: a phone cannot dial 127.0.0.1, so the service page draws no code. This
# binds every interface, which is how a household server actually runs, and the
# link then carries an address a phone can reach.
#
# TWO stands can run at once, which is what proves pinning: a second server on a
# second key, at a second port, is the only way to show that a device refuses
# the machine it did not pair with.
set -euo pipefail

PORT="${PORT:-8080}"
STATUS_PORT="${STATUS_PORT:-8081}"
STAND="${STAND:-/tmp/nox-demo}"
RESET_APP=0
FRESH=0

usage() {
  cat <<USAGE
usage: scripts/demo-stand.sh [--stand DIR] [--port N] [--status-port N] [--fresh] [--reset-app]

  --stand DIR      where the database and log live (default /tmp/nox-demo)
  --port N         the server port (default 8080)
  --status-port N  the service page port, loopback only (default 8081)
  --fresh          delete the stand first. A FRESH STAND IS A FRESH KEY: every
                   link ever issued by the old one stops working, and every
                   device paired with it refuses to connect. Off by default -
                   it used to be unconditional, which made every scenario that
                   needs to come BACK to a stand look like a broken build.
  --reset-app      also wipe the macOS app's data, so the next launch is a
                   genuine first install (container + keychain)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --stand) STAND="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    --status-port) STATUS_PORT="$2"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    --reset-app) RESET_APP=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> building noxd"
(cd client_backend && go build -o "$STAND-noxd" .)

echo "==> stopping any stand left from last time"
pkill -f "$STAND-noxd" 2>/dev/null || true
sleep 1

if [ "$FRESH" = 1 ]; then
  echo "==> deleting $STAND - the server will mint a NEW key"
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

echo "==> starting the server"
"$STAND-noxd" -addr "0.0.0.0:$PORT" -db "$STAND/nox.db" -status-addr "127.0.0.1:$STATUS_PORT" \
  > "$STAND/server.log" 2>&1 &

# Polled, not slept. A fixed wait is either too short on a cold build - and the
# script then reports "no claim link" over a server that was merely still
# starting - or wasted time on every run after that.
echo -n "==> waiting for the server"
for _ in $(seq 1 100); do
  if grep -q '"msg":"listening"' "$STAND/server.log" 2>/dev/null; then break; fi
  if ! pgrep -f "$STAND-noxd" >/dev/null 2>&1; then
    echo
    echo "the server stopped while starting:" >&2
    cat "$STAND/server.log" >&2
    exit 1
  fi
  echo -n "."
  sleep 0.2
done
echo

# Two links, one token. The startup line addresses the machine itself, because
# that is who reads a terminal; the page addresses the network, because that is
# who reads a QR off a screen. Same right, different reader.
local_link="$(grep -oE 'https://nox.app/p/#[A-Za-z0-9_-]+' "$STAND/server.log" | head -1 || true)"
page_link="$(curl -fsS "http://127.0.0.1:$STATUS_PORT/" 2>/dev/null \
  | grep -oE 'https://nox.app/p/#[A-Za-z0-9_-]+' | head -1 || true)"
fingerprint="$(grep -oE '"fingerprint":"[^"]+"' "$STAND/server.log" | head -1 | cut -d'"' -f4 || true)"

if [ -z "$local_link" ] && [ -z "$fingerprint" ]; then
  echo "the server printed neither a claim link nor a fingerprint:" >&2
  cat "$STAND/server.log" >&2
  exit 1
fi

cat <<INFO

  stand up

  service page   http://127.0.0.1:$STATUS_PORT      (this machine only, plain HTTP by design)
  server         https://0.0.0.0:$PORT        (TLS 1.3, self-signed, pinned by fingerprint)
  fingerprint    ${fingerprint:-unknown}
  database       $STAND/nox.db
  log            $STAND/server.log

  claim link for an app on THIS machine
  ${local_link:-none: this server already has an owner}

  claim link for a phone (the one the page shows as a QR)
  ${page_link:-none: this machine has no address another device could reach, or it is already claimed}

  check it works, without clicking anything:
      (cd client_backend && go run ./cmd/smoke '${local_link:-<claim link>}')
      # then re-run this script: the smoke test claims the server

  or run the demo by hand:
      open http://127.0.0.1:$STATUS_PORT
      fvm flutter run -d macos --dart-define-from-file=config/stage.json

  a SECOND stand, on its own key, to show a device refusing the wrong server:
      scripts/demo-stand.sh --stand /tmp/nox-other --port 8090 --status-port 8091

INFO
