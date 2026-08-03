import AppKit
import GithudCore

/// `githud glyph-proof [dir]` — a one-shot render of every `StatusGlyphDescriptor` state to
/// PNG at 1x and 2x (WP-5g proof affordance; sibling of `probe`/`login-status`, which exist
/// for the same reason: some real behavior can only be witnessed from the built product).
///
/// Why it exists: the status-item window has NO rendered backing while the menu bar is
/// hidden (e.g. the active Space is full-screen), so a live screenshot of the bar isn't
/// always possible — but the drawn ink still must be witnessable (the knockout '!', the
/// dash pattern, the eye states, the α0.55 loading g, 1x vs 2x rasterization). This writes the SAME
/// `NSImage`s `StatusItemController` hands the button (via the shared `StatusGlyphRenderer`
/// — never a duplicated drawing path), rasterized at both scales. Raw template ink: black
/// alpha on transparent, exactly what the system tints per bar appearance.
///
/// Runs and exits; no GUI, no status item, no timers, no network.
enum GlyphProofCommand {
    static func run(directory: String) -> Int32 {
        // Every descriptor state the renderer can draw — the full priority/composition
        // matrix's visual half (the identity fallback is an SF Symbol, not ours to prove).
        let states: [(name: String, descriptor: StatusGlyphDescriptor)] = [
            ("clear", .clear(degraded: false)),
            ("clear-degraded", .clear(degraded: true)),
            ("clear-unconfirmed", .clearUnconfirmed(degraded: false)),
            ("clear-unconfirmed-degraded", .clearUnconfirmed(degraded: true)),
            ("action-3", .action(countText: "3", degraded: false)),
            ("action-3-degraded", .action(countText: "3", degraded: true)),
            ("critical-2", .critical(countText: "2", degraded: false)),
            ("critical-2-degraded", .critical(countText: "2", degraded: true)),
            ("loading", .loading),
        ]
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            FileHandle.standardError.write(Data("githud: glyph-proof: cannot create \(directory)\n".utf8))
            return 1
        }
        for state in states {
            let image = StatusGlyphRenderer.image(for: state.descriptor)
            for scale in [1, 2] {
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 18 * scale, pixelsHigh: 18 * scale,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
                ) else { return 1 }
                rep.size = NSSize(width: 18, height: 18)   // 18pt canvas at 1x/2x backing
                // Guard the failable init: a nil context would make image.draw a no-op and
                // silently write fully-transparent PNGs with exit 0 — a proof-integrity lie.
                guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return 1 }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = ctx
                image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
                NSGraphicsContext.restoreGraphicsState()
                guard let png = rep.representation(using: .png, properties: [:]) else { return 1 }
                let url = dir.appendingPathComponent("glyph-\(state.name)@\(scale)x.png")
                do { try png.write(to: url) } catch {
                    FileHandle.standardError.write(Data("githud: glyph-proof: write failed: \(url.path)\n".utf8))
                    return 1
                }
                print(url.path)
            }
        }
        return 0
    }
}
