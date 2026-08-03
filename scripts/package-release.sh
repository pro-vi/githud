#!/usr/bin/env bash
# package-release.sh — turn build/githud.app into a distributable artifact
# (release WP Phase 0, U5). Credential-guarded, Gitify's NOTARIZE-flag pattern:
# every privileged step degrades to a loud skip when its credential is absent,
# so this script is runnable — and the release workflow useful — before an
# Apple Developer membership exists (Phase 1 just sets the env).
#
#   DEVELOPER_ID_IDENTITY  "Developer ID Application: …"  → real sign + hardened runtime
#   NOTARY_KEYCHAIN_PROFILE  notarytool keychain profile   → notarize + staple
#
# Output: build/githud-<version>.zip (labeled unsigned when unsigned).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/build/githud.app"
[ -d "$APP" ] || { echo "✗ $APP missing — run scripts/build-app.sh first" >&2; exit 1; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"

SIGNED=0
if [ -n "${DEVELOPER_ID_IDENTITY:-}" ]; then
  echo "▸ codesign (Developer ID, hardened runtime, entitlements)…"
  codesign --force --options runtime --timestamp \
           --entitlements "$ROOT/Resources/githud.entitlements" \
           --sign "$DEVELOPER_ID_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  SIGNED=1
else
  echo "▸ SKIP sign: DEVELOPER_ID_IDENTITY not set — artifact will be UNSIGNED (ad-hoc)"
  codesign --force --sign - "$APP"
fi

if [ "$SIGNED" = "1" ] && [ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  echo "▸ notarize (notarytool, profile $NOTARY_KEYCHAIN_PROFILE)…"
  NZIP="$ROOT/build/githud-notarize.zip"
  ditto -c -k --keepParent "$APP" "$NZIP"
  xcrun notarytool submit "$NZIP" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  rm -f "$NZIP"
  echo "▸ staple…"
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
  spctl -a -vvv -t install "$APP" || { echo "✗ Gatekeeper rejected the stapled app" >&2; exit 1; }
elif [ "$SIGNED" = "1" ]; then
  echo "▸ SKIP notarize: NOTARY_KEYCHAIN_PROFILE not set — signed but NOT notarized"
fi

SUFFIX=""; [ "$SIGNED" = "0" ] && SUFFIX="-unsigned"
OUT="$ROOT/build/githud-${VERSION}${SUFFIX}.zip"
echo "▸ zip → $OUT"
rm -f "$OUT"
ditto -c -k --keepParent "$APP" "$OUT"
shasum -a 256 "$OUT"
echo "✓ packaged $OUT"
