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
// The prototype may describe selected-but-not-yet-implemented UI. U12 locks its
// independently authored query expectations to real Core matching/destinations;
// U9/U10 add the actual controller visibility and selection assertions below.
let prototype = try PrototypeFixture.load(repo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
let populated = prototype.fixture.rowSets["populated"]!
check(populated.ids.count >= 25, "prototype fixture exercises production-sized overflow")
check(prototype.metadata.scenarios.contains { $0.id == "quiet" && $0.expected.matchedIDs.contains { id in
    populated.pulse.contains { $0.id == id && $0.isStale && !$0.isDraft }
} }, "prototype quiet case actually contains a quiet row")
check(prototype.metadata.scenarios.contains { $0.id == "draft" && $0.expected.matchedIDs.contains { id in
    populated.pulse.contains { $0.id == id && $0.isDraft }
} }, "prototype draft case actually contains a draft")
check(prototype.metadata.scenarios.contains { $0.id == "held" && $0.expected.matchedIDs.contains { id in
    populated.inbound.contains { $0.id == id && $0.isHeldBack }
} }, "prototype held case actually contains held-back inbound")
for scenario in prototype.metadata.scenarios {
    let rows = prototype.fixture.rowSets[scenario.rowSet]!
    let query = JumpQuery(scenario.query)
    let narrowed = query.narrow(radar: rows.radar, inbound: rows.inbound, pulse: rows.pulse)
    let ids = narrowed.radar.map(\.id) + narrowed.inbound.map(\.id) + narrowed.pulse.map(\.id)
    check(ids == scenario.expected.matchedIDs, "prototype \(scenario.id): Core matches declared IDs in order")
    let count = !query.isEmpty && narrowed.matched > 0
        ? PlainWords.jumpCount(matched: narrowed.matched, admitted: narrowed.admitted) : nil
    check(count == scenario.expected.count, "prototype \(scenario.id): Core count matches declaration")
    let destination = query.isEmpty ? nil : query.destination(selfLogin: prototype.fixture.selfLogin,
        knownRepos: JumpQuery.knownRepos(radar: rows.radar, inbound: rows.inbound, pulse: rows.pulse))
    check(destination == scenario.expected.destination,
          "prototype \(scenario.id): Core destination matches declaration")
    check(KeySession.actionableIDs(radar: rows.radar, pulse: rows.pulse,
        showDrafts: scenario.preferences.showDrafts, showStale: scenario.preferences.showStale,
        inbound: rows.inbound, showHeldBackInbound: scenario.preferences.showHeldBack,
        lens: scenario.preferences.lens) == scenario.expected.browseIDs,
          "prototype \(scenario.id): declared browse restoration agrees with Core")
}

func prototypeFreshness(_ reading: PrototypeFixture.Scenario.Reading) -> Freshness {
    switch reading {
    case .fresh: return .fresh
    case .loading: return .fresh
    case .offline: return .failing(consecutive: 3, ageSeconds: 480)
    }
}

func prototypeView(for scenario: PrototypeFixture.Scenario, theme: ThemeID,
                   fixture: PrototypeFixture) -> IslandContentView {
    let rows = fixture.rowSets[scenario.rowSet]!
    let query = JumpQuery(scenario.query)
    let narrowed = query.narrow(radar: rows.radar, inbound: rows.inbound, pulse: rows.pulse)
    let active = !query.isEmpty
    let knownRepos = JumpQuery.knownRepos(radar: rows.radar, inbound: rows.inbound, pulse: rows.pulse)
    return IslandContentView(
        rows: narrowed.radar, pulse: narrowed.pulse, inbound: narrowed.inbound,
        jump: scenario.session == .keyboard ? query : nil,
        jumpCount: active && narrowed.matched > 0
            ? PlainWords.jumpCount(matched: narrowed.matched, admitted: narrowed.admitted) : nil,
        jumpHandle: active ? query.handle(knownRepos: knownRepos) : nil,
        jumpDestination: active
            ? query.destination(selfLogin: fixture.selfLogin, knownRepos: knownRepos) : nil,
        showDrafts: scenario.preferences.showDrafts,
        showStale: scenario.preferences.showStale,
        showHeldBackInbound: scenario.preferences.showHeldBack,
        freshness: prototypeFreshness(scenario.freshness),
        radarConfirmed: true, inboundConfirmed: true, reviewsConfirmed: true,
        theme: Theme.named(theme), onGearTap: { _ in }, onCollapse: {},
        lensPreferences: scenario.preferences.lens, selfLogin: fixture.selfLogin)
}

// U9 view construction: compare the IDs AppKit actually registered in its rendered body,
// in order, against the shared case contract. The old browse-gated body intentionally fails
// the hidden draft/quiet/held-back/folded search cases until the production branch is changed.
for themeID in [ThemeID.color, .github] {
    for scenario in prototype.metadata.scenarios {
        let view = prototypeView(for: scenario, theme: themeID, fixture: prototype.fixture)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 900),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: 520, height: view.fittingHeight())
        view.layoutSubtreeIfNeeded()
        let query = JumpQuery(scenario.query)
        let expected = scenario.expected.localIDs
            + (!query.isEmpty && scenario.session == .keyboard ? [KeySession.destinationID] : [])
        check(view.renderedActionableIDsForTesting() == expected,
              "U9 \(themeID.rawValue)/\(scenario.id): rendered actionable rows equal the direct-search contract")
        window.contentView = nil
        window.close()
    }
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
            check(line.field.frame.width > 200,
                  "editable field retains available header width")
            check(line.field.stringValue == (query?.text ?? ""),
                  "native field value remains complete")
        }
        for button in descendants(view).compactMap({ $0 as? IconButton }) {
            let rect = button.convert(button.bounds, to: view)
            check(rect.minX >= 18 && rect.maxX <= 502, "header button stays inside island: \(rect)")
            check(!button.isHiddenOrHasHiddenAncestor && button.alphaValue == 1,
                  "header button remains visible")
        }
        if name == "summoned" {
            check(descendants(view).compactMap { $0 as? JumpLineView }.contains {
                $0.field.placeholderAttributedString?.string == PlainWords.jumpPlaceholder
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
// Native editor integration: use an unshown panel and synthetic text only. This exercises
// the actual field-editor and control-delegate path without global events or a clipboard.
app.setActivationPolicy(.accessory)
app.finishLaunching()

// U9 controller path: use the real HUDPanelController, native editor delegate, and snapshot
// update. Selection's first-row policy belongs to U10; this unit checks only the rendered body,
// walk order, and preservation of the live header/editor across edit and clear.
for scenario in prototype.metadata.scenarios where scenario.rowSet == "populated" && scenario.session == .keyboard {
    let rows = prototype.fixture.rowSets[scenario.rowSet]!
    let model = AppModel(surfacePreferences: .auto,
                         pulsePreferences: scenario.preferences.pulse,
                         themeID: .github,
                         inboundPreferences: scenario.preferences.inbound,
                         lensPreferences: scenario.preferences.lens)
    model.setRadar(rows.radar, confirmed: true)
    model.setInbound(rows.inbound)
    model.setPulse(rows.pulse)
    model.setSelfLogin(prototype.fixture.selfLogin)
    let controller = HUDPanelController(model: model)
    controller.show()
    controller.setExpanded(true)
    controller.beginKeySummonSession()
    check(controller.jumpSessionIsLiveForTesting(),
          "U9 controller \(scenario.id): native session begins")
    guard controller.jumpSessionIsLiveForTesting(),
          let line = controller.jumpLineForTesting(),
          let editor = line.field.currentEditor() as? JumpFieldEditor else {
        check(false, "U9 controller \(scenario.id): native editor is acquired")
        controller.hide()
        continue
    }
    let originalLine = line
    let beforePreferences = (model.pulsePreferences, model.inboundPreferences, model.lensPreferences)
    let replacement = NSRange(location: 0, length: editor.string.utf16.count)
    editor.insertText(scenario.query, replacementRange: replacement)
    let query = JumpQuery(scenario.query)
    let expectedDrawn = scenario.expected.localIDs
        + (!query.isEmpty ? [KeySession.destinationID] : [])
    check(controller.islandForTesting()?.renderedActionableIDsForTesting() == expectedDrawn,
          "U9 controller \(scenario.id): edit renders the ordered local rows and destination")
    check(controller.keyWalkForTesting() == scenario.expected.walk,
          "U9 controller \(scenario.id): edit walk equals the declared ordered walk")
    let visibleCounts = descendants(line).compactMap { $0 as? NSTextField }
        .filter { $0 !== line.field && !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue)
    check(visibleCounts == scenario.expected.count.map { [$0] } ?? [],
          "U9 controller \(scenario.id): actual header count agrees with the local results")
    check(controller.jumpLineForTesting() === originalLine
          && line.field.currentEditor() === editor,
          "U9 controller \(scenario.id): edit retains header and native editor identity")
    if !scenario.query.isEmpty {
        check(line.control(line.field, textView: editor,
                           doCommandBy: Selector(("cancelOperation:"))),
              "U9 controller \(scenario.id): native clear command is handled")
        check(controller.islandForTesting()?.renderedActionableIDsForTesting() == scenario.expected.browseIDs,
              "U9 controller \(scenario.id): clear restores the browse rows")
        check(model.pulsePreferences == beforePreferences.0
              && model.inboundPreferences == beforePreferences.1
              && model.lensPreferences == beforePreferences.2,
              "U9 controller \(scenario.id): clear does not mutate browse preferences")
        check(controller.jumpLineForTesting() === originalLine
              && line.field.currentEditor() === editor,
              "U9 controller \(scenario.id): clear retains header and native editor identity")
    }
    controller.hide()
}

func makeU10Controller(_ scenarioID: String) -> (HUDPanelController, JumpLineView, JumpFieldEditor)? {
    guard let scenario = prototype.metadata.scenarios.first(where: { $0.id == scenarioID }) else {
        check(false, "U10 controller \(scenarioID): scenario exists")
        return nil
    }
    guard let rows = prototype.fixture.rowSets[scenario.rowSet] else {
        check(false, "U10 controller \(scenarioID): fixture row set exists")
        return nil
    }
    let model = AppModel(surfacePreferences: .auto,
                         pulsePreferences: scenario.preferences.pulse,
                         themeID: .github,
                         inboundPreferences: scenario.preferences.inbound,
                         lensPreferences: scenario.preferences.lens)
    model.setRadar(rows.radar, confirmed: true)
    model.setInbound(rows.inbound)
    model.setPulse(rows.pulse)
    model.setSelfLogin(prototype.fixture.selfLogin)
    let controller = HUDPanelController(model: model)
    controller.show()
    controller.setExpanded(true)
    controller.beginKeySummonSession()
    guard controller.jumpSessionIsLiveForTesting(),
          let line = controller.jumpLineForTesting(),
          let editor = line.field.currentEditor() as? JumpFieldEditor else {
        check(false, "U10 controller \(scenarioID): native editor is acquired")
        controller.hide()
        return nil
    }
    return (controller, line, editor)
}

func replaceU10Text(_ editor: JumpFieldEditor, with text: String) {
    editor.insertText(text, replacementRange:
        NSRange(location: 0, length: editor.string.utf16.count))
}

// U10 selection defaults: a no-match prefix must not leave the fallback selected when
// a later changed value reveals a local row.
if let (prefixController, _, prefixEditor) = makeU10Controller("quiet"),
   let quiet = prototype.metadata.scenarios.first(where: { $0.id == "quiet" }) {
    replaceU10Text(prefixEditor, with: "feat")
    check(prefixController.selectedIDForTesting() == KeySession.destinationID,
          "U10 no-match prefix selects the GitHub destination")
    replaceU10Text(prefixEditor, with: "feat/keeper-rig")
    check(prefixController.selectedIDForTesting() == quiet.expected.localIDs.first,
          "U10 later local match resets selection to its first local row")
    prefixController.hide()
}

// U10 preserves an explicit destination choice through an unchanged-text callback,
// a caret move, and the production screen-change notification. A later edit resets it.
if let (stableController, stableLine, stableEditor) = makeU10Controller("quiet"),
   let quiet = prototype.metadata.scenarios.first(where: { $0.id == "quiet" }) {
    replaceU10Text(stableEditor, with: quiet.query)
    check(stableLine.control(stableLine.field, textView: stableEditor,
                             doCommandBy: Selector(("moveDown:"))),
          "U10 explicit destination arrow command is handled")
    let destination = stableController.selectedIDForTesting()
    check(destination == KeySession.destinationID,
          "U10 arrow moves to the GitHub destination")
    stableLine.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: stableLine.field))
    check(stableController.selectedIDForTesting() == destination,
          "U10 unchanged text callback preserves the explicit destination")
    stableEditor.setSelectedRange(NSRange(location: stableEditor.string.utf16.count, length: 0))
    check(stableController.selectedIDForTesting() == destination,
          "U10 caret movement preserves the explicit destination")
    NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    check(stableController.selectedIDForTesting() == destination,
          "U10 screen resize preserves the explicit destination")
    replaceU10Text(stableEditor, with: "draft-camera")
    check(stableController.selectedIDForTesting()
          == prototype.metadata.scenarios.first(where: { $0.id == "draft" })?.expected.localIDs.first,
          "U10 changed text resets to the first newly matching local row")
    stableController.hide()
}

// U10 disappearing-row rule: a selected local row leaving the result set selects the
// first remaining local row instead of clamping to the GitHub destination.
if let (disappearController, disappearLine, disappearEditor) = makeU10Controller("mixed"),
   let mixed = prototype.metadata.scenarios.first(where: { $0.id == "mixed" }),
   let quiet = prototype.metadata.scenarios.first(where: { $0.id == "quiet" }) {
    replaceU10Text(disappearEditor, with: mixed.query)
    check(disappearLine.control(disappearLine.field, textView: disappearEditor,
                                doCommandBy: Selector(("moveDown:"))),
          "U10 selects a second local row before it disappears")
    check(disappearController.selectedIDForTesting() == "radar-2",
          "U10 disappearing-row setup selects the second local row")
    replaceU10Text(disappearEditor, with: quiet.query)
    check(disappearController.selectedIDForTesting() == quiet.expected.localIDs.first,
          "U10 disappearing local row selects the first remaining local row")
    disappearController.hide()
}

// U10 native continuity: clear and undo travel through the field editor and panel
// command route while preserving the editor and its session-local undo manager.
if let (undoController, undoLine, undoEditor) = makeU10Controller("quiet"),
   let quiet = prototype.metadata.scenarios.first(where: { $0.id == "quiet" }),
   let panel = undoLine.field.window as? HUDPanel {
    replaceU10Text(undoEditor, with: quiet.query)
    // Separate user actions occur on separate event-loop turns. Without this,
    // setup insertion and Escape deletion share one undo group in this runner.
    RunLoop.current.run(until: Date().addingTimeInterval(0.01))
    let originalUndoManager = undoEditor.undoManager
    check(undoLine.control(undoLine.field, textView: undoEditor,
                           doCommandBy: Selector(("cancelOperation:"))),
          "U10 native clear command is handled")
    check(undoEditor.string.isEmpty, "U10 clear empties the native query")
    check(undoController.jumpLineForTesting() === undoLine
          && undoLine.field.currentEditor() === undoEditor
          && undoEditor.undoManager === originalUndoManager,
          "U10 clear preserves header, editor, and undo manager")
    let undoEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                     modifierFlags: .command, timestamp: 0,
                                     windowNumber: panel.windowNumber, context: nil,
                                     characters: "z", charactersIgnoringModifiers: "z",
                                     isARepeat: false, keyCode: 6)!
    check(panel.performKeyEquivalent(with: undoEvent), "U10 native undo chord is handled")
    check(undoEditor.string == quiet.query, "U10 native undo restores the query")
    check(undoController.keyWalkForTesting() == quiet.expected.walk
          && undoController.selectedIDForTesting() == quiet.expected.localIDs.first,
          "U10 undo restores search results and selects the first local match")
    check(undoController.jumpLineForTesting() === undoLine
          && undoLine.field.currentEditor() === undoEditor
          && undoEditor.undoManager === originalUndoManager,
          "U10 undo preserves header, editor, and undo manager")
    undoController.hide()
}

// U10 Return captures the existing local URL through the controller seam, without opening
// a browser or routing an external event.
if let (openController, openLine, openEditor) = makeU10Controller("quiet"),
   let quiet = prototype.metadata.scenarios.first(where: { $0.id == "quiet" }) {
    var openedURL: URL?
    openController.openURLForTesting = { openedURL = $0 }
    replaceU10Text(openEditor, with: quiet.query)
    check(openLine.control(openLine.field, textView: openEditor,
                           doCommandBy: Selector(("insertNewline:"))),
          "U10 local Return command is handled")
    check(openedURL == quiet.expected.openURL.flatMap(URL.init(string:)),
          "U10 local Return captures the selected row URL")
    check(!openController.jumpSessionIsLiveForTesting(),
          "U10 local Return retires the native session")
    openController.hide()
}

let nativePanel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 100),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
nativePanel.keySessionActive = true
nativePanel.becomesKeyOnlyIfNeeded = false
let nativeHost = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 100))
nativePanel.contentView = nativeHost
var nativeCommands: [KeySession.Intent] = []
let nativeSession = UUID()
let nativeLine = JumpLineView(text: "", count: nil, theme: Theme.named(.github),
                              sessionID: nativeSession,
                              onCommand: { nativeCommands.append($0); return true })
nativeLine.frame = NSRect(x: 18, y: 40, width: 484, height: 24)
nativeHost.addSubview(nativeLine)
nativePanel.activateJumpField(sessionID: nativeSession, field: nativeLine.field)
check(nativeLine.field.window === nativePanel, "jump field is attached to HUD panel")
let provisionedEditor = nativePanel.fieldEditor(true, for: nativeLine.field) as? JumpFieldEditor
check(provisionedEditor != nil, "HUD panel provisions the jump field editor")
nativePanel.orderFrontRegardless()
nativePanel.makeKey()
nativeLine.field.selectText(nil)
let acquired = nativePanel.firstResponder is JumpFieldEditor
let nativeEditor = provisionedEditor
check(acquired && nativeEditor != nil,
      "native jump field acquires its session-owned editor")
if let nativeEditor {
    check(nativeLine.field.currentEditor() === nativeEditor,
          "native field reports its attached editor")
    func key(_ flags: NSEvent.ModifierFlags, characters: String,
             ignoring: String, code: UInt16) {
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: 0, windowNumber: nativePanel.windowNumber,
                                     context: nil, characters: characters,
                                     charactersIgnoringModifiers: ignoring, isARepeat: false,
                                     keyCode: code)!
        nativeEditor.keyDown(with: event)
    }
    key(.shift, characters: "!", ignoring: "1", code: 18)
    key(.shift, characters: "A", ignoring: "a", code: 0)
    check(nativeEditor.string == "!A", "native key path accepts Shift punctuation and uppercase")
    key([], characters: "l", ignoring: "l", code: 37)
    key([], characters: "p", ignoring: "p", code: 35)
    key([], characters: "h", ignoring: "h", code: 4)
    key([], characters: "a", ignoring: "a", code: 0)
    key([], characters: " ", ignoring: " ", code: 49)
    key([], characters: "b", ignoring: "b", code: 11)
    key([], characters: "e", ignoring: "e", code: 14)
    key([], characters: "t", ignoring: "t", code: 17)
    key([], characters: "a", ignoring: "a", code: 0)
    key(.option, characters: "\u{7f}", ignoring: "\u{7f}", code: 51)
    check(nativeEditor.string == "!Alpha ",
          "native Option–Backspace deletes the previous word from the caret")
    nativeEditor.setMarkedText("漢", selectedRange: NSRange(location: 1, length: 0),
                               replacementRange: NSRange(location: 0, length: 0))
    let commandCount = nativeCommands.count
    check(!nativeLine.control(nativeLine.field, textView: nativeEditor,
                              doCommandBy: Selector(("insertNewline:"))),
          "marked composition defers return (range \(nativeEditor.markedRange()))")
    check(nativeCommands.count == commandCount, "composition does not open a result")
    nativeEditor.unmarkText()
    check(nativeLine.control(nativeLine.field, textView: nativeEditor,
                             doCommandBy: Selector(("moveDown:"))),
          "native down command is owned (range \(nativeEditor.markedRange()))")
    check(nativeCommands.last == .moveDown, "down reaches result selection")
    check(nativeLine.performCommand(Selector(("insertNewline:")), modifiers: .option, editor: nativeEditor),
          "option-return command is owned")
    check(nativeCommands.last == .peek, "option-return reaches peek")
    check(nativeLine.control(nativeLine.field, textView: nativeEditor,
                             doCommandBy: Selector(("insertNewline:"))),
          "return command is owned")
    check(nativeCommands.last == .open, "return reaches open")

    nativeEditor.string = "synthetic query"
    nativeEditor.setSelectedRange(NSRange(location: 0, length: nativeEditor.string.utf16.count))
    check(nativeLine.control(nativeLine.field, textView: nativeEditor,
                             doCommandBy: Selector(("cancelOperation:"))),
          "escape clear is native")
    check(nativeEditor.string.isEmpty, "escape replaces the selection and reports the native text")
}

// Text insertion/replacement and per-session undo use the same native field editor
// implementation without relying on a key-window shortcut to seed its initial value.
let editingEditor = JumpFieldEditor(sessionID: UUID())
editingEditor.isFieldEditor = false
editingEditor.string = "alpha beta"
check(editingEditor.string == "alpha beta", "standalone native editor accepts text setup")
editingEditor.undoManager?.removeAllActions()
editingEditor.setSelectedRange(NSRange(location: 6, length: 4))
editingEditor.insertText("!@#$", replacementRange: editingEditor.selectedRange())
check(editingEditor.string == "alpha !@#$", "native editor replaces a selection with punctuation (got \(editingEditor.string.debugDescription))")
editingEditor.undoManager?.undo()
check(editingEditor.string == "alpha beta", "native editor undo restores the selection")
editingEditor.undoManager?.redo()
check(editingEditor.string == "alpha !@#$", "native editor redo restores the replacement")
nativeLine.endEditingSession()
check(nativeLine.performCommand(Selector(("insertNewline:"))) == false,
      "late editor commands are ignored after teardown")

// Row-only updates retain the header/field object while replacing the drawn result set.
let sessionView = IslandContentView(rows: [], pulse: pulses, jump: JumpQuery(), theme: Theme.named(.github))
let sessionWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 400),
                             styleMask: .borderless, backing: .buffered, defer: false)
sessionWindow.contentView = sessionView
sessionView.frame = NSRect(x: 0, y: 0, width: 520, height: sessionView.fittingHeight())
sessionView.layoutSubtreeIfNeeded()
let originalLine = sessionView.jumpLineView()
let narrowed = JumpQuery("214").narrow(radar: [], inbound: [], pulse: pulses)
_ = sessionView.updateJump(rows: narrowed.radar, pulse: narrowed.pulse, inbound: narrowed.inbound,
                           jump: JumpQuery("214"), jumpCount: "1 of 3",
                           jumpHandle: .number(214), jumpDestination: "https://github.com/search?q=214",
                           showDrafts: false, showStale: false, showHeldBackInbound: false,
                           freshness: .fresh, lensPreferences: .default, selfLogin: nil,
                           lensLastOpened: [:])
check(sessionView.jumpLineView() === originalLine, "query narrowing keeps the attached header")
check(sessionView.keyFocusedRowView() == nil, "row replacement has no stale result focus")
let crowdedRadar = (try! NotificationThread.list(from: Data("""
[{"id":"short-r1","unread":true,"reason":"mention","updated_at":"2026-06-16T08:00:00Z","subject":{"title":"Radar row","type":"Issue","latest_comment_url":null},"repository":{"full_name":"sample/data-market","private":false,"owner":{"login":"sample","type":"Organization"}}}]
""".utf8))).map { $0 }
let crowdedInbound = (0..<4).map { index in
    InboundPresenter.row(for: InboundItem(
        repo: "sample/data-market", number: 400 + index, title: "Inbound \(index)",
        url: "https://github.com/sample/data-market/issues/\(400 + index)", authorLogin: "alice",
        authorType: "User", isPR: false, isDraft: false, createdAt: stamp, updatedAt: stamp))
}
let crowdedView = IslandContentView(
    rows: RadarPresenter.rows(for: SignalClassifier.radar(crowdedRadar), now: now),
    pulse: Array(repeating: pulses, count: 20).flatMap { $0 }, inbound: crowdedInbound,
    jump: JumpQuery(), theme: Theme.named(.github))
let shortHeight = crowdedView.fittingHeight(maxHeight: 300)
check(shortHeight <= 300 && crowdedView.paneHeightsForTesting().count == 3
      && crowdedView.paneHeightsForTesting().allSatisfy { $0 > 0 && $0 <= 240.5 },
      "short-display fitting shrinks scroll panes before clamping the panel")
check(crowdedView.jumpLineView() != nil,
      "short-display fitting leaves the native header attached")
sessionWindow.contentView = nil
sessionWindow.close()

// Production controller lifecycle: poll and appearance changes stay out of the live
// island, then the collapse transition replays the newest state exactly once.
let controllerModel = AppModel(surfacePreferences: .auto, pulsePreferences: .default,
                               themeID: .github)
controllerModel.setPulse(pulses)
let controller = HUDPanelController(model: controllerModel)
controller.onToggleStale = {
    controllerModel.setPulsePreferences(controllerModel.pulsePreferences.togglingShowStale())
}
controller.onToggleHeldBackInbound = {
    controllerModel.setInboundPreferences(controllerModel.inboundPreferences.togglingShowHeldBack())
}
controller.onToggleJustCleared = {
    controllerModel.setShowJustCleared(!controllerModel.showJustCleared)
}
controller.onToggleDrafts = {
    controllerModel.setPulsePreferences(controllerModel.pulsePreferences.togglingShowDrafts())
}
controller.onToggleFoldedOwner = { owner in
    controllerModel.setLensPreferences(controllerModel.lensPreferences.togglingFolded(owner))
}
controller.panelForTesting().level = .normal
controller.show()
controller.setExpanded(true)
check(controller.isVisible, "controller is visible before native summon")
check(controller.islandForTesting() != nil, "expanded controller has an island surface")
controller.beginKeySummonSession()
check(controller.jumpSessionIsLiveForTesting(), "controller begins a native jump session")
if controller.jumpSessionIsLiveForTesting(), let controllerLine = controller.jumpLineForTesting() {
    let controllerEditor = controllerLine.field.currentEditor() as? JumpFieldEditor
    check(controllerEditor != nil && controllerLine.field.window?.firstResponder === controllerEditor,
          "controller session owns the actual field editor and first responder")
    if let controllerEditor {
        let typedEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                          modifierFlags: [], timestamp: 0,
                                          windowNumber: controllerLine.field.window?.windowNumber ?? 0,
                                          context: nil, characters: "2",
                                          charactersIgnoringModifiers: "2", isARepeat: false,
                                          keyCode: 19)!
        controllerEditor.keyDown(with: typedEvent)
        check(controllerEditor.string == "2", "native typing updates the attached editor")
        check(controller.jumpLineForTesting() === controllerLine,
              "native text change keeps the controller header attached")
        if let panel = controllerLine.field.window as? HUDPanel {
            let undoEvent = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                              modifierFlags: .command, timestamp: 0,
                                              windowNumber: panel.windowNumber, context: nil,
                                              characters: "z", charactersIgnoringModifiers: "z",
                                              isARepeat: false, keyCode: 6)!
            _ = panel.performKeyEquivalent(with: undoEvent)
            check(controllerEditor.string.isEmpty, "native command-undo clears the typed query")
            let attachedAfterUndo = controllerLine.field.currentEditor() as? JumpFieldEditor
            check(attachedAfterUndo === controllerEditor
                  && panel.firstResponder === attachedAfterUndo,
                  "undo preserves the active native editor attachment")
            let typedAgain = NSEvent.keyEvent(with: .keyDown, location: .zero,
                                              modifierFlags: [], timestamp: 0,
                                              windowNumber: panel.windowNumber, context: nil,
                                              characters: "1", charactersIgnoringModifiers: "1",
                                              isARepeat: false, keyCode: 18)!
            attachedAfterUndo?.keyDown(with: typedAgain)
            check(attachedAfterUndo?.string == "1",
              "the next native key edits after undo")
        }
    }
    if let controllerEditor {
        for (query, expectedCount, expectsNoMatch) in [
            ("", "", false), ("   ", "", false),
            ("no-such-fixture-row", "", true), ("214", "1 of 3", false)
        ] {
            controllerEditor.insertText(query, replacementRange:
                NSRange(location: 0, length: controllerEditor.string.utf16.count))
            let visibleCountLabels = descendants(controllerLine).compactMap { $0 as? NSTextField }
                .filter { $0 !== controllerLine.field && !$0.isHiddenOrHasHiddenAncestor }
            check(visibleCountLabels.map(\.stringValue) == (expectedCount.isEmpty ? [] : [expectedCount]),
                  "controller count visibility for query \(query.debugDescription)")
            let noMatchVisible = controller.islandForTesting().map { island in
                descendants(island).compactMap { $0 as? NSTextField }.contains {
                    !$0.isHiddenOrHasHiddenAncestor && $0.stringValue == PlainWords.jumpNothingMatches
                }
            } ?? false
            check(noMatchVisible == expectsNoMatch,
                  "controller no-match visibility for query \(query.debugDescription)")
            check(controllerLine.field.frame.width > 200,
                  "controller field keeps width with count \(expectedCount.isEmpty ? "hidden" : "shown")")
            check(controllerLine.field.stringValue == query,
                  "controller field keeps complete query \(query.debugDescription)")
        }

        // Keyboard result selection is a separate AXSelected state. Moving the selection
        // through the actual field delegate must update the two rows without moving native
        // focus away from the editor.
        if let island = controller.islandForTesting(),
           let oldRow = island.keyFocusedRowView(),
           let fieldEditor = controllerLine.field.currentEditor() as? JumpFieldEditor,
           let panel = controllerLine.field.window as? HUDPanel {
            let movedUp = controllerLine.control(controllerLine.field, textView: fieldEditor,
                                                 doCommandBy: Selector(("moveUp:")))
            var newRow = island.keyFocusedRowView()
            var moved = movedUp && newRow !== oldRow
            if !moved {
                let movedDown = controllerLine.control(controllerLine.field, textView: fieldEditor,
                                                       doCommandBy: Selector(("moveDown:")))
                newRow = island.keyFocusedRowView()
                moved = movedDown && newRow !== oldRow
            }
            if moved, let newRow {
                let selected = newRow.isAccessibilitySelected()
                let formerSelected = oldRow.isAccessibilitySelected()
                check(selected && !formerSelected,
                      "keyboard selection exposes AXSelected on only the current row")
                check(panel.firstResponder === fieldEditor
                      && controllerLine.field.currentEditor() === fieldEditor,
                      "row selection leaves native editor focus attached")
            } else {
                check(false, "keyboard selection moves to a different controller row")
            }
        } else {
            check(false, "keyboard selection moves to a different controller row")
        }
    }
    if let appearanceSurface = controller.surfaceForTesting() as? IslandEffectView {
        appearanceSurface.viewDidChangeEffectiveAppearance()
        check(controller.deferredStateForTesting().surface,
              "appearance hook defers surface work during editing")
    } else if let appearanceSurface = controller.surfaceForTesting() as? IslandSolidView {
        appearanceSurface.viewDidChangeEffectiveAppearance()
        check(controller.deferredStateForTesting().surface,
              "appearance hook defers surface work during editing")
    }
    var renderCount = 0
    controller.renderObserverForTesting = { renderCount += 1 }
    controllerModel.setPulse([])
    controllerModel.setThemeID(.color)
    check(controller.jumpLineForTesting() === controllerLine,
          "poll and theme changes do not replace the live editor")
    let deferred = controller.deferredStateForTesting()
    check(deferred.render && deferred.surface,
          "poll and appearance changes record owed work")
    let beforeExit = renderCount
    controller.setExpanded(false)
    check(renderCount == beforeExit + 1,
          "collapse replays deferred work with one final render")
    check(!controller.jumpSessionIsLiveForTesting(), "collapse retires the native session")
    let afterExit = controller.deferredStateForTesting()
    check(!afterExit.render && !afterExit.surface, "deferred work is cleared after replay")
}

// Return exit-race: an opener that causes key loss synchronously cannot replay an
// expanded island between session teardown and the collapse transition.
let openModel = AppModel(surfacePreferences: .auto, pulsePreferences: .default, themeID: .github)
openModel.setPulse([pulses[0]])
let openController = HUDPanelController(model: openModel)
openController.show()
openController.setExpanded(true)
openController.beginKeySummonSession()
if openController.jumpSessionIsLiveForTesting(), let openLine = openController.jumpLineForTesting(),
   let openEditor = openLine.field.currentEditor() as? JumpFieldEditor,
   let openPanel = openLine.field.window as? HUDPanel {
    var openedURL: URL?
    var openRenders = 0
    openController.renderObserverForTesting = { openRenders += 1 }
    openController.openURLForTesting = { url in
        openedURL = url
        openPanel.resignKey()
    }
    let beforeOpen = openRenders
    check(openLine.control(openLine.field, textView: openEditor,
                           doCommandBy: Selector(("insertNewline:"))),
          "return command enters the controller open path")
    check(openedURL != nil && !openController.jumpSessionIsLiveForTesting(),
          "return captures destination and retires the session before opening")
    check(openRenders == beforeOpen + 1,
          "synchronous key loss does not add a second expanded render")
}
openController.hide()

// Production preference callbacks: each island control ends the native session before
// forwarding its model mutation, so the new preference is visible immediately.
let stalePulse = PulsePresenter.row(for: PullRequestPulse(
    repo: "sample/data-market", number: 301, title: "Old PR", url: "https://github.com/sample/data-market/pull/301",
    isDraft: false, createdAt: "2020-01-01T00:00:00Z", updatedAt: "2020-01-01T00:00:00Z",
    ci: .passing, review: .approved, merge: .mergeable, headBranch: "feat/old"), now: now)
let draftPulse = PulsePresenter.row(for: PullRequestPulse(
    repo: "sample/data-market", number: 302, title: "Draft PR", url: "https://github.com/sample/data-market/pull/302",
    isDraft: true, createdAt: stamp, updatedAt: stamp,
    ci: .passing, review: .none, merge: .unknown, headBranch: "feat/draft"), now: now)
let heldInbound = InboundPresenter.row(for: InboundItem(
    repo: "sample/data-market", number: 303, title: "Held inbound", url: "https://github.com/sample/data-market/pull/303",
    authorLogin: "dependabot[bot]", authorType: "Bot", isPR: true, isDraft: false,
    createdAt: stamp, updatedAt: stamp))
let cleared = ClearedRow(id: "cleared-304", repo: "sample/data-market #304", title: "Cleared",
                        effectiveReason: "mention", whyText: "read ✓",
                        url: "https://github.com/sample/data-market/pull/304")
controllerModel.setPulse([pulses[0], stalePulse, draftPulse])
controllerModel.setInbound([heldInbound])
controllerModel.setCleared([cleared])
controllerModel.setPulsePreferences(PulsePreferences(showDrafts: true, showStale: false))
controllerModel.setInboundPreferences(InboundPreferences(showHeldBack: false))
controllerModel.setShowJustCleared(false)
controllerModel.setLensPreferences(LensPreferences(groupByOwner: true,
                                                   foldedOwners: ["sample"], ownerOrder: []))
controller.setExpanded(true)

func startPreferenceSession() -> Bool {
    controller.beginKeySummonSession()
    return controller.jumpSessionIsLiveForTesting()
}
func pressCaption(containing phrase: String) -> Bool {
    guard let view = controller.islandForTesting() else { return false }
    guard let caption = descendants(view).compactMap({ $0 as? CaptionButtonView }).first(where: {
              ($0.accessibilityLabel() ?? "").contains(phrase)
          }) else {
        return false
    }
    return caption.accessibilityPerformPress()
}
func pressHideControl() -> Bool {
    guard let view = controller.islandForTesting() else { return false }
    guard let control = descendants(view).compactMap({ $0 as? HideControlView }).first else {
        return false
    }
    return control.accessibilityPerformPress()
}
func pressFoldedOwner() -> Bool {
    guard let view = controller.islandForTesting() else { return false }
    guard let ledger = descendants(view).compactMap({ $0 as? LensLedgerLineView }).first else {
        return false
    }
    return ledger.accessibilityPerformPress()
}

check(startPreferenceSession(), "preference test starts folded-owner session")
check(pressFoldedOwner() && !controller.jumpSessionIsLiveForTesting()
      && controllerModel.lensPreferences.foldedOwners.isEmpty,
      "folded-owner control ends session before forwarding")

controllerModel.setLensPreferences(LensPreferences(groupByOwner: false,
                                                   foldedOwners: [], ownerOrder: []))
check(startPreferenceSession(), "preference test starts drafts session")
check(pressHideControl() && !controller.jumpSessionIsLiveForTesting()
      && !controllerModel.pulsePreferences.showDrafts,
      "drafts control ends session before forwarding")

controllerModel.setPulsePreferences(PulsePreferences(showDrafts: false, showStale: true))
check(startPreferenceSession(), "preference test starts stale session")
check(pressHideControl() && !controller.jumpSessionIsLiveForTesting()
      && !controllerModel.pulsePreferences.showStale,
      "stale control ends session before forwarding")

controllerModel.setInboundPreferences(InboundPreferences(showHeldBack: true))
check(startPreferenceSession(), "preference test starts held-back session")
check(pressHideControl() && !controller.jumpSessionIsLiveForTesting()
      && !controllerModel.inboundPreferences.showHeldBack,
      "held-back control ends session before forwarding")

controllerModel.setShowJustCleared(true)
check(startPreferenceSession(), "preference test starts just-cleared session")
check(pressHideControl() && !controller.jumpSessionIsLiveForTesting()
      && !controllerModel.showJustCleared,
      "just-cleared control ends session before forwarding")

controller.setExpanded(false)
nativePanel.makeFirstResponder(nil)
nativePanel.discardJumpFieldEditor(sessionID: nativeSession)
nativePanel.orderOut(nil)
nativePanel.close()
exit(failures == 0 ? 0 : 1)
