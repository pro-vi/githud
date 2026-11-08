// make-sting.swift — render the githud mark's opening sting as PNG frames.
//
//   swift scripts/make-sting.swift <out-dir> [fps] [width] [height]
//     out-dir : where the NNNN.png frames go (created if missing; NNNN.png files already there are removed)
//     fps     : frames per second (default 60)
//     width   : frame width in px (default 1920)
//     height  : frame height in px (default 1080)
//
// Same geometry as scripts/make-icon.swift (24x24 viewBox units), drawn with
// CoreGraphics on a transparent canvas. The icon's "night" cut is the first pose;
// the look-right, look-left and rest poses are this script's own.
//
//   0.00–0.40  the bowl scales in
//   0.35–0.85  the disc dilates from nothing to the "night" cut — first look
//   0.55–1.15  the g tail draws in
//   1.20–1.50  look right (the site's cursor-follow reach, 1.5 units)
//   1.60–1.90  sweep to the left
//   1.90–2.10  return to centre, looking straight out
//   2.05–2.85  the squint: the lid slants down to about half on the right, holds, opens back
//   2.70–3.20  wordmark rises in
//   3.20–3.60  hold, eye open
//
// The frames are transparent PNGs; ffmpeg turns them into the three deliverables.
// From the repo root, with the frames in build/sting/frames, at the default rate and size:
//
//   swift scripts/make-sting.swift build/sting/frames 60 1920 1080
//   cd build/sting
//   # h264 over the site's ground colour, for the release film and README
//   ffmpeg -y -f lavfi -i color=c=0x0c0e12:s=1920x1080:r=60 -framerate 60 -i frames/%04d.png \
//     -filter_complex "[0:v][1:v]overlay=shortest=1,format=yuv420p" -c:v libx264 -crf 18 -preset slow githud-sting.mp4
//   # ProRes 4444 with alpha, for compositing over anything else
//   ffmpeg -y -framerate 60 -i frames/%04d.png -c:v prores_ks -profile:v 4444 -pix_fmt yuva444p10le githud-sting-alpha.mov
//   # 480px looping GIF
//   ffmpeg -y -i githud-sting.mp4 -vf "fps=30,scale=480:-1:flags=lanczos,split[a][b];[a]palettegen[p];[b][p]paletteuse=dither=sierra2_4a" \
//     -loop 0 githud-sting-480.gif
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else { fputs("usage: swift scripts/make-sting.swift <out-dir> [fps] [width] [height]\n", stderr); exit(64) }
let outDir = args[1]
let fps = args.count > 2 ? Double(args[2])! : 60
let W = args.count > 3 ? Int(args[3])! : 1920
let H = args.count > 4 ? Int(args[4])! : 1080
let duration = 3.6

// MARK: - geometry (viewBox units, y down)
let bowlCentre = CGPoint(x: 12, y: 10)
let bowlOuter: CGFloat = 6.4, bowlInner: CGFloat = 3.7
let lidX0 = bowlCentre.x - bowlInner, lidX1 = bowlCentre.x + bowlInner   // where the lid heights are measured: the opening's edges
let openChord: CGFloat = 6.3                                              // lid fully up: covers nothing
// The squint is asymmetric: the lid barely moves on the left and comes about halfway
// down on the right, so the eye narrows on one side. That slant is the expression.
let squintL: CGFloat = 8.6, squintR: CGFloat = 10.4

// In the icon the white disc is the pupil and the dark dot its catchlight. At title size
// on the dark ground the disc reads as the eyeball and the dot as the pupil, so here the
// dot is larger, sits inside the disc, and leads the gaze.
struct Pose { var disc: CGPoint; var discR: CGFloat; var dot: CGPoint; var dotR: CGFloat }
func pose(_ disc: CGPoint, _ discR: CGFloat, dot: CGPoint, _ dotR: CGFloat) -> Pose {
    Pose(disc: disc, discR: discR, dot: CGPoint(x: disc.x + dot.x, y: disc.y + dot.y), dotR: dotR)
}
let night     = pose(bowlCentre,                   2.1, dot: CGPoint(x: -0.45, y: -0.50), 0.85)
let lookRight = pose(CGPoint(x: 13.5, y: 9.65),   2.0, dot: CGPoint(x:  0.60, y: -0.30), 0.80)
let lookLeft  = pose(CGPoint(x: 10.5, y: 9.80),   2.0, dot: CGPoint(x: -0.60, y: -0.30), 0.80)
let rest      = pose(bowlCentre,                   2.1, dot: CGPoint(x:  0.00, y:  0.05), 0.70)   // open, full-size, looking straight out
let empty     = Pose(disc: night.disc, discR: 0, dot: night.dot, dotR: 0)                      // the bowl alone, before the dilation

let tailStart = CGPoint(x: 16.4, y: 14.0)
let tailC1 = CGPoint(x: 17.9, y: 16.6), tailC2 = CGPoint(x: 17.3, y: 19.6), tailEnd1 = CGPoint(x: 14.3, y: 20.5)
let tailC3 = CGPoint(x: 13.0, y: 20.9), tailC4 = CGPoint(x: 11.8, y: 20.6), tailEnd2 = CGPoint(x: 11.0, y: 19.9)
let tailWidth: CGFloat = 2.8

// Flattened tail with cumulative arc length, so a fraction of it can be stroked.
func cubic(_ p0: CGPoint, _ c1: CGPoint, _ c2: CGPoint, _ p3: CGPoint, _ t: CGFloat) -> CGPoint {
    let u = 1 - t
    let x = u*u*u*p0.x + 3*u*u*t*c1.x + 3*u*t*t*c2.x + t*t*t*p3.x
    let y = u*u*u*p0.y + 3*u*u*t*c1.y + 3*u*t*t*c2.y + t*t*t*p3.y
    return CGPoint(x: x, y: y)
}
let tailSteps = 60
var tailPts: [CGPoint] = []
for i in 0...tailSteps { tailPts.append(cubic(tailStart, tailC1, tailC2, tailEnd1, CGFloat(i)/CGFloat(tailSteps))) }
for i in 1...tailSteps { tailPts.append(cubic(tailEnd1, tailC3, tailC4, tailEnd2, CGFloat(i)/CGFloat(tailSteps))) }
var tailLen: [CGFloat] = [0]
for i in 1..<tailPts.count { tailLen.append(tailLen[i-1] + hypot(tailPts[i].x - tailPts[i-1].x, tailPts[i].y - tailPts[i-1].y)) }
let tailTotal = tailLen.last!

// MARK: - easing and timeline
func seg(_ t: Double, _ a: Double, _ b: Double) -> Double { max(0, min(1, (t - a) / (b - a))) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
func easeInOut(_ x: Double) -> Double { x < 0.5 ? 4*x*x*x : 1 - pow(-2*x + 2, 3) / 2 }
func lerp(_ a: CGFloat, _ b: CGFloat, _ f: Double) -> CGFloat { a + (b - a) * CGFloat(f) }
func lerp(_ a: CGPoint, _ b: CGPoint, _ f: Double) -> CGPoint { CGPoint(x: lerp(a.x, b.x, f), y: lerp(a.y, b.y, f)) }
func mix(_ a: Pose, _ b: Pose, _ f: Double) -> Pose {
    Pose(disc: lerp(a.disc, b.disc, f), discR: lerp(a.discR, b.discR, f), dot: lerp(a.dot, b.dot, f), dotR: lerp(a.dotR, b.dotR, f))
}

struct Frame { var bowl: Double; var pose: Pose; var squint: Double; var tail: Double; var word: Double }
func frame(at t: Double) -> Frame {
    var p: Pose
    if t >= 1.90      { p = mix(lookLeft, rest, easeInOut(seg(t, 1.90, 2.10))) }
    else if t >= 1.60 { p = mix(lookRight, lookLeft, easeInOut(seg(t, 1.60, 1.90))) }
    else if t >= 1.20 { p = mix(night, lookRight, easeInOut(seg(t, 1.20, 1.50))) }
    else              { p = mix(empty, night, easeOut(seg(t, 0.35, 0.85))) }
    // One squint: the lid slants down over the disc, holds a beat with the dot peering
    // out from under it, then opens back. Disc and dot dip a touch with it.
    let down = easeInOut(seg(t, 2.05, 2.28)), up = easeInOut(seg(t, 2.60, 2.85))
    let squint = down * (1 - up)
    p.disc.y += 0.20 * CGFloat(squint); p.dot.y += 0.25 * CGFloat(squint)
    return Frame(bowl: easeOut(seg(t, 0.0, 0.40)), pose: p, squint: squint,
                 tail: easeInOut(seg(t, 0.55, 1.15)), word: easeOut(seg(t, 2.70, 3.20)))
}

// MARK: - drawing
let ink = CGColor(red: 0xf0/255.0, green: 0xf2/255.0, blue: 0xf5/255.0, alpha: 1)
let markSide = CGFloat(H) * 0.36
let markBox = CGRect(x: CGFloat(W)/2 - markSide/2, y: CGFloat(H) * 0.62 - markSide/2, width: markSide, height: markSide)
let unit = markSide / 24
let wordSize = CGFloat(H) * 0.096                     // SF Pro Rounded runs small, so it is set up ~8%
let wordBaseline = CGFloat(H) * 0.235                 // from the bottom (CG space)
// SF Pro Rounded Bold: the one face drawn with the mark's round pen. -0.03em tracking as the site's h1.
let wordFont = NSFont(descriptor: NSFont.systemFont(ofSize: wordSize, weight: .bold).fontDescriptor.withDesign(.rounded)!, size: wordSize)!

func place(_ p: CGPoint) -> CGPoint { CGPoint(x: markBox.minX + p.x * unit, y: markBox.maxY - p.y * unit) }
func circle(_ c: CGPoint, _ r: CGFloat, scale: CGFloat = 1) -> CGPath {
    let d = place(c), rr = r * unit * scale
    return CGPath(ellipseIn: CGRect(x: d.x - rr, y: d.y - rr, width: rr * 2, height: rr * 2), transform: nil)
}

func draw(_ f: Frame, in ctx: CGContext) {
    ctx.setFillColor(ink); ctx.setStrokeColor(ink)

    // 1 — the bowl, scaling in about its own centre.
    ctx.saveGState()
    ctx.setAlpha(CGFloat(f.bowl))
    let bowlScale = CGFloat(0.6 + 0.4 * f.bowl)
    ctx.addPath(circle(bowlCentre, bowlOuter, scale: bowlScale))
    ctx.addPath(circle(bowlCentre, bowlInner, scale: bowlScale))
    ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()

    // 2 — the lid: a disc the size of the opening, clipped to everything above the line
    //     through (lidX0, lidL) and (lidX1, lidR), extended to the box edges.
    let lidL = lerp(openChord, squintL, f.squint), lidR = lerp(openChord, squintR, f.squint)
    if lidR > openChord + 0.01 {
        ctx.saveGState()
        let slope = (lidR - lidL) / (lidX1 - lidX0)
        func lidY(_ x: CGFloat) -> CGFloat { lidL + slope * (x - lidX0) }
        let clip = CGMutablePath()
        clip.addLines(between: [CGPoint(x: 0, y: -10), CGPoint(x: 24, y: -10), CGPoint(x: 24, y: lidY(24)), CGPoint(x: 0, y: lidY(0))].map(place))
        clip.closeSubpath()
        ctx.addPath(clip); ctx.clip()
        ctx.addPath(circle(bowlCentre, bowlInner + 0.25)); ctx.fillPath()   // overlap hides the shared edge
        ctx.restoreGState()
    }

    // 3 — the disc with the dot knocked out (a real hole: transparent).
    if f.pose.discR > 0.01 {
        ctx.addPath(circle(f.pose.disc, f.pose.discR))
        if f.pose.dotR > 0.01 { ctx.addPath(circle(f.pose.dot, f.pose.dotR)) }
        ctx.fillPath(using: .evenOdd)
    }

    // 4 — the tail, drawn to a fraction of its length.
    if f.tail > 0.001 {
        let target = tailTotal * CGFloat(f.tail)
        let path = CGMutablePath()
        path.move(to: place(tailPts[0]))
        for i in 1..<tailPts.count {
            if tailLen[i] <= target {
                path.addLine(to: place(tailPts[i]))
            } else {
                let f0 = (target - tailLen[i-1]) / (tailLen[i] - tailLen[i-1])
                path.addLine(to: place(lerp(tailPts[i-1], tailPts[i], Double(f0))))
                break
            }
        }
        ctx.setLineWidth(tailWidth * unit); ctx.setLineCap(.round); ctx.setLineJoin(.round)
        ctx.addPath(path); ctx.strokePath()
    }

    // 5 — the wordmark, fading in as it rises.
    if f.word > 0.001 {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: wordFont, .kern: -0.03 * wordSize,
            .foregroundColor: NSColor(cgColor: ink)!.withAlphaComponent(CGFloat(f.word))]
        let s = NSAttributedString(string: "githud", attributes: attrs)
        let size = s.size()
        let rise = CGFloat(1 - f.word) * wordSize * 0.18
        let origin = CGPoint(x: CGFloat(W)/2 - size.width/2, y: wordBaseline - rise)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        s.draw(at: origin)
        NSGraphicsContext.restoreGraphicsState()
    }
}

// MARK: - render loop
let fm = FileManager.default
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
// A shorter render must not leave earlier frames behind: ffmpeg's %04d.png would read them as a stale tail.
for name in (try? fm.contentsOfDirectory(atPath: outDir)) ?? [] where name.count == 8 && name.hasSuffix(".png") && name.dropLast(4).allSatisfy(\.isNumber) {
    try? fm.removeItem(atPath: (outDir as NSString).appendingPathComponent(name))
}
let frameCount = Int((duration * fps).rounded())
for i in 0..<frameCount {
    guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
    ctx.setAllowsAntialiasing(true); ctx.setShouldAntialias(true); ctx.interpolationQuality = .high
    draw(frame(at: Double(i) / fps), in: ctx)
    guard let img = ctx.makeImage() else { exit(1) }
    guard let png = NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:]) else { exit(1) }
    try! png.write(to: URL(fileURLWithPath: outDir).appendingPathComponent(String(format: "%04d.png", i)))
}
print("wrote \(frameCount) frames at \(Int(fps)) fps (\(W)x\(H)) to \(outDir)")
