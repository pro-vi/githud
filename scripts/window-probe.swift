// window-probe.swift — the "DOM inspect" analog for a native overlay.
//
// usage: swift scripts/window-probe.swift <pid>
//
// Lists on-screen windows owned by <pid> via CGWindowListCopyWindowInfo and
// prints them as JSON, plus derived facts: areaNonzero, withinScreen (against the
// union of active displays), and a sizeClass for the primary window. Window
// *metadata* (owner pid, bounds, layer) is NOT gated by Screen Recording
// permission — only window *images* are — so this proves "the HUD window is on
// screen with non-zero bounds" even before the screen-recording gate is flipped.
//
// Exit 0 if a non-zero-area window exists for the pid, else 2.
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2, let targetPID = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window-probe.swift <pid>\n".utf8))
    exit(64)
}

// Union bounds of all active displays (CG top-left coordinate space — same space
// as kCGWindowBounds, so containment is a direct rect test). Returns .zero (not
// .null/.infinite) when no displays are active (e.g. display asleep) so the result
// is always JSON-encodable — Double.inf cannot be encoded and would crash.
func displayUnion() -> CGRect {
    var count: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &count)
    guard count > 0 else { return .zero }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    CGGetActiveDisplayList(count, &ids, &count)
    let rects = ids.prefix(Int(count)).map { CGDisplayBounds($0) }
    return rects.dropFirst().reduce(rects.first ?? .zero) { $0.union($1) }
}

func sizeClass(_ w: Double, _ h: Double) -> String {
    func near(_ a: Double, _ b: Double, _ tol: Double) -> Bool { abs(a - b) <= tol }
    if near(w, 280, 60), near(h, 42, 24) { return "collapsed" }
    if near(w, 520, 80), near(h, 130, 70) { return "expanded" }   // populated island grows with rows
    return "other"
}

let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let raw = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
    print("{\"error\":\"CGWindowListCopyWindowInfo returned nil\"}")
    exit(70)
}

struct Win: Encodable {
    let ownerName: String?
    let ownerPID: Int
    let windowNumber: Int
    let layer: Int
    let x: Double, y: Double, w: Double, h: Double
}

var windows: [Win] = []
for info in raw {
    guard let pid = info[kCGWindowOwnerPID as String] as? Int, pid == targetPID else { continue }
    let bounds = info[kCGWindowBounds as String] as? [String: Double] ?? [:]
    windows.append(Win(
        ownerName: info[kCGWindowOwnerName as String] as? String,
        ownerPID: pid,
        windowNumber: info[kCGWindowNumber as String] as? Int ?? -1,
        layer: info[kCGWindowLayer as String] as? Int ?? 0,
        x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0,
        w: bounds["Width"] ?? 0, h: bounds["Height"] ?? 0
    ))
}

let rawScreen = displayUnion()
let screenValid = !rawScreen.isNull && !rawScreen.isInfinite
    && rawScreen.origin.x.isFinite && rawScreen.origin.y.isFinite
    && rawScreen.width.isFinite && rawScreen.height.isFinite
let screen = screenValid ? rawScreen : .zero   // never let Double.inf reach JSON
let nonzero = windows.filter { $0.w > 1 && $0.h > 1 }
let areaNonzero = !nonzero.isEmpty
// primary = largest-area non-zero window
let primary = nonzero.max { ($0.w * $0.h) < ($1.w * $1.h) }
let withinScreen = (screenValid ? primary.map { screen.contains(CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h)) } : false) ?? false
let primarySizeClass = primary.map { sizeClass($0.w, $0.h) } ?? "none"

struct ScreenRect: Encodable { let x: Double, y: Double, w: Double, h: Double }
struct Out: Encodable {
    let targetPID: Int
    let areaNonzero: Bool
    let withinScreen: Bool
    let primarySizeClass: String
    let count: Int
    let screen: ScreenRect
    let windows: [Win]
}

let out = Out(
    targetPID: targetPID,
    areaNonzero: areaNonzero,
    withinScreen: withinScreen,
    primarySizeClass: primarySizeClass,
    count: windows.count,
    screen: ScreenRect(x: screen.origin.x, y: screen.origin.y, w: screen.width, h: screen.height),
    windows: windows
)

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
print(String(decoding: try encoder.encode(out), as: UTF8.self))
exit(areaNonzero ? 0 : 2)
