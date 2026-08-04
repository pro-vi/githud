#!/usr/bin/env bash
# build-app.sh — compile githud and assemble a runnable .app bundle.
#   swift build → copy binary into Contents/MacOS → copy Info.plist → ad-hoc codesign.
# Ad-hoc signing (--sign -) is intentional: no Developer ID in the loop. See STATE.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="githud"
APP_BUNDLE="$ROOT/build/$APP_NAME.app"

# UNIVERSAL=1 → arm64+x86_64 fat binary via per-triple builds + lipo (release WP
# Phase 0, U2). Two triples, not `--arch a --arch b`: the multi-arch flag needs
# full Xcode's xcbuild, and this must work on CLT-only machines and CI alike.
# Default: host arch — the dev inner loop stays fast.
if [ "${UNIVERSAL:-0}" = "1" ]; then
  echo "▸ swift build (-c $CONFIG, universal via lipo)…"
  FAT_DIR="$ROOT/build"
  mkdir -p "$FAT_DIR"
  for TRIPLE in arm64-apple-macosx x86_64-apple-macosx; do
    echo "  ▸ $TRIPLE"
    swift build -c "$CONFIG" --triple "$TRIPLE"
  done
  BIN="$FAT_DIR/$APP_NAME-universal"
  lipo -create \
    "$(swift build -c "$CONFIG" --triple arm64-apple-macosx --show-bin-path)/$APP_NAME" \
    "$(swift build -c "$CONFIG" --triple x86_64-apple-macosx --show-bin-path)/$APP_NAME" \
    -output "$BIN"
else
  echo "▸ swift build (-c $CONFIG)…"
  swift build -c "$CONFIG"
  BIN="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
fi
[ -x "$BIN" ] || { echo "✗ binary not found at $BIN" >&2; exit 1; }

echo "▸ assembling ${APP_BUNDLE}…"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

# The app icon. githud is an LSUIElement agent so this never reaches the Dock, but it
# is what Finder, Get Info, the download, and the Gatekeeper dialog show — the first
# thing anyone installing it sees. Regenerate with scripts/make-icon.swift.
if [ -f "$ROOT/Resources/githud.icns" ]; then
  cp "$ROOT/Resources/githud.icns" "$APP_BUNDLE/Contents/Resources/githud.icns"
else
  echo "⚠ Resources/githud.icns missing — bundle will fall back to the generic app icon" >&2
fi

# Version stamping (release WP Phase 0, U1): VERSION env (e.g. a release tag)
# overrides the checked-in dev placeholder; CFBundleVersion gets a monotonic
# build number (commit count) so update logic can compare builds.
if [ -n "${VERSION:-}" ]; then
  BUILD_NUM="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" \
                          -c "Set :CFBundleVersion $BUILD_NUM" \
                          "$APP_BUNDLE/Contents/Info.plist"
  echo "▸ stamped version ${VERSION#v} (build $BUILD_NUM)"
fi

echo "▸ ad-hoc codesign…"
codesign --force --sign - "$APP_BUNDLE"

echo "✓ built $APP_BUNDLE"
