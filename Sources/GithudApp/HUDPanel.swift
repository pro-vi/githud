import AppKit

/// The overlay window. A non-activating panel that must never steal focus from the
/// foreground app — never-key EXCEPT during an explicit user-consented key moment.
///
/// Pressure `focus-non-theft` (burden, proof line re-worded WP-4d): every change here
/// owes proof the HUD doesn't interrupt the foreground app. The relaxation is built on
/// AppKit's DESIGNED palette mechanism, not on hand-rolled event ordering (fix round —
/// findings 2/3/4):
///
/// - `canBecomeKey` is gated on `keySessionActive` — the ONE ratified scoped relaxation
///   (designer session 2026-07-06, D-card + G-keyboard as a single decision). The flag
///   now means ELIGIBILITY: a field-bearing card is showing with a live field (WP-6k
///   later sets the same flag for its ⌃⌥G session). It is written by the controller's
///   render (card in ⇄ card out), NOT flipped per click — so a click-away then
///   click-back always re-acquires (the secret can never be routed to another app by a
///   dead field).
/// - `becomesKeyOnlyIfNeeded = true` (set by the controller) supplies the "only the
///   user's own click into the FIELD" half: AppKit makes the panel key only when the
///   clicked view answers `needsPanelToBecomeKey == true` (the token field, and only
///   while enabled) — decided in `sendEvent`, exactly where the click→key decision
///   actually lives. Clicks on any other card ink never take key.
/// - The moment ENDS by giving key back through the window server (the controller's
///   order-out pulse — see `endKeySession`) or by the system's own resign on
///   click-away. The app NEVER activates (no `NSApp.activate` anywhere — the Spotlight
///   pattern: the foreground app keeps its menu bar throughout).
///
/// `canBecomeMain` stays a hard false forever. Everything else — `.nonactivatingPanel`
/// + `orderFrontRegardless` (in the controller) — is unchanged structural guarantee.
final class HUDPanel: NSPanel {
    /// The scoped key-moment gate (the ONE flag both ratified key moments share): a
    /// key-eligible surface is showing. false is the resting state and the default;
    /// with it false the panel can never become key, whatever is clicked. Eligibility =
    /// a field-bearing ledger card (WP-4d, written by render() on card presence) OR a
    /// live ⌃⌥G list session (WP-6k, written at the session's begin/end choke points).
    var keySessionActive = false
    override var canBecomeKey: Bool { keySessionActive }
    override var canBecomeMain: Bool { false }

    private var jumpFieldEditor: JumpFieldEditor?
    private var activeJumpSessionID: UUID?
    private var activeJumpField: NSTextField?

    func activateJumpField(sessionID: UUID, field: NSTextField) {
        activeJumpSessionID = sessionID
        activeJumpField = field
        if jumpFieldEditor == nil {
            let editor = JumpFieldEditor(sessionID: sessionID)
            editor.string = field.stringValue
            editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
            jumpFieldEditor = editor
        }
    }

    /// Provide a session-owned editor only to the exact jump field. Every other
    /// control, including the secure ledger, follows NSWindow's ordinary path.
    override func fieldEditor(_ createFlag: Bool, for object: Any?) -> NSText? {
        guard (object as? NSTextField).map({ $0 === activeJumpField }) == true,
              let field = activeJumpField else {
            return super.fieldEditor(createFlag, for: object)
        }
        guard field.window === self, let sessionID = activeJumpSessionID else { return nil }
        if let editor = jumpFieldEditor, editor.sessionID == sessionID {
            return editor
        }
        guard createFlag else { return nil }
        let editor = JumpFieldEditor(sessionID: sessionID)
        editor.string = field.stringValue
        editor.selectedRange = NSRange(location: editor.string.utf16.count, length: 0)
        jumpFieldEditor = editor
        return editor
    }

    /// Drop the editor and its undo history at session teardown. The identity check
    /// prevents a late callback from retiring a newer session's editor.
    func discardJumpFieldEditor(sessionID: UUID) {
        guard activeJumpSessionID == sessionID else { return }
        jumpFieldEditor = nil
        activeJumpSessionID = nil
        activeJumpField = nil
    }


    /// While a list session is live, accessibility focus follows the actual native
    /// text editor. Result selection is separate state and never impersonates it.
    var sessionFocusElement: (() -> Any?)?
    override var accessibilityFocusedUIElement: Any {
        // (double-unwrap: nil closure and nil answer both fall through to super)
        (sessionFocusElement?() ?? nil) ?? super.accessibilityFocusedUIElement
    }

    /// Key status hooks — the focus cue must follow REAL key state (fix round, finding
    /// 4: painting the accent border off the *attempt* let the cue claim a focus that
    /// may not exist). AppKit calls these; the controller listens.
    var onDidBecomeKey: (() -> Void)?
    var onDidResignKey: (() -> Void)?
    override func becomeKey() {
        super.becomeKey()
        onDidBecomeKey?()
    }
    override func resignKey() {
        super.resignKey()
        onDidResignKey?()
    }

    /// githud is `.accessory` with no `NSApp.mainMenu`, so the standard Edit-menu key
    /// equivalents have no dispatch route at all (fix round BLOCKER: ⌘V could not paste
    /// into the token field — the card's PRIMARY interaction). While key, route the
    /// standard editing commands straight down the responder chain (the field editor).
    /// Copy/cut on the SECURE field are refused by NSSecureTextView itself — the secret
    /// can never be copied back out; ⌘V/⌘A are the ones that matter.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key = event.charactersIgnoringModifiers?.lowercased()
        let responder = firstResponder
        if isKeyWindow, modifiers == [.command, .shift], key == "z",
           NSApp.sendAction(Selector(("redo:")), to: responder, from: self) { return true }
        if isKeyWindow,
           modifiers == .command,
           let key {
            let action: Selector?
            switch key {
            case "v": action = #selector(NSText.paste(_:))
            case "c": action = #selector(NSText.copy(_:))
            case "x": action = #selector(NSText.cut(_:))
            case "a": action = #selector(NSText.selectAll(_:))
            case "z": action = Selector(("undo:"))
            default:  action = nil
            }
            if let action, NSApp.sendAction(action, to: responder, from: self) { return true }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// The island surfaces (and every interactive view inside them) must behave under a
/// NON-KEY panel:
/// - `mouseDownCanMoveWindow = false`: an `NSVisualEffectView` defaults this to `true`,
///   which shows a "grab" cursor and consumes mousedowns as window-drags so clicks/hover
///   never reach the content. We never want to drag the island, so kill it.
/// - `acceptsFirstMouse = true`: the panel can never become key (focus-non-theft), so
///   EVERY click is a "first mouse" — a default view swallows it as an activation attempt,
///   so rows/pill would never receive a click. Accept the first mouse so clicks work on the
///   very first try without stealing focus.
final class IslandEffectView: NSVisualEffectView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Fired on a REAL system appearance change (Light↔Dark, accent color) — see
    /// `HUDPanelController.handleAppearanceChange`. `CGColor`-baked layer properties (the
    /// hairline border) don't auto-track a dynamic `NSColor` the way `contentTintColor`/
    /// `textColor` do, so this is the sanctioned re-resolution trigger. Externally owned,
    /// set once per `buildSurface()`; `nil` is a no-op.
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

final class IslandSolidView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// See `IslandEffectView.onAppearanceChange` — the solid surface additionally bakes its
    /// fill color (`layer.backgroundColor`), which needs the same re-resolution.
    var onAppearanceChange: (() -> Void)?
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}

/// Base for the island's CLICKABLE leaf views (rows, pill, message, inbox link). Same
/// non-key event behavior as the surfaces, PLUS a `hitTest` that treats the whole view as
/// one target — so a click landing on an inner label/glyph still resolves to this view
/// (whose `acceptsFirstMouse` is true and which owns the click gesture), instead of a child
/// label that would reject the first mouse and swallow the click.
class IslandClickableView: NSView {
    /// When non-nil, the view reacts to hover — a subtle highlight fill + a pointing-hand
    /// cursor — signalling "this is clickable." Subclasses set it in init (nil = inert).
    var hoverFill: NSColor?

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Swap ONLY our own hover area (dogfood 2026-07-18): the old blanket
        // `trackingAreas.forEach(removeTrackingArea)` also destroyed the areas AppKit's
        // tooltip manager had just re-installed via super — so no clickable could ever
        // show its `toolTip` (theme chip names, settings-row hints, the lens tooltip).
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(rect: bounds,
            options: [.mouseEnteredAndExited, .cursorUpdate, .activeAlways, .inVisibleRect], owner: self)
        hoverTracking = area
        addTrackingArea(area)
    }
    override func mouseEntered(with event: NSEvent) {
        guard let hoverFill else { return }
        wantsLayer = true
        if !keyFocused { setHoverBackground(hoverFill.cgColor) }
        NSCursor.pointingHand.set()
    }
    override func mouseExited(with event: NSEvent) {
        guard hoverFill != nil else { return }   // inert views were never highlighted → nothing to fade
        NSCursor.arrow.set()
        // Pointer exit must not fade the keyboard selection.
        guard !keyFocused else { return }
        setHoverBackground(NSColor.clear.cgColor)
    }

    // MARK: - Keyboard row selection

    /// Set by actionable rows only; other clickable views never take row focus.
    var keyFocusFill: NSColor?
    private(set) var keyFocused = false

    /// A stronger held hover fill distinguishes keyboard selection from pointer
    /// hover without placing a bright strip against the status glyph.
    /// The row's own layer follows its bounds through peek reflow, with no animation.
    func setKeyFocused(_ focused: Bool) {
        guard focused != keyFocused, let fill = keyFocusFill else { return }
        keyFocused = focused
        // Selection is queryable independently of the native editor's key focus.
        setAccessibilitySelected(focused)
        wantsLayer = true
        layer?.removeAnimation(forKey: "hoverFill")   // 0ms — never ride a hover fade out/in
        if focused {
            layer?.backgroundColor = fill.withAlphaComponent(min(1, fill.alphaComponent * 1.8)).cgColor
        } else {
            // Hand-back keeps the one vocabulary: a row the pointer still rests on
            // stays hovered (fill only); otherwise the ink retires completely.
            let stillHovered: NSColor? = (hoverFill != nil && pointerInside()) ? hoverFill : nil
            layer?.backgroundColor = stillHovered?.cgColor ?? NSColor.clear.cgColor
        }
    }

    private func pointerInside() -> Bool {
        guard let window else { return false }
        // visibleRect, not bounds: a row half-scrolled out of its lane must not light
        // from the clipped part (mirrors the tracking area's own `.inVisibleRect`).
        return visibleRect.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    /// Re-evaluate the hover fill from the pointer's ACTUAL position — for content that
    /// moved under a stationary pointer (a lane scroll): tracking areas fire on pointer
    /// movement, not content movement, so the exit never arrives and the fill lingers
    /// (dogfood 2026-07-14). Idempotent with the enter/exit pair; a key-focused row
    /// keeps its held fill (the WP-6k one-vocabulary rule), exactly like `mouseExited`.
    func refreshHover() {
        guard let hoverFill, !keyFocused else { return }
        wantsLayer = true
        let target = pointerInside() ? hoverFill.cgColor : NSColor.clear.cgColor
        guard layer?.backgroundColor != target else { return }   // no re-fade per scroll tick
        setHoverBackground(target)
    }

    /// Ease the hover highlight in/out over ~0.12s. This motion maps 1:1 to the pointer entering
    /// or leaving a clickable target (a user action) — never idle motion — so attention-non-theft
    /// holds. Reduce-Motion (a11y) collapses it to an instant swap.
    private func setHoverBackground(_ color: CGColor) {
        guard let layer else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.removeAnimation(forKey: "hoverFill")
            layer.backgroundColor = color
            return
        }
        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        fade.toValue = color
        fade.duration = 0.12
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "hoverFill")
        layer.backgroundColor = color   // model value = destination, so it sticks after the animation
    }
    // Authoritative hover cursor on a borderless overlay panel (cursor rects are unreliable here).
    override func cursorUpdate(with event: NSEvent) {
        (hoverFill != nil ? NSCursor.pointingHand : NSCursor.arrow).set()
    }
}

/// A small icon control (the in-island gear + the collapse chevron). Gesture-driven like
/// the rows — NOT an `NSButton`, which is unreliable under a non-key panel — so it always
/// fires on the first click, with a hover highlight + pointing-hand cursor (discoverable).
final class IconButton: IslandClickableView {
    private let action: () -> Void

    init(symbol: String, tooltip: String, tint: NSColor, hover: NSColor, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        hoverFill = hover
        toolTip = tooltip
        translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        icon.contentTintColor = tint
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 24),
            heightAnchor.constraint(equalToConstant: 22),
            icon.centerXAnchor.constraint(equalTo: centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(tooltip)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { action() }
    override func accessibilityPerformPress() -> Bool { action(); return true }
}
