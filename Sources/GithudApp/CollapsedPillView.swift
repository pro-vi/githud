import AppKit
import GithudCore

/// The calm, collapsed island: a small pill showing the count + the most-urgent
/// glyph (or a check when clear). This is the default state — ambient, not a
/// persistent guilt-list (consults 002/003). Click the pill (or the menu-bar item) to expand.
///
/// WP-3x (ratified `slot-morph-inkfocus`, pill half): every state renders into ONE shared
/// chassis — [stale prefix slot, when degraded][glyph cell][gap 6][value cell] — so a
/// cross-state change can repaint ONLY the cell whose fact changed. The transition rules
/// live in `GithudCore.PillMorph` (pure, tested); this view just executes a `Plan`:
/// equal-digit value ticks swap text in place (0ms — exactly the old single-frame swap),
/// fading cells crossfade 120ms, and the invariant **no motion where no fact changed**
/// holds structurally because unchanged cells are never touched (same view instances).
final class CollapsedPillView: IslandClickableView {
    static let height: CGFloat = 36
    private let onTap: (() -> Void)?
    private let theme: Theme

    // The chassis (always these three hosts, in order; unused cells are hidden and
    // detached, so the rendered geometry — spacings, widths — is identical to the
    // pre-chassis pill and the existing width formulas below stay unchanged).
    private let prefixHost = PillCellHost()
    private let glyphHost = PillCellHost()
    private let valueHost = PillCellHost()
    private var stackCenterX: NSLayoutConstraint!

    /// A thin wrapper over the PURE width formula in `GithudCore.PillMorph` (which the F5
    /// style-matrix test pins headlessly): resolve the fingerprint for this (style × state),
    /// take its width. The pill's rendered geometry is therefore the tested formula, never a
    /// second copy that could drift — the two composed cases and the D2 reorder live in ONE
    /// place (`PillMorph.resolve` / `PillMorph.width`).
    static func size(for rows: [RadarRow], pulse: [PulseRow] = [], loading: Bool = false,
                     freshness: Freshness = .fresh, sweepFreshness: Freshness = .fresh,
                     inboundActive: Int = 0, style: PillStyle = .queueLeads,
                     clearConfirmed: Bool = false) -> NSSize {
        let fingerprint = PillMorph.fingerprint(rows: rows, pulse: pulse, loading: loading,
                                                freshness: freshness, sweepFreshness: sweepFreshness,
                                                inboundActive: inboundActive, style: style,
                                                clearConfirmed: clearConfirmed)
        return NSSize(width: PillMorph.width(for: fingerprint), height: height)
    }

    init(rows: [RadarRow], pulse: [PulseRow] = [], freshness: Freshness = .fresh,
         sweepFreshness: Freshness = .fresh, theme: Theme, loading: Bool = false,
         inboundActive: Int = 0, style: PillStyle = .queueLeads,
         clearConfirmed: Bool = false, onTap: (() -> Void)? = nil) {
        self.onTap = onTap
        self.theme = theme
        super.init(frame: NSRect(origin: .zero, size: CollapsedPillView.size(
            for: rows, pulse: pulse, loading: loading, freshness: freshness,
            sweepFreshness: sweepFreshness, inboundActive: inboundActive, style: style,
            clearConfirmed: clearConfirmed)))

        if onTap != nil {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
            wantsLayer = true
            layer?.cornerRadius = 14
            layer?.cornerCurve = .continuous
            hoverFill = theme.hoverFill   // base lights the whole pill + shows a pointing hand on hover
            setAccessibilityElement(true)
            setAccessibilityRole(.button)
            setAccessibilityLabel("githud — expand")
            // The pill is the product's thesis surface ("does GitHub need me right now?")
            // made speakable — built from the SAME inputs (rows/pulse/freshness/loading)
            // the glyph stack above uses, via the pure Core presenter (gray-swap a11y law:
            // the spoken value must carry the same meaning the color/shape/count do). Kept
            // current on every render — the full rebuild AND the in-place slot morph
            // (`applyTransition`) both set it, so it can never go stale.
            setAccessibilityValue(PillAccessibilityPresenter.value(rows: rows, pulse: pulse, freshness: freshness,
                                                                   sweepFreshness: sweepFreshness, loading: loading,
                                                                   inboundActive: inboundActive, style: style,
                                                                   clearConfirmed: clearConfirmed))
        }

        // Render the chassis from the SAME pure fingerprint the transition planner diffs —
        // one derivation of "what does the pill show", shared with GithudCore.
        let fingerprint = PillMorph.fingerprint(rows: rows, pulse: pulse, loading: loading,
                                                freshness: freshness, sweepFreshness: sweepFreshness,
                                                inboundActive: inboundActive, style: style,
                                                clearConfirmed: clearConfirmed)
        prefixHost.swapContent(fingerprint.stalePrefix ? makePrefixContent() : nil)
        glyphHost.swapContent(makeGlyphContent(fingerprint.glyph))
        valueHost.swapContent(makeValueContent(fingerprint.value))

        let stack = NSStackView(views: [prefixHost, glyphHost, valueHost])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.detachesHiddenViews = true   // hidden cells take no width and no spacing
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        stackCenterX = stack.centerXAnchor.constraint(equalTo: centerXAnchor)
        NSLayoutConstraint.activate([
            stackCenterX,
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onTap?() }
    override func accessibilityPerformPress() -> Bool {
        guard onTap != nil else { return false }
        onTap?(); return true
    }

    // MARK: - WP-3x slot morph (in-place cell transitions)

    /// Apply a cross-state transition IN PLACE (no teardown/rebuild): only the cells in
    /// `plan.changed` repaint — `plan.fades` cells crossfade 120ms, equal-digit value
    /// ticks swap text instantly (tabular digits: zero pixels move). Unchanged cells are
    /// literally untouched (same view instances) — the strongest possible reading of the
    /// invariant "no motion where no fact changed" (see `PillMorph`).
    ///
    /// The caller then wraps `beginWidthSettle()` + the panel frame ease in ONE 150ms
    /// animation group; anything that must slide (the chassis re-centering around a new
    /// width) slides on that curve, never jumps.
    func applyTransition(to fingerprint: PillMorph.Fingerprint, plan: PillMorph.Plan,
                         accessibilityValue: String) {
        // Anti-jump anchor: an unchanged, visible cell must not move at t=0. Measure its
        // offset-from-center before and after the chassis reflow, hold the chassis so the
        // anchor stays put, and let `beginWidthSettle()` ease that hold back to center.
        let cells: [(host: PillCellHost, id: PillMorph.Cell)] =
            [(glyphHost, .glyph), (valueHost, .value), (prefixHost, .prefix)]
        let reference = cells.first { !$0.host.isHidden && !plan.changed.contains($0.id) }?.host
        layoutSubtreeIfNeeded()
        let oldOffset = reference.map { $0.frame.midX - bounds.midX }

        if plan.changed.contains(.prefix) {
            crossfadeCell(prefixHost, to: fingerprint.stalePrefix ? makePrefixContent() : nil)
        }
        if plan.changed.contains(.glyph) {
            // The ink↔danger critical transition rides this same glyph crossfade (the ONE
            // sanctioned animated color transition — color doctrine's exact case): isCritical
            // is part of the glyph fact, so a critical arrival/departure IS a glyph change.
            crossfadeCell(glyphHost, to: makeGlyphContent(fingerprint.glyph))
        }
        if plan.changed.contains(.value) {
            if plan.fades.contains(.value) {
                crossfadeCell(valueHost, to: makeValueContent(fingerprint.value))
            } else {
                updateValueInPlace(fingerprint.value)   // rule (a): instant, exactly today
            }
        }
        setAccessibilityValue(accessibilityValue)

        if let reference, let oldOffset {
            layoutSubtreeIfNeeded()
            let delta = oldOffset - (reference.frame.midX - bounds.midX)
            if abs(delta) > 0.5 {
                stackCenterX.constant = delta
                layoutSubtreeIfNeeded()
            }
        }
    }

    /// Call INSIDE the controller's 150ms width-settle animation group: releases the
    /// anti-jump hold so the chassis re-centers on the same curve the panel width eases on.
    func beginWidthSettle() {
        stackCenterX.animator().constant = 0
    }

    /// Crossfade one cell: the outgoing content is ghosted at its current pill position
    /// (fading 1→0 over the first 80ms) while the incoming content fades 0→1 over the
    /// last 80ms (40ms overlap — the ratified 120ms cell fade, cubic-bezier(0.4,0,0.2,1)).
    ///
    /// The ghost is anchored to the pill's CENTER (its offset-from-center captured at t=0),
    /// NOT to a fixed pill-local frame. When the transition also changes the pill WIDTH, the
    /// panel re-centers on screen (midX held — the drift proof) so the pill's left edge slides;
    /// a left-edge-relative ghost would ride that edge (~Δwidth/2 px) opposite the settling
    /// live cells — "ink travels," the doctrine line this fades AT its position. A centerX/Y
    /// constraint keeps the ghost screen-fixed for the whole 80ms fade regardless of how far
    /// off-center the cell is (an autoresizing mask would only hold a *centered* cell put — its
    /// margin split can't screen-anchor an off-center one).
    private func crossfadeCell(_ host: PillCellHost, to newContent: NSView?) {
        let curve = CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1)
        if let old = host.content, !host.isHidden {
            let ghostFrame = convert(old.frame, from: host)
            host.swapContent(nil)
            old.translatesAutoresizingMaskIntoConstraints = false
            addSubview(old)
            NSLayoutConstraint.activate([
                old.centerXAnchor.constraint(equalTo: centerXAnchor, constant: ghostFrame.midX - bounds.midX),
                old.centerYAnchor.constraint(equalTo: centerYAnchor, constant: ghostFrame.midY - bounds.midY),
                old.widthAnchor.constraint(equalToConstant: ghostFrame.width),
                old.heightAnchor.constraint(equalToConstant: ghostFrame.height),
            ])
            InkFade.run(old, to: 0, delay: 0, duration: 0.08, curve: curve)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak old] in
                old?.removeFromSuperview()   // one-shot cleanup, no repeating timer
            }
        } else {
            host.swapContent(nil)
        }
        if let newContent {
            host.swapContent(newContent)
            InkFade.run(newContent, from: 0, to: 1, delay: 0.04, duration: 0.08, curve: curve)
        }
    }

    /// Rule (a) — the equal-digit tick: update the number(s) in place, 0ms. Tabular
    /// digits guarantee zero pixel movement; the plan guarantees the structure (segment
    /// states, order, digit counts) is unchanged, so a positional zip is safe.
    private func updateValueInPlace(_ value: PillMorph.Value) {
        switch value {
        case .count(let text):
            (valueHost.content as? NSTextField)?.stringValue = text
        case .gauge(let segments):
            guard let inner = valueHost.content as? NSStackView else { return }
            updateGaugeCounts(segments, in: inner)
        case .standing(let segments, let queue):
            // The plan guarantees identical structure (same gauge segments, same queue-print
            // case, equal digit counts), so a positional update is safe: the gauge segments
            // ride the LEADING arranged subviews, the queue rides last.
            guard let inner = valueHost.content as? NSStackView else { return }
            updateGaugeCounts(segments, in: inner)
            if case .count(let q) = queue, let last = inner.arrangedSubviews.last as? NSStackView {
                (last.arrangedSubviews.last as? NSTextField)?.stringValue = q   // mark carries no digits
            }
        case .none:
            break
        }
    }

    /// Update each gauge segment's count text in place (leading arranged subviews).
    private func updateGaugeCounts(_ segments: [PillMorph.GaugeSegmentPrint], in inner: NSStackView) {
        for (seg, view) in zip(segments, inner.arrangedSubviews) {
            ((view as? NSStackView)?.arrangedSubviews.last as? NSTextField)?.stringValue = seg.count
        }
    }

    // MARK: - cell content (one builder per chassis cell, driven by the fingerprint)

    /// A degraded reading prepends a caution clock to the whole glance (staleness must
    /// reach the collapsed pill — that's where you trust it without expanding).
    private func makePrefixContent() -> NSView {
        let clock = NSImageView()
        clock.image = NSImage(systemSymbolName: "clock.badge.exclamationmark", accessibilityDescription: "reading may be stale")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
        clock.contentTintColor = theme.caution
        return clock
    }

    private func makeGlyphContent(_ glyph: PillMorph.Glyph) -> NSView? {
        switch glyph {
        case .loading:
            // Haven't polled yet — DON'T claim "all clear" (that would be a trust lie).
            // The waking face (Glyphling g, WP 2026-07-16-001): a dim, still app-creature
            // until the first radar lands, drawn in code and tinted with the SAME `inkTertiary`
            // the old dim dot carried — the "not yet polled, don't over-assert" doctrine is in
            // the ink tier, unchanged; only the shape woke up. STATIC — no timers, no motion.
            return WakingFaceView(side: 13, tint: theme.inkTertiary)
        case .radar(let symbol, let critical):
            let icon = NSImageView()
            // The STANDING tray (queueLeads inbound / queue-only) is a still-life mark — a
            // lighter 13pt MEDIUM weight than the radar reason's semibold, ink not danger.
            let isStandingTray = symbol == PillMorph.standingTraySymbol
            icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: isStandingTray ? .medium : .semibold))
            if isStandingTray {
                icon.contentTintColor = theme.inkSecondary   // ink still-life, never a status hue
                return icon
            }
            // Ink by default; the pill goes `danger` ONLY when a critical emergency is
            // present (color doctrine — a hidden critical fact must cross to the collapsed
            // island, because that's where it decides whether you open the HUD). Critical
            // sorts first, so the top row IS the shield glyph when one exists.
            icon.contentTintColor = theme.radarGlyphColor(critical: critical)
            return icon
        case .checkUnconfirmed:
            // The EYE ALONE (WP 2026-07-22-001, "the g takes the bar"): githud hasn't finished
            // reading every source, so the pill wears the family's still-looking mark — iris
            // ring + sidelong night pupil, no bowl, no tail — drawn in code like WakingFaceView
            // and tinted with the SAME `inkTertiary` at FULL alpha (form-distinct, never
            // alpha-distinct: the A2 lesson). Width-matched to the earned ✓ by the pure
            // PillMorph formula (both are value `.none` → 52), so the confirmed flip moves
            // nothing. The two surfaces diverge at confirmed on purpose: the bar rests
            // (half-lid), the pill concludes (✓ — the reading is done).
            return UnconfirmedEyeView(side: 13, tint: theme.inkTertiary)
        case .check:
            let check = NSImageView()
            // Dormant today (the pill is ONE flattened AX element speaking the presenter's
            // value), but if the flattening ever changes this must speak the SAME ratified
            // caught-up line — one vocabulary per state (D-copy sweep, fix round minor 3).
            check.image = NSImage(systemSymbolName: "checkmark",
                                  accessibilityDescription: CaughtUpPresenter.caughtUpLine)?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            check.contentTintColor = theme.inkTertiary
            return check
        case .none:
            return nil   // gauge state — the glyphs live inside the value cell's segments
        }
    }

    private func makeValueContent(_ value: PillMorph.Value) -> NSView? {
        switch value {
        case .none:
            return nil
        case .count(let text):
            let count = NSTextField(labelWithString: text)
            count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)   // steady digit advance
            count.textColor = theme.inkPrimary
            return count
        case .gauge(let segments):
            // Caught up on the inbox, but you have open (non-draft) PRs — the "living
            // gauge", SEGMENTED: ✓ready then ⚠blocked (good news leads, real backlog
            // follows; each count matches its glyph). Drafts/stale never enter the glance
            // (the presenter's `active` section — the ONE home of the live-work rule). Uses
            // GitHub's status badges (theme-independent) so the pill matches the expanded lane.
            return makeGaugeStack(segments)
        case .standing(let segments, let queue):
            // The composed standing tier (standingMarked / standingCounted): the living
            // gauge, then the standing queue riding beside it — a dim count-free MARK, or a
            // still tray + COUNT segment on the gauge's own atoms. Ink either way (the queue
            // is never a status hue).
            let inner = makeGaugeStack(segments)
            switch queue {
            case .mark:
                let mark = NSImageView()
                mark.image = NSImage(systemSymbolName: PillMorph.standingTraySymbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
                mark.contentTintColor = theme.inkTertiary   // presence, dimmed — never a count
                inner.addArrangedSubview(mark)
            case .count(let q):
                let badge = NSImageView()
                badge.image = NSImage(systemSymbolName: PillMorph.standingTraySymbol, accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
                badge.contentTintColor = theme.inkSecondary
                let count = NSTextField(labelWithString: q)
                count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
                count.textColor = theme.inkPrimary
                let segStack = NSStackView(views: [badge, count])
                segStack.orientation = .horizontal
                segStack.alignment = .centerY
                segStack.spacing = 4
                inner.addArrangedSubview(segStack)
            }
            return inner
        }
    }

    /// Build the segmented living-gauge stack (one `[badge, count]` per segment). Shared by
    /// the plain gauge state and the composed standing tier, so the gauge draws identically
    /// whether or not a queue rides beside it.
    private func makeGaugeStack(_ segments: [PillMorph.GaugeSegmentPrint]) -> NSStackView {
        let inner = NSStackView()
        inner.orientation = .horizontal
        inner.alignment = .centerY
        inner.spacing = 6                                // inter-segment gap (was the outer stack's 6)
        for seg in segments {
            let badge = GitHubStatusBadge(.forState(seg.state))

            let count = NSTextField(labelWithString: seg.count)
            count.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)   // steady digit advance
            count.textColor = theme.inkPrimary

            let segStack = NSStackView(views: [badge, count])
            segStack.orientation = .horizontal
            segStack.alignment = .centerY
            segStack.spacing = 4                         // glyph↔count tight; segments spaced by `inner` (6)
            inner.addArrangedSubview(segStack)
        }
        return inner
    }
}

/// One chassis cell (WP-3x): a transparent host that hugs its content exactly — the
/// chassis adds ZERO geometry of its own, so the rendered pill is pixel-identical to the
/// pre-chassis layout. Content swaps in place; an empty host hides (and the stack detaches
/// it, so it takes no width and no spacing).
private final class PillCellHost: NSView {
    private(set) var content: NSView?
    private var pins: [NSLayoutConstraint] = []

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Install new content (pinned to all four edges → the host sizes to it exactly).
    /// `nil` empties and hides the host. The outgoing content is fully detached — the
    /// caller decides whether to ghost it (crossfade) or drop it (instant swap).
    @discardableResult
    func swapContent(_ new: NSView?) -> NSView? {
        let old = content
        NSLayoutConstraint.deactivate(pins)
        pins = []
        old?.removeFromSuperview()
        content = new
        if let new {
            new.translatesAutoresizingMaskIntoConstraints = false
            addSubview(new)
            pins = [
                new.leadingAnchor.constraint(equalTo: leadingAnchor),
                new.trailingAnchor.constraint(equalTo: trailingAnchor),
                new.topAnchor.constraint(equalTo: topAnchor),
                new.bottomAnchor.constraint(equalTo: bottomAnchor),
            ]
            NSLayoutConstraint.activate(pins)
        }
        isHidden = (new == nil)
        return old
    }
}

/// The waking face — Glyphling g, the loading-state creature (WP 2026-07-16-001, ratified
/// mark session; night-pupil cut, round five #2). Drawn in code from the binding vector
/// (viewBox 0 0 24 24) — this is a CLT-only repo with no asset catalogs — and template-tinted
/// with ONE solid theme ink, exactly like every other pill glyph (here `inkTertiary`, the dim
/// loading ink the outgoing dot carried).
///
/// Contract:
/// - Renders the 24-unit vector centered inside `side`×`side` pt (13 in the pill), y-flipped
///   from the SVG frame (SVG y-down → AppKit y-up). `intrinsicContentSize` is `side` square,
///   so the hugging chassis cell sizes to it exactly.
/// - STATIC. No `Timer`, no animation, no idle motion. The face appears with the loading
///   state and leaves with it on the pill's ordinary state-change repaint; a theme/appearance
///   change rebuilds the pill (fresh `tint`), so `draw` needs no dynamic-color resolution.
/// - Template: a single fill/stroke ink; no status hue ever reaches this state.
/// - The highlight knockout (r0.65 c(11.15,9.75)) is DROPPED — it is sub-pixel at 13pt
///   (≈0.35pt); it survives in the vector spec for future scale reuse (see the WP).
private final class WakingFaceView: NSView {
    private let side: CGFloat
    private let tint: NSColor

    init(side: CGFloat, tint: NSColor) {
        self.side = side
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)   // the pill is ONE flattened AX button (spoken by the presenter)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: side, height: side) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Center the 24-unit box in the smaller dimension, then scale + flip y into it.
        let dim = min(bounds.width, bounds.height)
        let s = dim / 24.0
        ctx.saveGState()
        ctx.translateBy(x: (bounds.width - dim) / 2, y: (bounds.height - dim) / 2 + dim)
        ctx.scaleBy(x: s, y: -s)
        tint.setFill()
        tint.setStroke()

        // Bowl: a ring — solid disc r6.4 c(12,10) with the sclera knocked out r3.7 (even-odd).
        let bowl = CGMutablePath()
        bowl.addEllipse(in: CGRect(x: 12 - 6.4, y: 10 - 6.4, width: 12.8, height: 12.8))
        bowl.addEllipse(in: CGRect(x: 12 - 3.7, y: 10 - 3.7, width: 7.4, height: 7.4))
        ctx.addPath(bowl)
        ctx.fillPath(using: .evenOdd)

        // Pupil: a solid ink disc r2.1 c(12,10). (Highlight knockout dropped — sub-pixel here.)
        ctx.addEllipse(in: CGRect(x: 12 - 2.1, y: 10 - 2.1, width: 4.2, height: 4.2))
        ctx.fillPath()

        // Tail: the waking curl — stroke 2.8, round caps.
        let tail = CGMutablePath()
        tail.move(to: CGPoint(x: 16.4, y: 14.0))
        tail.addCurve(to: CGPoint(x: 14.3, y: 20.5),
                      control1: CGPoint(x: 17.9, y: 16.6), control2: CGPoint(x: 17.3, y: 19.6))
        tail.addCurve(to: CGPoint(x: 11.0, y: 19.9),
                      control1: CGPoint(x: 13.0, y: 20.9), control2: CGPoint(x: 11.8, y: 20.6))
        ctx.addPath(tail)
        ctx.setLineWidth(2.8)
        ctx.setLineCap(.round)
        ctx.strokePath()

        ctx.restoreGState()
    }
}

/// The eye alone — the collapsed pill's unconfirmed-clear mark (WP 2026-07-22-001, "the g
/// takes the bar"). githud has an all-clear reading but hasn't confirmed every source, so the
/// pill wears the family's STILL-LOOKING mark: the eye with no bowl and no tail — iris ring +
/// sidelong night pupil. Drawn in code from the binding vector (viewBox 0 0 24 24 — a
/// CLT-only repo with no asset catalogs) and template-tinted with ONE solid theme ink, exactly
/// like `WakingFaceView` (here `inkTertiary` at full alpha — form-distinct, never dimmed).
///
/// Contract:
/// - Renders the 24-unit vector centered inside `side`×`side` pt (13 in the pill), y-flipped
///   from the SVG frame (SVG y-down → AppKit y-up). `intrinsicContentSize` is `side` square,
///   so the hugging chassis cell sizes to it exactly — and the pill's outer width is the pure
///   PillMorph formula (value `.none` → 52, the same slot the earned ✓ takes), so the
///   confirmed flip moves nothing.
/// - STATIC. No `Timer`, no animation, no idle motion. The eye appears with the unconfirmed
///   state and leaves with it on the pill's ordinary state-change repaint; a theme/appearance
///   change rebuilds the pill (fresh `tint`), so `draw` needs no dynamic-color resolution.
/// - Template: a single stroke/fill ink; no status hue ever reaches this state.
private final class UnconfirmedEyeView: NSView {
    private let side: CGFloat
    private let tint: NSColor

    init(side: CGFloat, tint: NSColor) {
        self.side = side
        self.tint = tint
        super.init(frame: NSRect(x: 0, y: 0, width: side, height: side))
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(false)   // the pill is ONE flattened AX button (spoken by the presenter)
        // Dormant today (the pill is ONE flattened AX element speaking the presenter's
        // value), but if the flattening ever changes this must speak the SAME ratified
        // unconfirmed-clear line — one vocabulary per state, the exact belt-and-suspenders
        // the earned ✓'s accessibilityDescription carries (D-copy sweep, fix round minor 3).
        setAccessibilityLabel(CaughtUpPresenter.unconfirmedClearLine)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: NSSize { NSSize(width: side, height: side) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // Center the 24-unit box in the smaller dimension, then scale + flip y into it.
        let dim = min(bounds.width, bounds.height)
        let s = dim / 24.0
        ctx.saveGState()
        ctx.translateBy(x: (bounds.width - dim) / 2, y: (bounds.height - dim) / 2 + dim)
        ctx.scaleBy(x: s, y: -s)
        tint.setStroke()
        tint.setFill()

        // Iris ring: a hollow ring — stroke 2.0, c(12,12) r5.2, no fill.
        ctx.addEllipse(in: CGRect(x: 12 - 5.2, y: 12 - 5.2, width: 10.4, height: 10.4))
        ctx.setLineWidth(2.0)
        ctx.strokePath()

        // Sidelong night pupil: a solid ink disc r2.2 c(12.9,11.1) — cast up-and-out, the
        // still-looking gaze (the same sidelong the bar's unconfirmed g wears).
        ctx.addEllipse(in: CGRect(x: 12.9 - 2.2, y: 11.1 - 2.2, width: 4.4, height: 4.4))
        ctx.fillPath()

        ctx.restoreGState()
    }
}
