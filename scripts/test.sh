#!/usr/bin/env bash
# test.sh — the canonical test command (ramp stage 1).
#
# XCTest and swift-testing both require full Xcode, which the githud stack rules
# out. So GithudCoreTests is a zero-dep executable runner; this builds and runs
# it, exiting non-zero if any check fails. Use this, not `swift test`.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-debug}"
echo "▸ swift run GithudCoreTests (-c $CONFIG)…"
swift run -c "$CONFIG" GithudCoreTests
