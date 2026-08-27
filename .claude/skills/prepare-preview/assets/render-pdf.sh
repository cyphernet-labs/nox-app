#!/usr/bin/env bash
# Render a change-preview markdown brief to a styled PDF via headless Google Chrome.
# Usage: render-pdf.sh <input.md> <output.pdf>
# Colored markers (🟢🟡🔴), ⚠️ callouts and ```mermaid diagrams all render. Needs network on first run
# (marked + mermaid load from the jsDelivr CDN). Verified recipe — do not "simplify" without re-testing.
set -euo pipefail

MD="${1:?usage: render-pdf.sh <input.md> <output.pdf>}"
PDF="${2:?usage: render-pdf.sh <input.md> <output.pdf>}"
DIR="$(cd "$(dirname "$0")" && pwd)"

CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[ -x "$CHROME" ] || { echo "Google Chrome not found at: $CHROME" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
WRAP="$TMP/wrapper.html"
{ cat "$DIR/head.html"; cat "$MD"; cat "$DIR/tail.html"; } > "$WRAP"

rm -f "$PDF"

# An isolated profile is REQUIRED: sharing the default user-data-dir with a running Chrome makes the print
# silently emit a blank ~900-byte PDF. Chrome also often fails to exit after writing, so run it detached and
# wait for the file instead of for the process.
# task_policy_set warnings on macOS are harmless; the PDF is still written.
"$CHROME" --headless=new --disable-gpu --user-data-dir="$TMP/profile" \
  --no-pdf-header-footer --run-all-compositor-stages-before-draw \
  --virtual-time-budget=20000 --print-to-pdf="$PDF" "file://$WRAP" >/dev/null 2>&1 &
CHROME_PID=$!

for _ in $(seq 1 60); do
  sleep 1
  [ -s "$PDF" ] && sleep 2 && break
done
kill "$CHROME_PID" 2>/dev/null || true
wait "$CHROME_PID" 2>/dev/null || true

SIZE=$([ -f "$PDF" ] && wc -c < "$PDF" | tr -d ' ' || echo 0)

# A blank page is ~900 bytes; any real brief with embedded fonts is tens of KB. Treat blank as a failure.
if [ "$SIZE" -gt 20000 ]; then
  echo "PDF written: $PDF ($SIZE bytes)"
else
  echo "PDF generation FAILED — got $SIZE bytes (a blank page is ~900)." >&2
  echo "Check: Chrome installed, network for the jsDelivr CDN, and no mermaid syntax error in the brief." >&2
  exit 1
fi
