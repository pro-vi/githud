import AppKit
import GithudCore
import ServiceManagement

/// Owns the menu-bar presence. LEFT-click the item toggles the island (summon);
/// RIGHT-click (or Control-click) opens the menu — a "Surface…" submenu (which
/// reason-types surface), a "Theme" submenu, "Launch at Login" + "Hide/Show island"
/// (WP-5i), and Quit. The in-island gear opens the SAME menu (see `showGearMenu`), so
/// every one of these is reachable without right-clicking.
///
/// WP-5g, superseded by WP 2026-07-22-001 ("the g takes the bar"): the item is no longer a
/// static identity mark — it draws a LIVE 18×18pt template glyph per
/// `StatusGlyphPresenter.descriptor` (Core owns the trust logic; this class only inks it):
/// the constant Glyphling g whose EYE does the states — half-lid at ease when clear, a
/// locked pupil + count-as-text when action is needed, a sidelong pupil while unconfirmed,
/// a dilated pupil (whole mark α0.55) pre-first-poll — the shield for the one categorical
/// critical, and dashed arcs flanking the mark when the reading degrades. Update trigger is
/// MODEL MUTATION ONLY (the same `AppModel`
/// observer seam the panel renders from) — no timers, no polling of its own
/// (`idle-footprint`); motion is a one-shot 180ms crossfade on clear↔action↔critical class
/// changes only, 0ms for count/freshness swaps (`attention-non-theft`), instant under
/// Reduce Motion. Template ink means the gray-swap law is physics here, not an audit
/// (`color-doctrine`). The click/menu contract above is untouched.
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    /// The single observable app state (WP-6a) — read on glyph renders, observed for the
    /// changes that can alter the glyph/tooltip. Mutated ONLY by AppDelegate.
    private let model: AppModel
    /// The last descriptor actually drawn — the change guard (an identical descriptor
    /// repaints nothing) and the crossfade baseline (class change vs 0ms hard swap).
    /// `nil` while the identity fallback is showing (message state) or before first render.
    private var lastGlyphDescriptor: StatusGlyphDescriptor?
    private let onToggle: () -> Void
    private let onQuit: () -> Void
    /// Open the in-island Settings card (mark-and-settings option B, dogfood-ratified
    /// 2026-07-14): every config the dropdown used to hold lives there; this menu is
    /// VERBS only — Settings… / Hide-Show / Quit.
    private let onOpenSettings: () -> Void
    /// Whether the island is currently shown (drives the "Hide island"/"Show island"
    /// item's title + the reverse action) — read fresh on every menu open, never cached,
    /// so the item can never claim a state the panel isn't actually in.
    private let currentVisibility: () -> Bool
    private let onToggleVisibility: () -> Void
    private let menu = NSMenu()
    /// Title/checkmark is "Hide island"/"Show island" by `currentVisibility()` — one item
    /// (WP-5i), reachable from BOTH the right-click menu and the in-island gear menu (they
    /// share this same `NSMenu` instance).
    private let visibilityItem = NSMenuItem()

    init(model: AppModel,
         onToggle: @escaping () -> Void,
         onQuit: @escaping () -> Void,
         onOpenSettings: @escaping () -> Void = {},
         currentVisibility: @escaping () -> Bool,
         onToggleVisibility: @escaping () -> Void) {
        self.model = model
        self.onToggle = onToggle
        self.onQuit = onQuit
        self.onOpenSettings = onOpenSettings
        self.currentVisibility = currentVisibility
        self.onToggleVisibility = onToggleVisibility
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(buttonClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            // Layer-backed once, up front, so the one-shot class-change crossfade
            // (`renderGlyph`) never flips layer-backing mid-flight.
            button.wantsLayer = true
        }

        menu.delegate = self   // refreshes visibilityItem's live state on every open

        // VERBS ONLY (mark-and-settings option B, dogfood-ratified 2026-07-14): all
        // config — surface reasons, theme, pill style, lens, launch-at-login — lives in
        // the in-island Settings card. The dropdown keeps just the doors and exits.
        let settingsItem = NSMenuItem(title: PlainWords.settingsMenuItem,
                                      action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        visibilityItem.action = #selector(toggleVisibility)
        visibilityItem.target = self
        menu.addItem(visibilityItem)   // title set live in menuNeedsUpdate ("Hide island"/"Show island")

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit githud", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        // WP-5g: the glyph re-renders on MODEL MUTATION ONLY — the same observer seam the
        // panel renders from (WP-6a). No timer, no polling, no ambient repaint
        // (`idle-footprint`): `.radar`/`.freshness`/`.ledger` can change the drawn mark;
        // `.pulse` can change only the TOOLTIP (the H2 gauge is spoken, never drawn —
        // H1-only ratified scope), and `renderGlyph`'s descriptor guard makes every other
        // notification a no-op paint-wise. Theme/a11y-appearance changes are irrelevant to
        // a template image (the system tints it per bar appearance). Weak self breaks the
        // model→observer→controller cycle, mirroring HUDPanelController's registration.
        model.addObserver { [weak self] change in
            switch change {
            case .radar, .pulse, .freshness, .ledger, .pillStyle, .sweepFreshness:
                // .pillStyle changes only the TOOLTIP's inbound phrasing (the drawn mark is
                // radar-only, unchanged) — renderGlyph refreshes the tooltip before its
                // descriptor guard, so a style switch keeps the hover text in sync.
                // .sweepFreshness (D1, F-1): same tooltip-only reach — the spoken value's
                // stale prefix reads the sweep clock for inbound facts; the drawn mark's
                // degraded dash stays poll-clock only (descriptor guard makes it a no-op).
                self?.renderGlyph()
            case .inbound, .pulsePreferences, .inboundPreferences, .surfacePreferences, .theme,
                 .reduceTransparency, .increaseContrast, .pillStyleChooser,
                 .lensPreferences, .selfLogin, .lensChooser, .settingsCard:
                // .inbound deliberately no-op: the bar glyph speaks the RADAR's action count
                // only — the standing queue lives in the island (recorded lane decision).
                // .lensPreferences/.selfLogin (owner lens): island-lane concerns only — the
                // bar mark and tooltip never speak per-owner facts.
                break
            }
        }
        renderGlyph()   // initial paint — pre-first-poll this is the LOADING mark (the g, dilated pupil, α0.55, no title)
    }

    // MARK: - the live glyph (WP-5g / D-glyph `constant-mark-count-text`, amended)

    /// Repaint the status item from the model. Pure decision first (`StatusGlyphPresenter`
    /// owns priority/composition — tested in Core), ink second. Change-guarded: an identical
    /// descriptor repaints nothing (a poll tick that changes nothing costs a string compare,
    /// no image build — `idle-footprint`). Motion: ONLY a clear↔action↔critical class change
    /// earns the one-shot 180ms opacity crossfade (cubic-bezier(0.25,0.1,0.25,1)); count-text
    /// and degraded-dash changes are 0ms hard swaps, and Reduce Motion drops the crossfade
    /// entirely (`attention-non-theft`: motion maps 1:1 to a real action-class change).
    private func renderGlyph() {
        guard let button = statusItem.button else { return }

        // Identity fallback (scope C): the descriptor set deliberately does NOT model the
        // setup/auth ledger-card state (no token, 401/403, wrong shape, Keychain failure) — a
        // loading mark there would promise a first poll that may never come, and any of the
        // four data marks would fabricate a reading. The static identity glyph — today's
        // exact mark — carries "githud is here, click it" and nothing more. Also the safety
        // net for any future state the descriptor doesn't cover: never crash the bar.
        guard model.ledger == nil else {
            if lastGlyphDescriptor != nil || button.image == nil {
                button.image = NSImage(systemSymbolName: "dot.radiowaves.left.and.right",
                                       accessibilityDescription: "githud")
                button.image?.isTemplate = true
                button.imagePosition = .imageOnly
                button.title = ""
                button.toolTip = "githud — click to expand/collapse, right-click for menu"
            }
            lastGlyphDescriptor = nil   // next data paint is a hard swap (identity isn't a class)
            return
        }

        let clearConfirmed = model.radarConfirmed && model.inboundConfirmed && model.reviewsConfirmed
        let descriptor = StatusGlyphPresenter.descriptor(
            rows: model.radarRows, pulse: model.pulseRows,
            freshness: model.freshness, loading: !model.hasData,
            clearConfirmed: clearConfirmed)

        // Tooltip first — it can change while the drawn mark doesn't (the spoken value
        // carries the H2 gauge and the exact uncapped count). Copy verbatim from the
        // ratified spec, via the SAME presenter the pill speaks through.
        let value = PillAccessibilityPresenter.value(
            rows: model.radarRows, pulse: model.pulseRows,
            freshness: model.freshness,
            sweepFreshness: FreshnessModel.sweepStatus(lastSweepSuccess: model.lastInboundSuccessAt, now: Date()),
            loading: !model.hasData,
            inboundActive: InboundPresenter.sections(for: model.inboundRows).active.count,
            style: model.pillStyle,
            clearConfirmed: clearConfirmed)   // the tooltip speaks the user's chosen vocabulary, in parity with the pill
        let tip = StatusGlyphPresenter.toolTip(value: value)
        if button.toolTip != tip { button.toolTip = tip }

        guard descriptor != lastGlyphDescriptor else { return }   // nothing visual changed
        let crossfade = lastGlyphDescriptor.map { StatusGlyphPresenter.crossfades(from: $0, to: descriptor) } ?? false
        lastGlyphDescriptor = descriptor

        if crossfade, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            // One-shot layer fade on the real class change — never a repeating animation,
            // removed by Core Animation on completion (idle-footprint: nothing persists).
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.18
            fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1)
            button.layer?.add(fade, forKey: "githudGlyphCrossfade")
        }

        let image = StatusGlyphRenderer.image(for: descriptor)
        image.accessibilityDescription = value   // VoiceOver hears exactly what the pill would say
        button.image = image
        if let count = descriptor.countText {
            // Count as REAL 12pt text (the only 1x-guaranteed-legible treatment) beside the
            // 18pt mark; monospaced digits so equal-width counts don't wobble the bar.
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
            button.imagePosition = .imageLeading
            button.imageHugsTitle = true   // title sits against the image (≈3px visual gap incl. canvas margin)
            button.title = count
        } else {
            button.imagePosition = .imageOnly   // no title when clear/loading
            button.title = ""
        }
    }

    /// Pop up the unified gear menu (Surface… + Theme + Quit) anchored to a view (the in-island
    /// gear) — the same `menu` the right-click opens, so Themes are findable from the island.
    /// The screen the status item's button currently lives on — `nil` before the button has
    /// a window (shouldn't happen post-init) or if AppKit can't resolve one. WP-5i's screen
    /// anchoring reads this FIRST (the monitor the menu-bar item is actually on), ahead of the
    /// mouse-location/`.main` fallbacks `HUDPanelController.screenProvider` composes.
    var screen: NSScreen? { statusItem.button?.window?.screen }

    @objc private func buttonClicked() {
        // Right-click OR Control-click (a macOS convention for "secondary click") opens the menu;
        // a plain left-click summons the island.
        let event = NSApp.currentEvent
        let isSecondaryClick = event?.type == .rightMouseUp
            || (event?.type == .leftMouseUp && event?.modifierFlags.contains(.control) == true)
        if isSecondaryClick {
            statusItem.menu = menu                         // attach, pop up, detach (so left-click still summons)
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onToggle()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        // Read live, every open — never cache a click's outcome as the truth (WP-5i).
        visibilityItem.title = currentVisibility() ? "Hide island" : "Show island"
    }

    @objc private func openSettings() { onOpenSettings() }

    /// Hide/Show island (WP-5i) — this menu item is the affordance, and the status item
    /// remains the way back in; since WP-5g the item is a LIVE glyph, so a hidden island
    /// still carries the H1 signal (that was D-glyph's whole design question). `hide()`'s
    /// collapse/click-away-monitor-teardown semantics (WP-3e) are untouched — this only
    /// decides WHICH of `hide()`/`show()` to call.
    @objc private func toggleVisibility() { onToggleVisibility() }

    @objc private func quitApp() { onQuit() }
}

/// Draws the 18×18pt TEMPLATE image for a `StatusGlyphDescriptor` — geometry verbatim from
/// docs/plans/2026-07-22-001-g-takes-the-bar-wp.md ("the g takes the bar", render-verified
/// against docs/design/2026-07-12-mark-settings-mocks.html top section), which RETIRES the
/// arcs constant-mark (D-glyph) in favor of the Glyphling g with per-state eyes.
///
/// Template = alpha-only ink: the system tints the mark black/white per bar appearance, so
/// on this fourth surface the color doctrine's gray-swap law is not an audit — it is the
/// physics. Shape and fill weight carry EVERYTHING, including critical ('!' knockout, no hue).
///
/// The constant mark (every non-critical state): the g — a `bowl()` ring (even-odd disc
/// c(9,7.5) r4.8 with the sclera knocked out r2.78) and a `tail()` (stroke 2.1, round caps).
/// Its EYE does the states: a dilated pupil probing (loading), a sidelong pupil still looking
/// (clearUnconfirmed), a half-lid come down at ease (clear), a locked pupil while the count
/// text counts (action). Drawing is y-flipped so the spec's SVG (y-down) coordinates
/// transcribe verbatim. Critical is untouched: the shield supersedes the g entirely.
///
/// Internal (not private) so `GlyphProofCommand` can render the SAME images the bar
/// receives for the visual proof — never a duplicated drawing path that could drift.
enum StatusGlyphRenderer {
    /// Narrowing factor for the critical+degraded shield (the review amendment's "slightly
    /// narrowed" — x only, about the mark's center x=9) and the outward offset that moves
    /// each dashed arc clear of the mark, so the arcs FLANK it as pure freshness chrome. The
    /// SAME offset serves both silhouettes: the narrowed shield spans x≈4.4–13.6 and the g's
    /// bowl spans x 4.2–13.8, so 2.4 sets the left arc's whole span to x≈2.2–3.5 and mirrors
    /// on the right. Clearance off the bowl is NOT uniform: ≈0.7pt of air at the equator
    /// (the arc's midpoint vs the bowl's y-adjusted left edge), tightening to ≈0.19pt
    /// ink-to-fill at the arcs' LOWER ENDPOINTS — still positive, no overlap, render-verified
    /// (WP 2026-07-22-001). The amendment gives no numbers; this is this build's pinned value.
    private static let narrowedShieldScaleX: CGFloat = 0.82
    private static let flankingArcOffset: CGFloat = 2.4

    static func image(for descriptor: StatusGlyphDescriptor) -> NSImage {
        // flipped: true → y-down, matching the spec's SVG coordinates exactly. The handler
        // re-runs per backing scale (1x/2x), so the mark stays vector-crisp on Retina.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            draw(descriptor)
            return true
        }
        image.isTemplate = true   // alpha-only; the system owns the tint
        return image
    }

    private static func draw(_ descriptor: StatusGlyphDescriptor) {
        switch descriptor {
        case .loading:
            // The g PROBING: dilated centered pupil, and the WHOLE mark dimmed to the waking
            // register α0.55 (SPEC DECISION, amendable one-line via `loadingAlpha`) — the
            // pre-first-poll-is-tentative cue the old α0.40 arcs carried, echoing the pill's
            // inkTertiary waking face. Never degraded (loading outranks freshness).
            //
            // A TRANSPARENCY LAYER, not per-path alpha: the tail's root crosses the bowl's
            // annulus, and two overlapping α0.55 paints there would compound to ≈0.80 — a
            // darker seam exactly where the spec says WHOLE mark at α0.55. The layer
            // composites the full-alpha mark first, then dims it uniformly on the way out.
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            ctx.setAlpha(CGFloat(StatusGlyphPresenter.loadingAlpha))
            ctx.beginTransparencyLayer(auxiliaryInfo: nil)
            bowl(); tail(); pupil(cx: 9, cy: 7.5, r: 1.7)
            ctx.endTransparencyLayer()
        case .clearUnconfirmed(let degraded):
            // The g STILL LOOKING: a sidelong pupil, FULL alpha (never dimmed — the A2 lesson:
            // unconfirmed is form-distinct, not alpha-distinct). githud hasn't finished reading
            // every source, so the eye has not yet come to rest.
            if degraded { strokeArcs(dashed: true, outwardOffset: flankingArcOffset) }
            bowl(); tail(); pupil(cx: 9.65, cy: 6.85, r: 1.45)
        case .clear(let degraded):
            // The g AT EASE: the half-lid comes down (the filled upper segment of the sclera
            // above the chord y=6.525) and the pupil settles low — done looking, every source
            // confirmed. The pack's own at-ease face, identical anatomy to the app icon.
            if degraded { strokeArcs(dashed: true, outwardOffset: flankingArcOffset) }
            bowl(); tail(); halfLid(); pupil(cx: 9, cy: 8.35, r: 1.2)
        case .action(_, let degraded):
            // The g with a LOCKED pupil while the count TEXT does the counting (the count-text
            // plumbing lives in `renderGlyph`, untouched — text presence is the structural
            // separator from loading, which shares the centered-pupil silhouette).
            if degraded { strokeArcs(dashed: true, outwardOffset: flankingArcOffset) }
            bowl(); tail(); pupil(cx: 9, cy: 7.5, r: 1.45)
        case .critical(_, let degraded):
            // UNTOUCHED (WP 2026-07-22-001 leaves the shield exactly as landed): the shield
            // supersedes the g entirely, including its own degraded flanking-arc rule.
            if degraded {
                // BINDING amendment: degraded COMPOSES over critical — the dashed arc pair
                // returns, flanking a slightly-narrowed shield, so the crisp shield can
                // never hide a reading that may be minutes dead.
                strokeArcs(dashed: true, outwardOffset: flankingArcOffset)
                shield(narrowed: true)
            } else {
                shield(narrowed: false)   // identity yields fully to the one emergency
            }
        }
    }

    /// The arc pair. `outwardOffset` slides each arc away from center (the flanking chrome
    /// of every degraded composition); `dashed` is the degraded-reading cue (spec: dash
    /// ≈2.25/1.6, round caps — caution carried by shape, never hue). The old `alpha`
    /// parameter left with the arcs-only loading mark it served (WP 2026-07-22-001 fix
    /// round): every remaining caller strokes at full ink.
    private static func strokeArcs(dashed: Bool, outwardOffset: CGFloat = 0) {
        NSColor.black.setStroke()
        let arcs: [(dx: CGFloat, start: CGFloat, end: CGFloat)] = [
            (-outwardOffset, 135, 225),   // left arc — bulges left
            (outwardOffset, -45, 45),     // right arc — bulges right
        ]
        for arc in arcs {
            let path = NSBezierPath()
            path.appendArc(withCenter: NSPoint(x: 9 + arc.dx, y: 9), radius: 4.4,
                           startAngle: arc.start, endAngle: arc.end, clockwise: false)
            path.lineWidth = 1.5
            path.lineCapStyle = .round
            if dashed { path.setLineDash([2.25, 1.6], count: 2, phase: 0) }
            path.stroke()
        }
    }

    /// The g's BOWL — the ring: even-odd fill of the outer disc c(9,7.5) r4.8 minus the
    /// sclera knockout r2.78 (same center). Always full ink — loading's whole-mark dim
    /// happens in the transparency layer above, never per-path (which would double-darken
    /// where the tail crosses this annulus). The sclera knockout is the eye's white — the
    /// pupil and the half-lid draw INTO it.
    private static func bowl() {
        NSColor.black.setFill()
        let path = NSBezierPath()
        path.appendOval(in: NSRect(x: 9 - 4.8, y: 7.5 - 4.8, width: 9.6, height: 9.6))
        path.appendOval(in: NSRect(x: 9 - 2.78, y: 7.5 - 2.78, width: 5.56, height: 5.56))
        path.windingRule = .evenOdd
        path.fill()
    }

    /// The g's TAIL — the descending curl: stroke 2.1, round caps. Path verbatim from the
    /// spec (M12.3 10.5 C13.4 12.45 12.98 14.7 10.7 15.4 C9.75 15.7 8.85 15.45 8.25 14.9).
    /// Always full ink (loading dims via the transparency layer, see `draw`).
    private static func tail() {
        NSColor.black.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 12.3, y: 10.5))
        path.curve(to: NSPoint(x: 10.7, y: 15.4),
                   controlPoint1: NSPoint(x: 13.4, y: 12.45), controlPoint2: NSPoint(x: 12.98, y: 14.7))
        path.curve(to: NSPoint(x: 8.25, y: 14.9),
                   controlPoint1: NSPoint(x: 9.75, y: 15.7), controlPoint2: NSPoint(x: 8.85, y: 15.45))
        path.lineWidth = 2.1
        path.lineCapStyle = .round
        path.stroke()
    }

    /// The g's PUPIL — a solid ink disc at (cx,cy) r. The eye's whole state vocabulary rides
    /// this one atom's size and position: dilated centered (loading), sidelong (unconfirmed),
    /// resting low (clear), locked centered (action). Always full ink (loading dims via the
    /// transparency layer, see `draw`).
    private static func pupil(cx: CGFloat, cy: CGFloat, r: CGFloat) {
        NSColor.black.setFill()
        NSBezierPath(ovalIn: NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)).fill()
    }

    /// The g AT EASE's HALF-LID — the filled upper segment of the sclera above the chord
    /// y=6.525 (spec: M6.4 6.525 A2.78 2.78 0 0 1 11.6 6.525 Z). Both endpoints lie on the
    /// sclera circle (c(9,7.5) r2.78); the arc runs over its TOP (y≈4.72), and `close()` draws
    /// the chord back — filling the eyelid-down segment. Angles are derived from the endpoints
    /// so the fill lands exactly on the sclera; `clockwise:false` sweeps through the top (in
    /// this flipped:true context that is the minor, upper arc — render-verified).
    private static func halfLid() {
        NSColor.black.setFill()
        let start = atan2(6.525 - 7.5, 6.4 - 9) * 180 / .pi
        let end = atan2(6.525 - 7.5, 11.6 - 9) * 180 / .pi
        let lid = NSBezierPath()
        lid.appendArc(withCenter: NSPoint(x: 9, y: 7.5), radius: 2.78,
                      startAngle: start, endAngle: end, clockwise: false)
        lid.close()
        lid.fill()
    }

    /// CRITICAL: filled shield (spec path verbatim) with the '!' knocked out via
    /// destination-out — mirrors the row set's exclamationmark.shield.fill, shape-only.
    /// `narrowed` applies the critical+degraded x-compression about center (the knockout
    /// stays unscaled: it is comfortably inside the narrowed silhouette and the '!' must
    /// not lose weight exactly when two facts are on display).
    private static func shield(narrowed: Bool) {
        // x' = 9 + (x − 9) · scale — computed per point (no transform-order ambiguity).
        func nx(_ x: CGFloat) -> CGFloat { narrowed ? 9 + (x - 9) * narrowedShieldScaleX : x }
        let path = NSBezierPath()
        path.move(to: NSPoint(x: nx(9), y: 1.9))
        path.line(to: NSPoint(x: nx(14.6), y: 4.1))
        path.curve(to: NSPoint(x: nx(13.3), y: 12.2),
                   controlPoint1: NSPoint(x: nx(14.6), y: 4.1), controlPoint2: NSPoint(x: nx(14.9), y: 9.4))
        path.curve(to: NSPoint(x: nx(9), y: 16.1),
                   controlPoint1: NSPoint(x: nx(11.9), y: 14.6), controlPoint2: NSPoint(x: nx(9), y: 16.1))
        path.curve(to: NSPoint(x: nx(4.7), y: 12.2),
                   controlPoint1: NSPoint(x: nx(9), y: 16.1), controlPoint2: NSPoint(x: nx(6.1), y: 14.6))
        path.curve(to: NSPoint(x: nx(3.4), y: 4.1),
                   controlPoint1: NSPoint(x: nx(3.1), y: 9.4), controlPoint2: NSPoint(x: nx(3.4), y: 4.1))
        path.close()
        NSColor.black.setFill()
        path.fill()

        // Knockout: bar (8.2, 5.3, 1.6×4.4, r=0.8) + dot ((9,12), r=1), destination-out —
        // the emergency marker survives the gray swap because it is carved, not colored.
        guard let context = NSGraphicsContext.current else { return }
        let saved = context.compositingOperation
        context.compositingOperation = .destinationOut
        NSBezierPath(roundedRect: NSRect(x: 8.2, y: 5.3, width: 1.6, height: 4.4),
                     xRadius: 0.8, yRadius: 0.8).fill()
        NSBezierPath(ovalIn: NSRect(x: 8, y: 11, width: 2, height: 2)).fill()
        context.compositingOperation = saved
    }
}
