#!/usr/bin/env bash
# screenshots.sh — regenerate the README images from committed fixtures.
#
# Every shot is driven by Tests/Fixtures/*, never by a live account, so the images
# are deterministic and contain no real data. Each run launches the app with the
# fixture flags, asks CGWindowList where the island actually is, and captures only
# that rectangle — the desktop behind it is never published.
#
#   scripts/screenshots.sh            # write to docs/images/
#   OUT=/tmp/shots scripts/screenshots.sh
#
# Needs Screen Recording permission for the terminal, or screencapture returns
# black frames; the script checks each frame and fails loudly rather than
# committing a black rectangle.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT="${OUT:-docs/images}"
BIN="build/githud.app/Contents/MacOS/githud"
MARGIN="${MARGIN:-18}"      # points of slack so the island's shadow is not clipped

[ -x "$BIN" ] || { echo "build first: scripts/build-app.sh" >&2; exit 1; }
mkdir -p "$OUT"

stop_all() { pkill -f 'githud.app/Contents/MacOS/githud' 2>/dev/null; sleep 1; }

# shoot <name> [app args…]
shoot() {
  local name="$1"; shift
  stop_all
  "$BIN" "$@" &
  local pid=$! probe x y w h sw sh
  sleep 5                                   # let the panel seat + settle its animation

  # The app can own more than one window (the collapsed pill AND the island). Pick the
  # LARGEST by area — a positional parse silently grabbed the 60x36 pill instead.
  probe=$(swift scripts/window-probe.swift "$pid" 2>/dev/null)
  read -r x y w h sw sh <<<"$(printf '%s' "$probe" | python3 -c '
import json,sys
d = json.load(sys.stdin)
ws = [w for w in d["windows"] if w["w"] * w["h"] > 0]
if not ws:
    sys.exit(1)
b = max(ws, key=lambda w: w["w"] * w["h"])
s = d["screen"]
print(b["x"], b["y"], b["w"], b["h"], s["w"], s["h"])
')"
  if [ -z "${w:-}" ] || [ "${w:-0}" -eq 0 ]; then
    echo "✗ $name: no on-screen window for pid $pid" >&2; kill "$pid" 2>/dev/null; return 1
  fi

  # Grow by MARGIN, then clamp to the screen so screencapture never gets a negative origin.
  x=$((x - MARGIN)); [ "$x" -lt 0 ] && x=0
  y=$((y - MARGIN)); [ "$y" -lt 0 ] && y=0
  w=$((w + MARGIN * 2)); [ $((x + w)) -gt "$sw" ] && w=$((sw - x))
  h=$((h + MARGIN * 2)); [ $((y + h)) -gt "$sh" ] && h=$((sh - y))

  screencapture -x -o -R"${x},${y},${w},${h}" "$OUT/$name.png"
  kill "$pid" 2>/dev/null

  # A frame captured without Screen Recording permission is uniformly black.
  if ! swift scripts/pixel-stats.swift "$OUT/$name.png" >/dev/null 2>&1; then
    echo "✗ $name: black/dead frame — grant Screen Recording to your terminal" >&2
    return 1
  fi
  echo "✓ $OUT/$name.png  (${w}×${h}pt)"
}

F=Tests/Fixtures

# The hero: all three lanes at once.
shoot island-all-lanes \
  --fixture "$F/notifications.json" \
  --fixture-pulse "$F/pulls.json" \
  --fixture-inbound "$F/inbound-search.json" --show-drafts

# One lane at a time.
shoot island-needs-you   --fixture "$F/notifications.json"
shoot island-your-prs    --fixture-pulse "$F/pulls-three-region.json" --show-drafts --show-stale
shoot island-inbound     --fixture-inbound "$F/inbound-search.json"

# The collapsed pill — how githud looks almost all the time.
shoot pill-collapsed     --fixture "$F/notifications.json" --collapsed

# Themes: the same data, three ways.
shoot theme-color        --fixture "$F/notifications.json" --theme color
shoot theme-geist-mono   --fixture "$F/notifications.json" --theme geist-mono
shoot theme-tokyo-night  --fixture "$F/notifications.json" --theme tokyo-night

stop_all
echo "done → $OUT"
