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

# task_policy_set warnings on macOS are harmless; the PDF is still written.
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --run-all-compositor-stages-before-draw \
  --virtual-time-budget=20000 --print-to-pdf="$PDF" "file://$WRAP" >/dev/null 2>&1 || true

if [ -s "$PDF" ]; then
  echo "PDF written: $PDF ($(wc -c < "$PDF" | tr -d ' ') bytes)"
else
  echo "PDF generation FAILED — check that Chrome is installed and the machine has network for the CDN." >&2
  exit 1
fi
