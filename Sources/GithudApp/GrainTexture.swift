import AppKit

/// A single static, seeded film-grain tile — generated ONCE, cached, tiled as a pattern.
/// DETERMINISTIC (a fixed-seed LCG; no `Date`/`arc4random`) so it's identical between
/// launches and safe in headless/test contexts. STATIC (no animation, no CIFilter, no
/// timer) → drawing happens only on layout/resize, never per-frame, so idle CPU stays ~0
/// (honors the idle-footprint pressure).
enum GrainTexture {
    /// 128×128 seeded grayscale noise, generated lazily once.
    static let tile: NSImage = makeTile()

    private static func makeTile() -> NSImage {
        let side = 128
        var pixels = [UInt8](repeating: 0, count: side * side * 4)   // RGBA8
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15                     // fixed seed → reproducible
        func nextByte() -> UInt8 {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407   // LCG
            return UInt8((seed >> 56) & 0xFF)
        }
        for i in 0..<(side * side) {
            let v = nextByte()
            pixels[i * 4 + 0] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v; pixels[i * 4 + 3] = 255
        }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8,
                                  bytesPerRow: side * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = ctx.makeImage() else {
            return NSImage(size: NSSize(width: side, height: side))
        }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}

/// A subtle, static grain overlay drawn as a tiled pattern at low opacity. Non-interactive
/// (never intercepts clicks). Sits between the island surface color and the content, so the
/// texture reads through the content's gaps. Redraws only on resize → 0 idle cost.
final class GrainView: NSView {
    init(opacity: CGFloat) {
        super.init(frame: .zero)
        alphaValue = opacity
        autoresizingMask = [.width, .height]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(patternImage: GrainTexture.tile).set()
        bounds.fill()
    }

    // Never steal a click meant for a row underneath the content (content sits on top anyway).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
