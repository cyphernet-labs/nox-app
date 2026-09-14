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

# Waiting for OUR server, which is not the same as waiting for the port.
#
# Two traps, both hit in practice. noxd writes "listening" one statement BEFORE
# it binds, so a server whose port is taken prints that line and then dies -
# this script used to believe it and announce a stand that was not running,
# with a fingerprint and a claim link for a dead process. And probing the port
# is no better on its own: a clash means somebody ELSE answers there, healthily.
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

# "listening" is written before the bind, so give the bind a moment to fail and
# re-read the error before believing the line.
sleep 0.3
if grep -q '"level":"ERROR"' "$STAND/server.log" 2>/dev/null; then
  echo "the server refused to start:" >&2
  grep '"level":"ERROR"' "$STAND/server.log" >&2
  exit 1
fi

fingerprint="$(grep -oE '"fingerprint":"[^"]+"' "$STAND/server.log" | head -1 | cut -d'"' -f4 || true)"
if [ -z "$fingerprint" ]; then
  echo "the server never announced a fingerprint:" >&2
  tail -20 "$STAND/server.log" >&2
  exit 1
fi
served="$(echo | openssl s_client -connect "127.0.0.1:$PORT" 2>/dev/null \
  | openssl x509 -noout -pubkey 2>/dev/null \
  | openssl pkey -pubin -outform DER 2>/dev/null \
  | openssl dgst -sha256 -binary 2>/dev/null | base64 || true)"
if [ "$served" != "$fingerprint" ]; then
  echo "port $PORT is answering, but not with THIS stand's key." >&2
  echo "  this stand minted: $fingerprint" >&2
  echo "  the port serves:   ${served:-nothing}" >&2
  echo "Another noxd is almost certainly holding the port - stop it, or pass --port." >&2
  tail -5 "$STAND/server.log" >&2
  exit 1
fi

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
