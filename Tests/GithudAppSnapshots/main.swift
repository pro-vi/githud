// Native view regression checks and PNG renders; no live data or UI automation.
// Compile with the app sources except their main.swift and link GithudCore.
import AppKit
import GithudCore

let output = CommandLine.arguments.dropFirst().first ?? "/tmp/githud-snapshots"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
var failures = 0
func check(_ condition: Bool, _ message: String) {
    print("\(condition ? "PASS" : "FAIL") \(message)")
    if !condition { failures += 1 }
}
func descendants(_ view: NSView) -> [NSView] {
    [view] + view.subviews.flatMap(descendants)
}
let now = Date()
let stamp = ISO8601DateFormatter().string(from: now)
let pulses = [182, 214, 215].map { number in
    PulsePresenter.row(for: PullRequestPulse(
        repo: "sample/data-market", number: number,
        title: number == 182 ? "Verify one professional record and ordered draft" : "Improve the review workflow",
        url: "https://github.com/sample/data-market/pull/\(number)", isDraft: false,
        createdAt: stamp, updatedAt: stamp, ci: number == 182 ? .failing : .passing,
        review: .approved, merge: .mergeable, headBranch: "feat/review-\(number)"), now: now)
}
for themeID in [ThemeID.github, .color] {
    for name in ["mouse", "summoned", "number", "no-match", "long-query"] {
        let query: JumpQuery? = name == "mouse" ? nil : JumpQuery(
            name == "number" ? "214" : name == "no-match" ? "unmatched" :
            name == "long-query" ? String(repeating: "long-query-", count: 12) : "")
        let active = query?.isEmpty == false
        let narrowed = (query ?? JumpQuery()).narrow(radar: [], inbound: [], pulse: pulses)
        let known = JumpQuery.knownRepos(radar: [], inbound: [], pulse: pulses)
        let theme = Theme.named(themeID)
        let view = IslandContentView(
            rows: narrowed.radar, pulse: narrowed.pulse, inbound: [], jump: query,
            jumpCount: active && narrowed.matched > 0 ? PlainWords.jumpCount(matched: narrowed.matched, admitted: narrowed.admitted) : nil,
            jumpHandle: active ? query?.handle(knownRepos: known) : nil,
            jumpDestination: active ? query?.destination(selfLogin: nil, knownRepos: known) : nil,
            theme: theme, onGearTap: { _ in }, onCollapse: {})
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSView(frame: window.contentView!.bounds)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor(calibratedWhite: 0.105, alpha: 1).cgColor
        window.contentView = host
        view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            view.topAnchor.constraint(equalTo: host.topAnchor),
            view.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
        window.setContentSize(NSSize(width: 520, height: view.fittingHeight()))
        host.layoutSubtreeIfNeeded()
        if query != nil {
            view.setKeySessionHint(true, hasQuery: active)
            view.setKeyFocus(id: KeySession.actionableIDs(radar: [], pulse: narrowed.pulse,
                showDrafts: false, showStale: false, includeDestination: active).first)
        }
        host.layoutSubtreeIfNeeded()
        let lines = descendants(view).compactMap { $0 as? JumpLineView }
        check(lines.count == (query == nil ? 0 : 1), "\(themeID.rawValue)/\(name): jump line follows session presence")
        for line in lines {
            check(line.frame.width <= 484 && line.frame.width > 100, "query fits header width")
        }
        for button in descendants(view).compactMap({ $0 as? IconButton }) {
            let rect = button.convert(button.bounds, to: view)
            check(rect.minX >= 18 && rect.maxX <= 502, "header button stays inside island: \(rect)")
            check(!button.isHiddenOrHasHiddenAncestor && button.alphaValue == 1,
                  "header button remains visible")
        }
        if name == "summoned" {
            check(descendants(view).compactMap { $0 as? NSTextField }.contains {
                $0.stringValue == PlainWords.jumpPlaceholder
            }, "summon displays typing placeholder")
        }
        if let row = view.keyFocusedRowView() {
            check(!row.subviews.contains { $0.frame.width == 3 && $0.frame.minX == 0 },
                  "selection has no white edge strip")
            if let clickable = row as? IslandClickableView {
                let focusedColor = clickable.layer?.backgroundColor
                let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero,
                    modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil,
                    eventNumber: 0, clickCount: 0, pressure: 0)!
                clickable.mouseEntered(with: event)
                clickable.mouseExited(with: event)
                check(clickable.layer?.backgroundColor == focusedColor,
                      "hover entry and exit preserve keyboard selection")
            }
        }
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fatalError("bitmap") }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(
            to: URL(fileURLWithPath: output).appendingPathComponent("\(themeID.rawValue)-\(name).png"))
        window.contentView = nil
    }
}
for (input, expected) in [("fix review", "fix "), ("review", ""), ("", ""),
                          ("fix review   ", "fix "), ("feat/review", "feat/"),
                          ("café résumé", "café "), ("👩🏽‍💻 review", "👩🏽‍💻 ")] {
    var query = JumpQuery(input)
    query.deleteWordBackward()
    check(query.text == expected, "native word deletion: \(input.debugDescription) → \(query.text.debugDescription)")
}
exit(failures == 0 ? 0 : 1)
