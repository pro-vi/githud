#!/bin/zsh
# Compile the real AppKit views into an offscreen regression renderer.
# These images check view layout, not window-server input routing or vibrancy.
set -euo pipefail
cd "${0:A:h}/../.."
SNAPSHOT_OUTPUT="${1:-$(mktemp -d /tmp/githud-snapshots-XXXXXX)}"
mkdir -p "$SNAPSHOT_OUTPUT"
swift build -c release --target GithudCore
SNAPSHOT_BIN_DIR=$(swift build -c release --show-bin-path)
SNAPSHOT_SOURCES=(Sources/GithudApp/*.swift)
SNAPSHOT_SOURCES=("${(@)SNAPSHOT_SOURCES:#Sources/GithudApp/main.swift}")
swiftc -I "$SNAPSHOT_BIN_DIR/Modules" "${SNAPSHOT_SOURCES[@]}" \
    Tests/GithudAppSnapshots/main.swift "$SNAPSHOT_BIN_DIR"/GithudCore.build/*.o \
    -o "$SNAPSHOT_OUTPUT/render"
"$SNAPSHOT_OUTPUT/render" "$SNAPSHOT_OUTPUT"
printf 'Native view renders: %s\n' "$SNAPSHOT_OUTPUT"
