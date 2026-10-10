#!/usr/bin/env bash
# Brings up a NOX stand for a demo, and prints what to do with it.
#
# The default -addr is loopback, which is right for development and useless
# here: a phone cannot dial 127.0.0.1, so the service page draws no code. This
# binds every interface, which is how a household server actually runs, and the
# link then carries an address a phone can reach.
#
# TWO stands can run at once, which is what proves the channel check: a second
# server on a second key, at a second port, is the only way to show that a
# device refuses the machine it did not pair with.
#
# The server starts LOCKED (047): its data is encrypted, and the password that
# opens it is entered after every start. This script enters it with `noxd
# unlock` - from NOX_STAND_PASSWORD when that is set, piped on standard input
# and never written anywhere, or by asking at the terminal. A fresh stand takes
# the password as its first one; a stand that is reused needs the one it was
# given.
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

  NOX_STAND_PASSWORD  the stand's password, entered with noxd unlock: the first
                   one on a fresh stand, the same one on a reused stand. Unset,
                   noxd unlock asks at the terminal.
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

echo "==> building noxd and the smoke tool"
(cd client_backend && go build -o "$STAND-noxd" . && go build -o "$STAND-smoke" ./cmd/smoke)

echo "==> stopping any stand left from last time"
pkill -f "$STAND-noxd" 2>/dev/null || true
sleep 1

if [ "$FRESH" = 1 ]; then
  echo "==> deleting $STAND - the server will mint a NEW key"
  rm -rf "$STAND"
fi
mkdir -p "$STAND"
if [ -f "$STAND/nox.db" ]; then
  echo "==> reusing the database in $STAND (same key, same password, old pairings still work)"
else
  echo "==> new database in $STAND (the server will mint a key; the password you give now is its first)"
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

# The server comes up locked: only its service page listens, and the main port
# opens once the password is in. So first the page, then the password, then
# the main port.
#
# OUR page, by our log: a page answering on the port may be another stand's,
# and the password must not go there. The line is written once the page's
# listener is bound.
echo -n "==> waiting for the service page"
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
  if grep -qE '"msg":"(no password is set yet|this server is locked)' "$STAND/server.log" 2>/dev/null; then break; fi
  echo -n "."
  sleep 0.2
done
echo

echo "==> unlocking the server with noxd unlock"
# noxd unlock says why it failed - a wrong password, or why a server with the
# right one could not start, its main port taken by another process above all.
# A server that could not start also writes it to its log on the way down, a
# moment after the command returned: show that too, rather than let set -e end
# the script on the command's line alone.
unlock_failed() {
  for _ in $(seq 1 10); do
    grep -q '"level":"ERROR"' "$STAND/server.log" 2>/dev/null && break
    pgrep -f "$STAND-noxd" >/dev/null 2>&1 || break
    sleep 0.2
  done
  if grep -q '"level":"ERROR"' "$STAND/server.log" 2>/dev/null; then
    echo "the server could not start:" >&2
    grep '"level":"ERROR"' "$STAND/server.log" >&2
  fi
  exit 1
}
if [ -n "${NOX_STAND_PASSWORD:-}" ]; then
  # Twice: a fresh server asks for the password and its repeat, a locked one
  # reads the first line and leaves the second.
  if ! printf '%s\n%s\n' "$NOX_STAND_PASSWORD" "$NOX_STAND_PASSWORD" \
    | "$STAND-noxd" unlock -status-addr "127.0.0.1:$STATUS_PORT"; then
    unlock_failed
  fi
elif [ -t 0 ]; then
  "$STAND-noxd" unlock -status-addr "127.0.0.1:$STATUS_PORT" || unlock_failed
else
  echo "no terminal to ask the password at: set NOX_STAND_PASSWORD" >&2
  exit 1
fi

# Waiting for OUR server, which is not the same as waiting for the port.
#
# Two traps, both hit in practice. A server whose port is taken can say it is
# about to listen and then die - this script used to believe that and announce
# a stand that was not running, with a key and a link for a dead process. And
# probing the port is no better on its own: a clash means somebody ELSE answers
# there, healthily. So: wait for our process to settle, refuse on any ERROR it
# logged, and then confirm the machine on that port is the one whose key we
# just minted.
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

# "listening" is written once the port is bound; a moment more, and a failure
# right after it would be in the log too.
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

# The link for a first device is on the page - never in the log. A machine
# that has devices shows none until somebody asks for one (Add a device, or
# noxd link), and asking voids the previous one.
page_link="$(curl -fsS "http://127.0.0.1:$STATUS_PORT/" 2>/dev/null \
  | grep -oE 'nox://pair/[A-Za-z0-9_-]+' | head -1 || true)"

cat <<INFO

  stand up

  service page   http://127.0.0.1:$STATUS_PORT      (this machine only, plain HTTP by design)
  server         https://0.0.0.0:$PORT        (TLS 1.3 + the channel check against the server key)
  server key     ${server_key:-unknown}
  database       $STAND/nox.db
  log            $STAND/server.log

  link for a first device (the one the page shows, as text and as a QR)
  ${page_link:-none on the page: this server has devices - get one with: $STAND-noxd link -status-addr 127.0.0.1:$STATUS_PORT}

  the server is unlocked until it stops; after every start it waits for its
  password again:
      $STAND-noxd unlock -status-addr 127.0.0.1:$STATUS_PORT

  check it works, without clicking anything:
      (cd client_backend && go run ./cmd/smoke '${page_link:-<link>}')
      # the smoke test pairs its own devices with the server

  or run the demo by hand:
      open http://127.0.0.1:$STATUS_PORT
      fvm flutter run -d macos --dart-define-from-file=config/stage.json

  a SECOND stand, on its own key, to show a device refusing the wrong server:
      scripts/demo-stand.sh --stand /tmp/nox-other --port 8090 --status-port 8091

INFO
