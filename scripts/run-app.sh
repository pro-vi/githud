#!/usr/bin/env bash
# run-app.sh — launch the assembled githud.app (building it first if needed).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT/build/githud.app"

[ -d "$APP_BUNDLE" ] || "$ROOT/scripts/build-app.sh"

echo "▸ launching ${APP_BUNDLE}…"
open "$APP_BUNDLE"
echo "✓ launched (menu-bar agent — look for the dot.radiowaves icon, and the island under the menu bar)"
