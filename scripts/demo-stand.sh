#!/usr/bin/env bash
# Brings up a clean NOX stand for a demo, and prints what to do with it.
#
# The default -addr is loopback, which is right for development and useless
# here: a phone cannot dial 127.0.0.1, so the service page draws no code. This
# binds every interface, which is how a household server actually runs, and the
# link then carries an address a phone can reach.
set -euo pipefail

PORT="${PORT:-8080}"
STATUS_PORT="${STATUS_PORT:-8081}"
STAND="${STAND:-/tmp/nox-demo}"
RESET_APP=0

for arg in "$@"; do
  case "$arg" in
    --reset-app) RESET_APP=1 ;;
    -h|--help)
      echo "usage: scripts/demo-stand.sh [--reset-app]"
      echo
      echo "  --reset-app   also wipe the macOS app's data, so the next launch"
      echo "                is a genuine first install (container + keychain)"
      exit 0
      ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> building noxd"
(cd client_backend && go build -o "$STAND-noxd" .)

echo "==> stopping any stand left from last time"
pkill -f "$STAND-noxd" 2>/dev/null || true
sleep 1

echo "==> fresh database in $STAND"
rm -rf "$STAND" && mkdir -p "$STAND"

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
sleep 2

# Two links, one token. The startup line addresses the machine itself, because
# that is who reads a terminal; the page addresses the network, because that is
# who reads a QR off a screen. Same right, different reader.
local_link="$(grep -oE 'https://nox.app/p/#[A-Za-z0-9_-]+' "$STAND/server.log" | head -1 || true)"
page_link="$(curl -fsS "http://127.0.0.1:$STATUS_PORT/" 2>/dev/null \
  | grep -oE 'https://nox.app/p/#[A-Za-z0-9_-]+' | head -1 || true)"
if [ -z "$local_link" ]; then
  echo "the server printed no claim link:" >&2
  cat "$STAND/server.log" >&2
  exit 1
fi

cat <<INFO

  stand up

  service page   http://127.0.0.1:$STATUS_PORT      (this machine only)
  server         0.0.0.0:$PORT
  database       $STAND/nox.db
  log            $STAND/server.log

  claim link for an app on THIS machine
  $local_link

  claim link for a phone (the one the page shows as a QR)
  ${page_link:-none: this machine has no address another device could reach}

  check it works, without clicking anything:
      (cd client_backend && go run ./cmd/smoke '$local_link')
      # then re-run this script: the smoke test claims the server

  or run the demo by hand:
      open http://127.0.0.1:$STATUS_PORT
      fvm flutter run -d macos --dart-define-from-file=config/stage.json

INFO
