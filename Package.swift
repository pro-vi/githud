// swift-tools-version:5.9
import PackageDescription

// githud — native AppKit macOS GitHub HUD overlay.
// SwiftPM executable (no full Xcode). Swift 5 language mode for the AppKit
// scaffold; concurrency-strict (Swift 6) mode is deferred until the networking
// spine lands, where it earns its keep. See loop/STATE Alignment Review.
let package = Package(
    name: "githud",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, headless-testable logic (geometry now; GitHub client / models /
        // polling later). No AppKit, no app entry point — unit-testable without a
        // window server.
        .target(
            name: "GithudCore",
            path: "Sources/GithudCore"
        ),
        // The app shell: NSApplication entry, status item, overlay panel.
        .executableTarget(
            name: "githud",
            dependencies: ["GithudCore"],
            path: "Sources/GithudApp"
        ),
        // Zero-dep test runner (executable, not a .testTarget): XCTest /
        // swift-testing ship with full Xcode, which the stack rules out. Run via
        // scripts/test.sh. `swift test` is unavailable under CLT-only.
        .executableTarget(
            name: "GithudCoreTests",
            dependencies: ["GithudCore"],
            path: "Tests/GithudCoreTests"
        ),
    ]
)
