#!/usr/bin/env bash
# visual-proof.sh — native visual proof. Capture + inspect → a content-addressed,
# provenance-stamped manifest per (condition × scenario). The MANIFEST is the
# proof, not the screenshot's existence. (/visual-proof is browser-only — routes,
# DOM, viewports, WCAG — and does NOT apply to a native AppKit app.)
#
# Without Screen Recording permission, screencapture yields black frames, so the
# manifest records status=skipped, reason=no_screen_recording and the visual
# criterion stays capped at 2. NEVER fabricate a passing manifest.
#
# The loop exports GITHUD_SCREEN_REC=1 ONLY when the screen_recording_permission
# gate in STATE is literally yes.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
APP_NAME="githud"
ITER="${ITER:-0}"
CONDITION="${CONDITION:-idle}"
SCENARIO="${SCENARIO:-normal-desktop}"
SCREEN_REC="${GITHUD_SCREEN_REC:-0}"
EVID="$ROOT/loop/evidence"
mkdir -p "$EVID"

STAMP="$CONDITION-$SCENARIO-$ITER"
PNG="$EVID/$STAMP.png"
MANIFEST="$EVID/$STAMP.manifest.json"
PROBE_FILE="$(mktemp)"
trap 'rm -f "$PROBE_FILE"' EXIT
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Only idle × normal-desktop is automated in bootstrap. The other conditions
# (notification-arrived / hover-expanded / inspector-open) and scenarios
# (over-fullscreen-space / stage-manager / second-monitor) are NOT yet scripted —
# logged here so a skipped condition never reads as covered.
if [ "$CONDITION" != "idle" ] || [ "$SCENARIO" != "normal-desktop" ]; then
    echo "⚠ ${CONDITION}×${SCENARIO} not yet automated (bootstrap covers idle×normal-desktop only)." >&2
fi

echo "▸ build…"
swift build -c "$CONFIG" >/dev/null
BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"

FRONT_BEFORE="$(lsappinfo front 2>/dev/null || echo unknown)"

echo "▸ launch…"
# GITHUD_ARGS lets a caller render a populated island, e.g.
#   GITHUD_ARGS="--fixture Tests/Fixtures/notifications.json" CONDITION=hover-expanded
# shellcheck disable=SC2086
"$BIN" ${GITHUD_ARGS:-} &
PID=$!
cleanup() { kill "$PID" 2>/dev/null || true; rm -f "$PROBE_FILE"; }
trap cleanup EXIT

echo "▸ waiting for HUD window…"
PROBE_OK=0
for _ in $(seq 1 40); do
    if swift "$ROOT/scripts/window-probe.swift" "$PID" > "$PROBE_FILE" 2>/dev/null; then
        PROBE_OK=1; break
    fi
    sleep 0.25
done
if [ "$PROBE_OK" -ne 1 ]; then
    echo "✗ no HUD window; cannot produce a manifest" >&2
    exit 1
fi

# Settle, then read idle CPU and frontmost (focus-non-theft witness).
sleep 1.0
IDLE_CPU="$(ps -o %cpu= -p "$PID" 2>/dev/null | tr -d ' ')"
[ -z "${IDLE_CPU:-}" ] && IDLE_CPU="null"
FRONT_AFTER="$(lsappinfo front 2>/dev/null || echo unknown)"

# Pixel capture — only meaningful with Screen Recording permission. Capture JUST
# the island region (privacy + precision), not the whole desktop. The PNG is
# gitignored; only the manifest (sha + stats, no image) is committed.
STATUS="captured"
REASON=""
PNG_SHA="null"
PIXEL_LIVE="null"
PIXEL_STATS="null"
if [ "$SCREEN_REC" = "1" ] && swift "$ROOT/scripts/screen-locked.swift" 2>/dev/null; then
    # The screen is LOCKED — a capture would grab the lock screen, not the island.
    # Refuse to claim a (false) pixel_live. The window geometry below is still real.
    STATUS="skipped"; REASON="screen_locked"
elif [ "$SCREEN_REC" = "1" ]; then
    # island region from the probe (largest non-zero window for our pid) — CG top-left points
    REGION="$(python3 -c "import json; d=json.load(open('$PROBE_FILE')); ws=[w for w in d['windows'] if w['w']>1 and w['h']>1]; w=max(ws,key=lambda x:x['w']*x['h']); print(f\"{int(w['x'])},{int(w['y'])},{int(w['w'])},{int(w['h'])}\")" 2>/dev/null || true)"
    if [ -n "$REGION" ] && screencapture -x -R"$REGION" "$PNG" 2>/dev/null; then
        PNG_SHA="$(shasum -a 256 "$PNG" | awk '{print $1}')"
        if PIXEL_STATS="$(swift "$ROOT/scripts/pixel-stats.swift" "$PNG" 2>/dev/null)"; then
            PIXEL_LIVE="true"
        else
            PIXEL_LIVE="false"; REASON="island_region_blank"
        fi
        [ -z "$PIXEL_STATS" ] && PIXEL_STATS="null"
    else
        STATUS="error"; REASON="screencapture_or_region_failed"
    fi
else
    STATUS="skipped"; REASON="no_screen_recording"
fi

PROBE_FILE="$PROBE_FILE" \
CONDITION="$CONDITION" SCENARIO="$SCENARIO" ITER="$ITER" \
STATUS="$STATUS" REASON="$REASON" \
PNG_PATH="loop/evidence/$STAMP.png" PNG_SHA="$PNG_SHA" PIXEL_LIVE="$PIXEL_LIVE" PIXEL_STATS="$PIXEL_STATS" \
IDLE_CPU="$IDLE_CPU" CONDITION_IS_IDLE="$([ "$CONDITION" = idle ] && echo 1 || echo 0)" \
FRONT_BEFORE="$FRONT_BEFORE" FRONT_AFTER="$FRONT_AFTER" \
CAPTURED_AT="$CAPTURED_AT" COMMIT="$COMMIT" \
MANIFEST="$MANIFEST" \
python3 - <<'PY'
import json, os

probe = json.load(open(os.environ["PROBE_FILE"]))
prim = None
for w in probe.get("windows", []):
    if w["w"] > 1 and w["h"] > 1 and (prim is None or w["w"]*w["h"] > prim["w"]*prim["h"]):
        prim = w

def numornull(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

manifest = {
    "condition": os.environ["CONDITION"],
    "scenario": os.environ["SCENARIO"],
    "iter": int(os.environ["ITER"]),
    "status": os.environ["STATUS"],
    "reason": os.environ["REASON"] or None,
    "png": os.environ["PNG_PATH"],
    "png_sha256": None if os.environ["PNG_SHA"] == "null" else os.environ["PNG_SHA"],
    "window_bounds": ({"x": prim["x"], "y": prim["y"], "w": prim["w"], "h": prim["h"]} if prim else None),
    "within_screen": probe.get("withinScreen"),
    "size_class": probe.get("primarySizeClass"),
    "frontmost_unchanged": os.environ["FRONT_BEFORE"] == os.environ["FRONT_AFTER"],
    "frontmost_before": os.environ["FRONT_BEFORE"],
    "frontmost_after": os.environ["FRONT_AFTER"],
    "pixel_live": None if os.environ["PIXEL_LIVE"] == "null" else (os.environ["PIXEL_LIVE"] == "true"),
    "pixel_stats": (json.loads(os.environ["PIXEL_STATS"]) if os.environ.get("PIXEL_STATS", "null") not in ("", "null") else None),
    "idle_cpu": (numornull(os.environ["IDLE_CPU"]) if os.environ["CONDITION_IS_IDLE"] == "1" else None),
    "captured_at": os.environ["CAPTURED_AT"],
    "commit": os.environ["COMMIT"],
    "screen": probe.get("screen"),
    "window_count": probe.get("count"),
}
with open(os.environ["MANIFEST"], "w") as f:
    json.dump(manifest, f, indent=2, sort_keys=True)
    f.write("\n")
print(json.dumps(manifest, indent=2, sort_keys=True))
PY

echo "✓ manifest → $MANIFEST"
