#!/usr/bin/env bash
# validate.sh — the smoke validator (ramp stage 3).
#   build → launch bare binary → assert the HUD window is on screen
#   (CGWindowList, permission-free) → screenshot to evidence → kill.
#
# Named false greens this guards against:
#   - "builds but the panel never appears"  → caught: CGWindowList shows no window.
#   - "process dies on launch"               → caught: probe finds nothing, we fail.
#   - "window exists but zero-area/offscreen"→ caught: area_nonzero + bounds check.
# NOT yet guarded (later ramp stage 4): focus theft, Spaces/full-screen behavior.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
APP_NAME="githud"
ITER="${ITER:-0}"
EVID="$ROOT/loop/evidence"
mkdir -p "$EVID"

echo "▸ build (-c $CONFIG)…"
swift build -c "$CONFIG" >/dev/null
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

echo "▸ launch (background)…"
"$BIN" &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; }
trap cleanup EXIT

echo "▸ waiting for HUD window (pid $PID)…"
PROBE_OUT=""
PROBE_RC=2
for _ in $(seq 1 40); do
    if ! kill -0 "$PID" 2>/dev/null; then
        echo "✗ FALSE GREEN: process exited before a window appeared" >&2
        exit 1
    fi
    if PROBE_OUT="$(swift "$ROOT/scripts/window-probe.swift" "$PID" 2>/dev/null)"; then
        PROBE_RC=0
        break
    fi
    sleep 0.25
done

if [ "$PROBE_RC" -ne 0 ]; then
    echo "✗ FALSE GREEN: process alive but no non-zero HUD window in CGWindowList" >&2
    echo "$PROBE_OUT" >&2
    exit 1
fi

echo "$PROBE_OUT" > "$EVID/validate-window-$ITER.json"
echo "✓ HUD window on screen:"
echo "$PROBE_OUT"

# Screenshot to evidence. Black without Screen Recording permission — captured
# either way; the manifest (visual-proof.sh) is the real visual proof.
SHOT="$EVID/validate-$ITER.png"
if screencapture -x "$SHOT" 2>/dev/null; then
    echo "▸ screenshot → $SHOT (black if Screen Recording permission not granted)"
else
    echo "▸ screencapture unavailable; skipped"
fi

echo "✓ validate passed"
