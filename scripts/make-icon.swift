// make-icon.swift — render Resources/githud.icns from the mark's own geometry.
//
//   swift scripts/make-icon.swift [variant] [plate]
//     variant : night (default) · halflid · sidelong
//     plate   : dark (default) · light
//
// The mark is defined once here, in the artifact's 24x24 viewBox coordinates, and
// drawn with CoreGraphics — no SVG rasteriser, no external tool, so the icon is
// reproducible from a Command Line Tools install like everything else in this repo.
//
// Writes build/githud.iconset/*.png. `iconutil` turns that into the .icns; see
// scripts/build-app.sh, which calls this and then packs it.
//
// Layout follows the macOS icon grid: the rounded plate is 824/1024 of the canvas
// (a ~9.8% margin on each side) with a corner radius of 22.5% of the plate.
import AppKit
import CoreGraphics
import Foundation

// MARK: - the mark, in 24x24 viewBox units (y grows DOWN, as in the source SVG)

/// Everything shared by the round-five cuts: the sclera annulus and the tail.
/// Centre (12,10); the outer bowl is r=6.4 and the iris opening r=3.7, so the ring
/// itself is 2.7 units — the thinnest ink in the mark and the first thing to close
/// as the icon shrinks.
private let bowlCentre = CGPoint(x: 12, y: 10)
private let bowlOuter: CGFloat = 6.4
private let bowlInner: CGFloat = 3.7

private struct Mark {
    let pupil: (c: CGPoint, r: CGFloat)
    let catchlight: (c: CGPoint, r: CGFloat)
    /// Filled wedge over the upper iris — only the at-ease cut has one.
    let halfLid: Bool
}

private let marks: [String: Mark] = [
    // Dilated, dark-adapted. Taking its first look.
    "night":    Mark(pupil: (CGPoint(x: 12, y: 10), 2.1),
                     catchlight: (CGPoint(x: 11.15, y: 9.1), 0.65), halfLid: false),
    // The lid comes down and the pupil settles low. At ease.
    "halflid":  Mark(pupil: (CGPoint(x: 12, y: 10.4), 1.6),
                     catchlight: (CGPoint(x: 11.35, y: 9.62), 0.5), halfLid: true),
    // Pupil carried right — looking at you.
    "sidelong": Mark(pupil: (CGPoint(x: 12.8, y: 9.3), 1.7),
                     catchlight: (CGPoint(x: 12.1, y: 8.5), 0.55), halfLid: false),
]

/// The descender, as the cubic in the source path. Stroked, round-capped.
private let tailStart = CGPoint(x: 16.4, y: 14.0)
private let tailC1 = CGPoint(x: 17.9, y: 16.6), tailC2 = CGPoint(x: 17.3, y: 19.6)
private let tailEnd1 = CGPoint(x: 14.3, y: 20.5)
private let tailC3 = CGPoint(x: 13.0, y: 20.9), tailC4 = CGPoint(x: 11.8, y: 20.6)
private let tailEnd2 = CGPoint(x: 11.0, y: 19.9)
private let tailWidth: CGFloat = 2.8

// MARK: - drawing

/// Maps viewBox coordinates into the flipped, scaled device space of one icon size.
private func place(_ p: CGPoint, box: CGRect, unit: CGFloat) -> CGPoint {
    CGPoint(x: box.minX + p.x * unit, y: box.maxY - p.y * unit)
}

private func drawMark(_ mark: Mark, in ctx: CGContext, box: CGRect, ink: CGColor) {
    let unit = box.width / 24.0
    ctx.setFillColor(ink)
    ctx.setStrokeColor(ink)

    func circle(_ c: CGPoint, _ r: CGFloat) -> CGPath {
        let d = place(c, box: box, unit: unit)
        return CGPath(ellipseIn: CGRect(x: d.x - r * unit, y: d.y - r * unit,
                                        width: r * 2 * unit, height: r * 2 * unit),
                      transform: nil)
    }

    // 1 — the sclera annulus: outer bowl minus the iris opening, even-odd.
    let ring = CGMutablePath()
    ring.addPath(circle(bowlCentre, bowlOuter))
    ring.addPath(circle(bowlCentre, bowlInner))
    ctx.addPath(ring)
    ctx.fillPath(using: .evenOdd)

    // 2 — the half-lid, where the cut has one: the iris disc clipped to everything
    // above the chord, so it reads as a lid rather than a separate shape.
    if mark.halfLid {
        ctx.saveGState()
        let chordY = place(CGPoint(x: 0, y: 8.7), box: box, unit: unit).y
        ctx.clip(to: CGRect(x: box.minX, y: chordY, width: box.width, height: box.maxY - chordY))
        ctx.addPath(circle(bowlCentre, bowlInner))
        ctx.fillPath()
        ctx.restoreGState()
    }

    // 3 — the pupil, with the catchlight knocked out of it.
    let eye = CGMutablePath()
    eye.addPath(circle(mark.pupil.c, mark.pupil.r))
    eye.addPath(circle(mark.catchlight.c, mark.catchlight.r))
    ctx.addPath(eye)
    ctx.fillPath(using: .evenOdd)

    // 4 — the tail.
    let tail = CGMutablePath()
    tail.move(to: place(tailStart, box: box, unit: unit))
    tail.addCurve(to: place(tailEnd1, box: box, unit: unit),
                  control1: place(tailC1, box: box, unit: unit),
                  control2: place(tailC2, box: box, unit: unit))
    tail.addCurve(to: place(tailEnd2, box: box, unit: unit),
                  control1: place(tailC3, box: box, unit: unit),
                  control2: place(tailC4, box: box, unit: unit))
    ctx.setLineWidth(tailWidth * unit)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.addPath(tail)
    ctx.strokePath()
}

private func renderIcon(size: Int, mark: Mark, plate: CGColor, ink: CGColor) -> Data? {
    let s = CGFloat(size)
    guard let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // The macOS grid: 824/1024 plate, 185.4/1024 corner radius.
    let inset = s * (1 - 824.0 / 1024.0) / 2
    let plateRect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let radius = plateRect.width * (185.4 / 824.0)
    ctx.setFillColor(plate)
    ctx.addPath(CGPath(roundedRect: plateRect, cornerWidth: radius, cornerHeight: radius,
                       transform: nil))
    ctx.fillPath()

    // The mark sits at 70% of the plate, centred. The artifact's mocks used 62%, which
    // is right for a tile shown next to prose but leaves a Dock icon looking sparse;
    // 70% keeps clear of the corner radius at every rung. One number, easy to retune.
    let markSide = plateRect.width * 0.70
    let markBox = CGRect(x: plateRect.midX - markSide / 2, y: plateRect.midY - markSide / 2,
                         width: markSide, height: markSide)
    drawMark(mark, in: ctx, box: markBox, ink: ink)

    guard let image = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
}

// MARK: - main

let args = CommandLine.arguments
let variant = args.count > 1 ? args[1] : "night"
let plateName = args.count > 2 ? args[2] : "dark"

guard let mark = marks[variant] else {
    FileHandle.standardError.write(Data("make-icon: unknown variant '\(variant)' — expected one of \(marks.keys.sorted().joined(separator: ", "))\n".utf8))
    exit(64)
}

// Ink and plate are the app's own two grounds, not arbitrary greys: the dark plate
// is the island's surface, the light one the menu bar's.
let (plateColor, inkColor): (CGColor, CGColor) = plateName == "light"
    ? (CGColor(red: 0.949, green: 0.949, blue: 0.961, alpha: 1),
       CGColor(red: 0.086, green: 0.094, blue: 0.110, alpha: 1))
    : (CGColor(red: 0.110, green: 0.125, blue: 0.149, alpha: 1),
       CGColor(red: 0.941, green: 0.949, blue: 0.961, alpha: 1))

// Every rung iconutil requires. A missing one fails the whole pack.
let rungs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outDir = root.appendingPathComponent("build/githud.iconset")
try? FileManager.default.removeItem(at: outDir)
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for rung in rungs {
    guard let png = renderIcon(size: rung.px, mark: mark, plate: plateColor, ink: inkColor) else {
        FileHandle.standardError.write(Data("make-icon: failed to render \(rung.name)\n".utf8))
        exit(1)
    }
    try png.write(to: outDir.appendingPathComponent("\(rung.name).png"))
}

print("✓ \(rungs.count) rungs → \(outDir.path)  (\(variant), \(plateName) plate)")
