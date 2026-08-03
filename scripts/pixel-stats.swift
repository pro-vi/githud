// pixel-stats.swift — pixel-liveness for a captured PNG (the "is it black?" test).
//
// usage: swift scripts/pixel-stats.swift <png-path>
//
// Loads the image, draws a downsample into an RGBA buffer, and reports luminance
// mean/min/max/variance + distinct-color count as JSON. A frame captured WITHOUT
// Screen Recording permission is black/uniform (variance≈0, max≈0); a real capture
// has spread. Exit 0 if the frame is "live" (real content), else 2.
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: pixel-stats.swift <png-path>\n".utf8))
    exit(64)
}
let path = CommandLine.arguments[1]
guard let img = NSImage(contentsOfFile: path),
      let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("{\"error\":\"could not load image\"}")
    exit(64)
}

let w = min(cg.width, 160), h = min(cg.height, 100)
let cs = CGColorSpaceCreateDeviceRGB()
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("{\"error\":\"could not make context\"}")
    exit(70)
}
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

var sum = 0.0, sumsq = 0.0, n = 0.0, mn = 255.0, mx = 0.0
var uniq = Set<Int>()
for i in stride(from: 0, to: buf.count, by: 4) {
    let lum = 0.299 * Double(buf[i]) + 0.587 * Double(buf[i + 1]) + 0.114 * Double(buf[i + 2])
    sum += lum; sumsq += lum * lum; n += 1
    mn = min(mn, lum); mx = max(mx, lum)
    uniq.insert((Int(buf[i]) / 16) << 8 | (Int(buf[i + 1]) / 16) << 4 | (Int(buf[i + 2]) / 16))
}
let mean = sum / n
let variance = sumsq / n - mean * mean
let live = mx > 10 && variance > 2

print(String(format: "{\"src_w\":%d,\"src_h\":%d,\"mean\":%.2f,\"min\":%.2f,\"max\":%.2f,\"variance\":%.2f,\"distinct_colors\":%d,\"live\":%@}",
             cg.width, cg.height, mean, mn, mx, variance, uniq.count, live ? "true" : "false"))
exit(live ? 0 : 2)
