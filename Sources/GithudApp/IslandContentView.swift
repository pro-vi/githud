import AppKit
import GithudCore

/// The populated island content: a "Needs you" header with a count badge + the top
/// action-required rows, each with a leading SF Symbol (the *kind* of attention)
/// tinted by the active theme. AppKit-native; no animation, no timers. Every color
/// comes from the injected `Theme` (no hardcoded tints).
///
/// WP-3d′ adds two ratified surfaces:
/// - the CAUGHT-UP AFFIRMATION (D-copy `voice-plainspoken` as amended): fully caught up →
///   a centered block; radar-empty-with-live-PRs → the header slot carries the phrase.
///   All gating/tense logic is `GithudCore.CaughtUpPresenter` (pure, tested); 0ms motion —
///   the block appears with the island rebuild the user's expand caused.
/// - the CHEVRON INLINE PEEK (D-reveal as amended): rows whose measured text truncates
///   grow a trailing disclosure chevron; clicking IT (never the row) un-truncates in
///   place. Open peeks live in a `PeekStash` keyed on stable row ids, carried across data
///   rebuilds by the controller exactly like `ScrollOffsets`, reset on collapse.
/// WP-6k: what the ⌃⌥G key session can DO to the focused row — open (the SAME
/// Open-on-GitHub path a plain click runs, incl. its nil-url no-op guard) and peek
/// (the chevron's own toggle; false when the row has no chevron — D-reveal's ratified
/// Space mapping). Both row classes conform; the session never grows a third
/// capability (the H3 ceiling holds under the keyboard too).
protocol KeySessionActionable: AnyObject {
    @discardableResult func performOpen() -> Bool
    @discardableResult func performPeekToggle() -> Bool
}

final class IslandContentView: NSView {
    static let width: CGFloat = 520

    private let theme: Theme
    private let onGearTap: ((NSView) -> Void)?
    private let onCollapse: (() -> Void)?
    /// WP 2026-07-12-001: the plain-words caption/hide controls flip the SAME preference
    /// the gear items flip (two handles, one truth). These route through the exact toggle
    /// path the gear action uses (AppDelegate.toggleShowStale / toggleShowHeldBackInbound),
    /// so `Change.pulsePreferences` re-renders + eases the height on the existing machinery —
    /// no new state, no new animation. `nil` in headless/measurement contexts.
    private let onToggleStale: (() -> Void)?
    private let onToggleHeldBackInbound: (() -> Void)?
    private let onToggleJustCleared: (() -> Void)?
    /// WP 2026-07-12-001 addendum: the Drafts revealed header's (hide) control flips the SAME
    /// `showDrafts` preference the gear item flips (one truth) — routed through the exact
    /// `AppDelegate.toggleShowDrafts` path, so `Change.pulsePreferences` re-renders on the
    /// existing machinery. `nil` in headless/measurement contexts. NOTE: drafts have no
    /// collapsed caption (preserved asymmetry) — only this fold-back handle from the island.
    private let onToggleDrafts: (() -> Void)?
    /// Owner lens (WP 2026-07-14-001): a folded ledger line's click unfolds its owner —
    /// the SAME transition the lens card and the gear drive (three handles, one truth),
    /// routed through `AppDelegate.toggleFoldedOwner` so the unfold stamps the "N new"
    /// clock and re-renders via `Change.lensPreferences`. `nil` in headless contexts.
    private let onToggleFoldedOwner: ((String) -> Void)?
    /// The lens eye's (and the merged "elsewhere" line's) destination: the lens card.
    private let onOpenLensCard: (() -> Void)?
    private weak var gearButton: NSView?
    private var headerStack: NSStackView!   // pinned (count/gear/collapse stay put while the lanes scroll)
    private var bodyStack: NSStackView!     // the lanes (morph body ink — fades as one block)
    private var footerView: NSView!         // the trust-audit inbox link (fades with the body)
    private var radarScroll: CappedLaneScrollView?  // "Needs you" pane — scrolls independently
    private var inboundScroll: CappedLaneScrollView? // "Inbound" pane (WP 2026-07-09-001)
    private var pulseScroll: CappedLaneScrollView?  // "Your PRs" pane — scrolls independently
    private var radarHeightC: NSLayoutConstraint?   // set to min(content, cap) in fittingHeight()
    private var inboundHeightC: NSLayoutConstraint?
    private var pulseHeightC: NSLayoutConstraint?

    /// WP-3d′ peek state: which rows are un-truncated, keyed on stable id → change
    /// signature (`GithudCore.PeekStash`). Mutated by row toggles; read back by the
    /// controller before a rebuild (`peekStash()`) — the ScrollOffsets contract.
    private var peeks: PeekStash

    /// WP-6k: the actionable row views keyed by STABLE row id — the ink bar's execution
    /// map. Selection DECISIONS live in `GithudCore.KeySession`/`KeySelection` (the
    /// controller owns them); this view only resolves an id to the view wearing the bar.
    /// Headers/captions/stale-count lines never enter the map — only real rows do.
    private var keyRows: [String: IslandClickableView & KeySessionActionable] = [:]
    private var keyFocusedID: String?
    /// Fired after a user peek toggle changed a row's height — the controller re-measures
    /// `fittingHeight()` and eases the panel frame on the WP-3d machinery.
    var onPeekChange: (() -> Void)?

    // WP-3d morph hand-off: the two ink groups the container morph fades on its ratified
    // windows — header 80–200ms (the pill's top band hands off into it), body+footer
    // 120–220ms. Exposing the real subviews (not snapshots) keeps the fades honest ink.
    var morphHeader: NSView { headerStack }
    var morphBody: [NSView] { [bodyStack, footerView].compactMap { $0 } }

    init(rows: [RadarRow], pulse: [PulseRow] = [], inbound: [InboundRow] = [],
         showDrafts: Bool = false, showStale: Bool = false, showHeldBackInbound: Bool = false,
         freshness: Freshness = .fresh, radarConfirmed: Bool = false, inboundConfirmed: Bool = false,
         reviewsConfirmed: Bool = false,
         clearedRows: [ClearedRow] = [], showJustCleared: Bool = false,
         onToggleJustCleared: (() -> Void)? = nil,
         peeks: PeekStash = PeekStash(),
         theme: Theme, onGearTap: ((NSView) -> Void)? = nil, onCollapse: (() -> Void)? = nil,
         onToggleStale: (() -> Void)? = nil, onToggleHeldBackInbound: (() -> Void)? = nil,
         onToggleDrafts: (() -> Void)? = nil,
         lensPreferences: LensPreferences = .default, selfLogin: String? = nil,
         lensLastOpened: [String: Date] = [:],
         onToggleFoldedOwner: ((String) -> Void)? = nil, onOpenLensCard: (() -> Void)? = nil) {
        self.theme = theme
        self.onGearTap = onGearTap
        self.onCollapse = onCollapse
        self.onToggleStale = onToggleStale
        self.onToggleHeldBackInbound = onToggleHeldBackInbound
        self.onToggleJustCleared = onToggleJustCleared
        self.onToggleDrafts = onToggleDrafts
        self.onToggleFoldedOwner = onToggleFoldedOwner
        self.onOpenLensCard = onOpenLensCard
        self.peeks = peeks
        super.init(frame: .zero)

        // WP-3d′ caught-up affirmation: exactly one treatment per state (block XOR header
        // phrase, never per-lane filler). All the trust rules — the radar-confirmation
        // gate (never affirm an inbox that was never once read — fix round 1a), the
        // pill-shared live-work rule, the tense amendment (degraded leaves the present
        // tense), and the age-0 guard (never a fabricated timestamp — fix round 1b) —
        // live in the pure Core presenter.
        let inboundSections = InboundPresenter.sections(for: inbound)
        let caughtUp = CaughtUpPresenter.display(rows: rows, pulse: pulse,
                                                 radarConfirmed: radarConfirmed, freshness: freshness,
                                                 inboundActive: inboundSections.active.count,
                                                 inboundConfirmed: inboundConfirmed,
                                                 reviewsConfirmed: reviewsConfirmed)
        var caughtUpPhrase: String?
        if case .headerPhrase(let phrase) = caughtUp { caughtUpPhrase = phrase }

        // PINNED header: an optional degraded-reading banner + the "Needs you" header
        // (count badge, Surface gear, Collapse chevron). Stays put while the lanes scroll,
        // so Collapse/Surface are always reachable no matter how far you've scrolled.
        var headerViews: [NSView] = []
        // Reading-freshness banner (the sanctioned `caution` use): ONLY when degraded —
        // a stalled/failing poll leaves last-good data on screen, so say so. Quiet otherwise.
        if let banner = freshnessBanner(freshness) { headerViews.append(banner) }
        headerViews.append(makeHeader(count: rows.count, caughtUpPhrase: caughtUpPhrase))
        let header = NSStackView(views: headerViews)
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 8
        header.translatesAutoresizingMaskIntoConstraints = false
        headerStack = header

        // TWO independent scroll panes — the H1 "Needs you" radar and the H2 "Your PRs"
        // pulse each scroll WITHIN their own pane, so a long notification list never pushes
        // your PRs off-screen (and vice-versa). When a lane is EMPTY it simply doesn't render
        // (no "all clear" placeholder) — the island shows only what's actually there.
        var radarPane: NSView? = nil
        // The "Just cleared" departure receipt (plan 2026-07-21-001, caption B1): one
        // reveal-line in the caption family, riding the radar lane — collapsed → the
        // caption button; revealed → header + dimmed one-line rows with a reason suffix
        // ONLY where the reading actually knew one. Display-only: these views never
        // enter `rows`, so the affirmation/pill/glyph never see them.
        var radarViews: [NSView] = rows.map { radarRowView($0) }
        if showJustCleared {
            if !clearedRows.isEmpty {
                radarViews.append(revealedHeader(PlainWords.justClearedHeader, onHide: onToggleJustCleared))
            }
            radarViews += clearedRows.map { clearedRowView($0) }
        } else if !clearedRows.isEmpty {
            radarViews.append(captionButton(
                text: PlainWords.justClearedCaption(clearedRows.count),
                spoken: PlainWords.justClearedCaptionSpoken(clearedRows.count),
                onClick: onToggleJustCleared))
        }
        if !radarViews.isEmpty {
            let (s, hc) = makeScrollPane(radarViews)
            radarScroll = s; radarHeightC = hc
            radarPane = s
        }

        // The INBOUND lane (WP 2026-07-09-001): the standing "at your door" queue —
        // issues/PRs OTHERS opened on repos the user owns, waiting-longest first (a
        // triage queue, not a feed; a new arrival's announcement is the radar's event
        // row). Bot/draft items hold back to a quiet caption (default-off reveal via
        // the gear), the same demotion doctrine as the pulse's stale/drafts split.
        var inboundRowViews: [NSView] = inboundSections.active.map { inboundRowView($0) }
        // Held-back (bot/draft) arrivals: a default-off subsection. Collapsed → the plain-words
        // caption button (full-lane click target, flips `showHeldBackInbound`); revealed → a
        // header that gains a right-edge (hide) control folding it back (the two-way handle the
        // gear alone used to be). The header renders only WITH its rows — never a lone control.
        if showHeldBackInbound {
            if !inboundSections.heldBack.isEmpty {
                inboundRowViews.append(revealedHeader(PlainWords.heldBackHeader, onHide: onToggleHeldBackInbound))
            }
            inboundRowViews += inboundSections.heldBack.map { inboundRowView($0) }
        } else if !inboundSections.heldBack.isEmpty {
            inboundRowViews.append(captionButton(
                text: PlainWords.heldBackCaption(inboundSections.heldBack.count),
                spoken: PlainWords.heldBackCaptionSpoken(inboundSections.heldBack.count),
                onClick: onToggleHeldBackInbound))
        }
        let inboundLabel: NSView? = inboundRowViews.isEmpty ? nil : sectionHeader("Inbound")
        inboundLabel?.setContentHuggingPriority(.required, for: .vertical)
        if !inboundRowViews.isEmpty {
            let (s, hc) = makeScrollPane(inboundRowViews)
            inboundScroll = s; inboundHeightC = hc
        }

        // H2 — the ambient pulse lane: "how's my work doing?" The state of your open PRs
        // (CI · review · merge). Two facts pull PRs OUT of the live glance into default-off
        // subsections, so a rotting or WIP PR never crowds it: `isStale` (untouched 14d+ —
        // the rotting backlog) and `isDraft` ("ignore me, WIP"). The just-raised ones lead
        // the live list (the presenter floats them up — by position, not by chrome).
        // The live/stale/drafts split comes from the ONE presenter home of the live-work
        // rule (WP-6a dedupe) — the same `PulseSections` the collapsed pill + its spoken
        // a11y value consume, so the three surfaces can never drift apart.
        let sections = PulsePresenter.sections(for: pulse)
        // OWNER LENS (WP 2026-07-14-001): the active region renders through the lens
        // layout — titled owner groups (grouped shape), the one flat run (flat shape), and
        // folded owners compressed to counted ledger lines that sink to the region's foot.
        // Fold, not filter: a ledger line always prints its count (RUBRIC #11). Under a
        // title, rows elide the owner prefix (the title said it); in the flat run, A's
        // quiet typography applies once the login is known — the viewer's own prefix
        // elides, a foreign org's token gets one ink step (position + ink, no chrome).
        // PER-ORG TAILS (WP 2026-07-26-001 for drafts, 2026-07-29-001 for quiet): the lens takes
        // all three regions, so a group ends with its own WIP and then its own rotting backlog
        // instead of the lane ending with everyone's.
        //
        // THE TWO PREFS GATE AT DIFFERENT LAYERS, and that is the load-bearing asymmetry. The
        // `showDrafts` gate is HERE, on the lens's input: hidden drafts leave no caption behind, so
        // hidden and absent mean the same thing and `[]` is honest. `showStale` gates BELOW, at
        // render: quiet's whole grammar is that it leaves a count behind, so gating its input would
        // take a quiet-only owner's count off screen with its rows. See `lensRegions`.
        let lensDrafts = sections.lensRegions(showDrafts: showDrafts).drafts
        let lensLayout = PulsePresenter.lensLayout(live: sections.active, drafts: lensDrafts,
                                                   quiet: sections.stale, prefs: lensPreferences,
                                                   selfLogin: selfLogin, lastOpened: lensLastOpened)
        // Grouped shape tails its groups; flat shape keeps both terminal regions. Both sets come
        // from `LensLayout` so the key walk cannot disagree with the render — and so neither can
        // be rendered while the other is silently forgotten.
        let terminalDrafts = lensLayout.terminalDrafts
        let terminalQuiet = lensLayout.terminalQuiet
        var pulseRowViews: [NSView] = []
        for entry in lensLayout.entries {
            switch entry {
            case .rows(let lensRows):
                pulseRowViews += lensRows.map { row in
                    let owner = PulsePresenter.owner(of: row)
                    guard let selfLogin else { return pulseRowView(row) }
                    return owner.lowercased() == selfLogin.lowercased()
                        ? pulseRowView(row, elideOwner: true)
                        : pulseRowView(row, emphasizeOwner: owner)
                }
            case .group(_, let title, let groupRows, let drafts, let quiet):
                pulseRowViews.append(ownerSubHeader(title))
                pulseRowViews += groupRows.map { pulseRowView($0, elideOwner: true) }
                // The tails: subordinate, never peers, drafts then quiet (descending relevance,
                // ratified). Their rows elide the owner the group title already said, and the ink
                // demotion is derived inside PulseRowView from the row's own facts — nothing to
                // pass, nothing to forget.
                //
                // The CHROME differs per tail, which is why these are two branches and not a loop:
                // drafts wear a bare count label (the ratified no-caption asymmetry keeps their
                // hide control in the gear), while quiet's collapsed caption IS its affordance.
                if !drafts.isEmpty {
                    pulseRowViews.append(tailLabel(PlainWords.draftTailLabel(drafts.count)))
                    pulseRowViews += drafts.map { pulseRowView($0, elideOwner: true) }
                }
                if !quiet.isEmpty {
                    // ONE OBJECT, TWO STATES. The quiet tail is the ratified caption scoped to this
                    // org, and revealing it flips the verb rather than swapping the control for a
                    // different kind of thing: "2 gone quiet (show)" ⇄ "2 gone quiet (hide)".
                    //
                    // ONE LANE-WIDE PREF — any group's verb toggles every group's quiet, exactly as
                    // the gear does. Per-owner reveal state is a named non-goal: a second persisted
                    // set nobody asked for.
                    pulseRowViews.append(captionButton(
                        text: showStale ? PlainWords.staleRevealedCaption(quiet.count)
                                        : PlainWords.staleCaption(quiet.count),
                        spoken: showStale ? PlainWords.staleRevealedCaptionSpoken(quiet.count)
                                          : PlainWords.staleCaptionSpoken(quiet.count),
                        verb: showStale ? PlainWords.hideControl : PlainWords.showVerb,
                        indent: Self.tailIndent,
                        onClick: onToggleStale))
                    if showStale { pulseRowViews += quiet.map { pulseRowView($0, elideOwner: true) } }
                }
            case .ledger(let owner, let title, let count, let draftCount, let quietCount, let fresh):
                pulseRowViews.append(lensLedgerLine(owner: owner, title: title, count: count,
                                                    draftCount: draftCount, quietCount: quietCount,
                                                    fresh: fresh))
            }
        }
        // ── The terminal regions: FLAT SHAPE ONLY ────────────────────────────────────────────
        // When the lane wears owner titles each group carries its own tails, and a terminal region
        // would be a second, contradictory home for the same rows. Both sets are empty in grouped
        // shape by `LensLayout`'s post-condition, and fold-filtered in flat shape so a folded
        // owner's WIP and backlog hide with the rest of its work.
        //
        // ORDER: drafts, then quiet — matching the ratified per-group tail order. Before V3 quiet
        // sat above drafts, inherited from `PulseSections`' field order rather than chosen, so the
        // flat lane and a grouped lane disagreed about which tail came first. One mental model.
        //
        // Drafts (WIP PRs): a default-off subsection of the revealed-header family (WP
        // 2026-07-12-001 addendum) — the plain-words "Draft PRs" header with a right-edge (hide)
        // flipping the same `showDrafts` pref the gear flips. PRESERVED ASYMMETRY: no collapsed
        // caption; hidden drafts stay fully invisible. The header renders only WITH its rows (the
        // lone-header guard — a hide control over zero rows is a dangling affordance).
        if showDrafts, !terminalDrafts.isEmpty {
            pulseRowViews.append(revealedHeader(PlainWords.draftsHeader, onHide: onToggleDrafts))
            pulseRowViews += terminalDrafts.map { pulseRowView($0) }
        }
        // Quiet: collapsed by default to ONE count line — honest (you see it's there + why) without
        // a 4-month-old conflicted PR dominating the glance. Reveal via the caption button or
        // gear → "Show PRs gone quiet" (both flip the one `showStale` pref).
        if showStale {
            if !terminalQuiet.isEmpty {
                pulseRowViews.append(revealedHeader(PlainWords.staleHeader, onHide: onToggleStale))
                pulseRowViews += terminalQuiet.map { pulseRowView($0) }
            }
        } else if !terminalQuiet.isEmpty {
            pulseRowViews.append(captionButton(
                text: PlainWords.staleCaption(terminalQuiet.count),
                spoken: PlainWords.staleCaptionSpoken(terminalQuiet.count),
                onClick: onToggleStale))
        }
        // "Your PRs" label is PINNED above its pane (so it stays put while the PRs scroll).
        // With ≥2 owners present (or anything folded) it carries the lens EYE on its right
        // edge — hover-revealed within the header band (chrome only when it carries a
        // control someone might reach for; the single-owner lane never grows one).
        // The eye's owner set spans ALL THREE regions the lens governs, derived from the SAME
        // partition the lane and the card use — so "which owners exist" cannot drift between
        // the eye and the card behind it (it used to be a hand-rolled Set here). A quiet-only
        // owner joins with no edit beyond the third argument, which is the extraction paying off.
        //
        // SCOPE, honestly: with `showDrafts` off the lens gets no drafts (gated lane-wide), so a
        // folded draft-only owner leaves this set and the eye stops counting it while the card
        // still lists it unchecked via the folded-remnant rule. Correct — the owner genuinely has
        // nothing in the lane — but its fold is then reachable only through the gear. Recorded in
        // the WP plan's open questions. `showStale` has no such effect: quiet is never gated here,
        // so a quiet-only owner is in this set whether or not its rows are on screen.
        let presentOwners = Set(PulsePresenter.ownerBuckets(live: sections.active,
                                                            drafts: lensDrafts,
                                                            quiet: sections.stale)
                                    .map(\.key))
        let foldedPresentCount = presentOwners.filter { lensPreferences.isFolded($0) }.count
        let lensFolding = lensLayout.entries.contains { if case .ledger = $0 { return true }; return false }
        let wantsEye = presentOwners.count >= 2 || foldedPresentCount > 0
        let pulseLabel: NSView?
        if pulse.isEmpty {
            pulseLabel = nil
        } else if wantsEye {
            let eye = IconButton(symbol: lensFolding ? "eye.slash" : "eye",
                                 tooltip: PlainWords.lensEyeLabel(foldedCount: foldedPresentCount),
                                 tint: theme.inkTertiary, hover: theme.hoverFill) { [weak self] in
                self?.onOpenLensCard?()
            }
            pulseLabel = LensEyeHeaderView(title: sectionHeader("Your PRs"), eye: eye)
        } else {
            pulseLabel = sectionHeader("Your PRs")
        }
        pulseLabel?.setContentHuggingPriority(.required, for: .vertical)
        if !pulse.isEmpty {
            let (s, hc) = makeScrollPane(pulseRowViews)
            pulseScroll = s; pulseHeightC = hc
        }

        // The middle: radar pane, then the "Your PRs" label, then the pulse pane — each lane
        // sized to its content (reactive), capped + scrollable when busy. Fully caught up →
        // the affirmation BLOCK leads instead of the (absent) radar pane; any default-off
        // pulse subsections (the stale caption, opted-in stale/draft rows) still render
        // below it — real content, not filler (the per-lane placeholder stays banned).
        var middle: [NSView] = []
        var affirmation: NSView?
        if case .block(let line1, let line2) = caughtUp {
            let block = affirmationBlock(line1: line1, line2: line2)
            affirmation = block
            middle.append(block)
        }
        if let radarPane { middle.append(radarPane) }
        if let inboundLabel { middle.append(inboundLabel) }
        if let inboundScroll { middle.append(inboundScroll) }
        if let pulseLabel { middle.append(pulseLabel) }
        if let pulseScroll { middle.append(pulseScroll) }
        let body = NSStackView(views: middle)
        body.orientation = .vertical
        body.alignment = .leading
        body.distribution = .fill
        body.spacing = 8
        body.translatesAutoresizingMaskIntoConstraints = false
        // The eyed lane header must span the lane (the eye rides the RIGHT edge; a
        // leading-aligned stack would otherwise hug it beside the title).
        if let pulseLabel, pulseLabel is LensEyeHeaderView {
            pulseLabel.widthAnchor.constraint(equalTo: body.widthAnchor).isActive = true
        }
        bodyStack = body

        // The trust audit, in-product (consult 004): one click to the full inbox to check
        // for a MISS (false negative) among what githud hid. PINNED at the bottom edge.
        let footer = InboxLinkView(theme: theme)
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerView = footer

        addSubview(header)
        addSubview(body)
        addSubview(footer)
        var cons: [NSLayoutConstraint] = [
            header.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),

            body.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            body.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            body.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            body.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            footer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16),
        ]
        // Panes span the full body width (no horizontal scroll, rows align with the header).
        for pane in [radarScroll, inboundScroll, pulseScroll].compactMap({ $0 }) {
            cons.append(pane.widthAnchor.constraint(equalTo: body.widthAnchor))
        }
        // The affirmation block spans the full body width too, so its text CENTERS on the
        // island (the leading-aligned body stack would otherwise hug it left).
        if let affirmation {
            cons.append(affirmation.widthAnchor.constraint(equalTo: body.widthAnchor))
        }
        NSLayoutConstraint.activate(cons)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The island's REACTIVE height — it sizes to its content (header + lanes + footer), so a
    /// short lane leaves no dead space. Each lane is set to min(its content, `perPaneMaxHeight`):
    /// under the cap it shows every row; over it, the lane scrolls (rows stay full height — the
    /// documentView keeps its intrinsic size, only the scroll FRAME is capped). Controller clamps
    /// the total to the screen.
    func fittingHeight() -> CGFloat {
        let w = widthAnchor.constraint(equalToConstant: IslandContentView.width)
        w.isActive = true
        layoutSubtreeIfNeeded()
        for (scroll, hc) in [(radarScroll, radarHeightC), (inboundScroll, inboundHeightC),
                             (pulseScroll, pulseHeightC)] {
            guard let scroll, let hc, let doc = scroll.documentView else { continue }
            let content = ceil(doc.fittingSize.height)
            // Under the cap: show every row. Over it: snap DOWN to the last WHOLE row that fits,
            // so the lane never rests on a half-cut row — the overflow scrolls into view.
            hc.constant = content <= IslandGeometry.perPaneMaxHeight
                ? content
                : wholeRowsHeight(in: doc, cap: IslandGeometry.perPaneMaxHeight)
            // WP-3d capped-lane bottom fade: only a lane whose content exceeds its snapped
            // frame wears the "more below this edge" gradient (ratified scope bleed —
            // decided once, on purpose, in the D-morph record).
            scroll.setBottomFade(active: content > hc.constant + 0.5)
        }
        layoutSubtreeIfNeeded()
        let h = ceil(fittingSize.height)
        w.isActive = false   // measurement only — present() drives the real frame
        return h
    }

    /// Per-lane scroll offsets — the flipped clip view's `bounds.origin.y` (0 = top). Captured
    /// from the OUTGOING island before a rebuild so a data-driven refresh doesn't yank the read.
    struct ScrollOffsets { var radar: CGFloat; var pulse: CGFloat; var inbound: CGFloat = 0 }

    func scrollOffsets() -> ScrollOffsets {
        ScrollOffsets(radar: radarScroll?.contentView.bounds.origin.y ?? 0,
                      pulse: pulseScroll?.contentView.bounds.origin.y ?? 0,
                      inbound: inboundScroll?.contentView.bounds.origin.y ?? 0)
    }

    /// Restore captured offsets into the REBUILT panes (call after the island is framed + laid
    /// out). Each is clamped to the new content height — a shorter rebuilt lane can't scroll past
    /// its end, and the pane frame itself is already whole-row-snapped by `fittingHeight()`, so
    /// the restored position rests within a snapped frame (never below a half-cut row).
    func applyScrollOffsets(_ offsets: ScrollOffsets) {
        restore(radarScroll, to: offsets.radar)
        restore(pulseScroll, to: offsets.pulse)
        restore(inboundScroll, to: offsets.inbound)
    }

    private func restore(_ scroll: CappedLaneScrollView?, to y: CGFloat) {
        guard let scroll, y > 0, let doc = scroll.documentView else { return }
        scroll.layoutSubtreeIfNeeded()
        let maxY = max(0, doc.frame.height - scroll.contentView.bounds.height)
        let clamped = min(y, maxY)
        guard clamped > 0 else { return }
        // Restore through the lane's non-animating path — this is the reader's own prior
        // position replayed across a data rebuild, not a live scroll, so the bottom fade must
        // not animate for it (the double-pulse the review flagged).
        scroll.restoreScrollOffset {
            scroll.contentView.scroll(to: NSPoint(x: 0, y: clamped))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }

    // MARK: - WP-3d′ peeks (the ScrollOffsets contract, for un-truncated rows)

    /// The current peek set — captured by the controller from the OUTGOING island before a
    /// data rebuild (exactly like `scrollOffsets()`) and fed into the next island's init,
    /// where each row restores open iff its stable id AND change signature still match.
    /// Reset-on-collapse is structural: a collapsed render never carries the stash forward.
    func peekStash() -> PeekStash { peeks }

    /// One radar row, peek-wired: restored open from the stash (0ms — replayed state, not
    /// motion), and reporting toggles back into the stash + up to the controller (which
    /// eases the island height on the WP-3d machinery).
    private func radarRowView(_ row: RadarRow) -> RadarRowView {
        let view = RadarRowView(row: row, theme: theme,
                                peeked: peeks.isOpen(id: row.id, signature: row.changeSignature),
                                onPeekToggle: { [weak self] open in
                                    self?.peeks.setOpen(open, id: row.id, signature: row.changeSignature)
                                    self?.onPeekChange?()
                                })
        keyRows[row.id] = view   // WP-6k: actionable → reachable by the ink bar
        return view
    }

    /// One pulse row, peek-wired — same contract as `radarRowView`. Owner-lens ink
    /// (WP 2026-07-14-001): `elideOwner` drops the owner prefix (rows under an owner
    /// title, or the viewer's own rows in the flat run); `emphasizeOwner` gives a foreign
    /// org's token one ink step in the flat run. VoiceOver always speaks the full
    /// owner/repo either way (elision and emphasis are visual only).
    private func pulseRowView(_ row: PulseRow, elideOwner: Bool = false,
                              emphasizeOwner: String? = nil) -> PulseRowView {
        let view = PulseRowView(row: row, theme: theme,
                                peeked: peeks.isOpen(id: row.id, signature: row.changeSignature),
                                elideOwner: elideOwner, emphasizeOwner: emphasizeOwner,
                                onPeekToggle: { [weak self] open in
                                    self?.peeks.setOpen(open, id: row.id, signature: row.changeSignature)
                                    self?.onPeekChange?()
                                })
        keyRows[row.id] = view   // WP-6k: actionable → reachable by the ink bar
        return view
    }

    /// One inbound row, peek-wired — same contract as `pulseRowView`.
    private func inboundRowView(_ row: InboundRow) -> InboundRowView {
        let view = InboundRowView(row: row, theme: theme,
                                  peeked: peeks.isOpen(id: row.id, signature: row.changeSignature),
                                  onPeekToggle: { [weak self] open in
                                      self?.peeks.setOpen(open, id: row.id, signature: row.changeSignature)
                                      self?.onPeekChange?()
                                  })
        keyRows[row.id] = view   // WP-6k: actionable → reachable by the ink bar
        return view
    }

    // MARK: - WP-6k key session (bar + hint EXECUTION; decisions live in GithudCore.KeySession)

    /// Show/hide the session-only hint on the existing footer line ("↑↓ move · ⏎ open ·
    /// esc dismiss", right-aligned) — visible ONLY while the ⌃⌥G session is live, so the
    /// mouse-path island never wears keyboard chrome (the provable F8 boundary).
    func setKeySessionHint(_ visible: Bool) {
        (footerView as? InboxLinkView)?.setHintVisible(visible)
    }

    /// Move the ink bar to `id` (nil retires it). 0ms — the bar is a steered cursor, not
    /// motion. The focused row is scrolled fully visible (whole-row, unanimated —
    /// `scrollToVisible` is minimal-scroll, so under the lane cap the lane walks row by
    /// row), and VoiceOver is told the focus moved (the panel's
    /// `accessibilityFocusedUIElement` mirror answers with this same row).
    func setKeyFocus(id: String?) {
        if let old = keyFocusedID, old != id { keyRows[old]?.setKeyFocused(false) }
        keyFocusedID = id
        guard let id, let row = keyRows[id] else { return }
        row.setKeyFocused(true)
        row.scrollToVisible(row.bounds)
        NSAccessibility.post(element: row, notification: .focusedUIElementChanged)
    }

    /// The view wearing the bar — the panel's AX-focus mirror reads this.
    func keyFocusedRowView() -> NSView? { keyFocusedID.flatMap { keyRows[$0] } }

    /// ⏎ — the focused row's own Open-on-GitHub path (nil-url guard included).
    @discardableResult func openKeyFocusedRow() -> Bool {
        guard let id = keyFocusedID, let row = keyRows[id] else { return false }
        return row.performOpen()
    }

    /// Space — the focused row's own chevron toggle (no-op without a chevron).
    @discardableResult func togglePeekOnKeyFocusedRow() -> Bool {
        guard let id = keyFocusedID, let row = keyRows[id] else { return false }
        return row.performPeekToggle()
    }

    /// The height of the largest run of WHOLE rows (top-down) that fits within `cap` — so a
    /// capped lane rests on a row boundary, never a half-cut row. Falls back to `cap` if even
    /// the first row is taller than the cap (then it shows that single row, partially).
    private func wholeRowsHeight(in doc: NSView, cap: CGFloat) -> CGFloat {
        guard let stack = doc as? NSStackView else { return cap }
        var bottom: CGFloat = 0, lastWhole: CGFloat = 0
        for (i, row) in stack.arrangedSubviews.enumerated() {
            let rowH = row.frame.height > 1 ? row.frame.height : ceil(row.fittingSize.height)
            let rowBottom = bottom + (i > 0 ? stack.spacing : 0) + rowH
            if rowBottom > cap { break }
            bottom = rowBottom; lastWhole = rowBottom
        }
        return lastWhole > 0 ? lastWhole : cap
    }

    /// One scrollable lane: a flipped document stack of rows inside an overlay-scroller scroll
    /// view that SIZES TO ITS CONTENT (so the island stays reactive — no dead space) up to
    /// `perPaneMaxHeight`, beyond which it caps and scrolls its overflow in place. Returns the
    /// scroll plus its height constraint (fittingHeight() sets the constant to min(content, cap)).
    private func makeScrollPane(_ rowViews: [NSView]) -> (CappedLaneScrollView, NSLayoutConstraint) {
        let doc = FlippedStack(views: rowViews)   // flipped → opens at the TOP, not the bottom
        doc.orientation = .vertical
        doc.alignment = .leading
        doc.spacing = 8
        doc.translatesAutoresizingMaskIntoConstraints = false

        let scroll = CappedLaneScrollView()
        scroll.drawsBackground = false
        // No scroller knob at all (dogfood 2026-07-14: the overlay knob read as oversized
        // chrome on the glass). Scroll-wheel/trackpad scrolling is unaffected; the lane's
        // overflow gradient mask is the "there's more" affordance — ink, not chrome.
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.scrollerStyle = .overlay
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = doc
        scroll.translatesAutoresizingMaskIntoConstraints = false
        // Every lane child spans the FULL lane width (the panes' own pin, one level down —
        // the leading-aligned doc stack would otherwise let a row hug its fitting width).
        // Without this, a peeked row's wrapped labels shrink to their longest laid-out LINE,
        // and the whole row narrows with them: the trailing chevron slides off the lane edge
        // to a per-row X (the dogfood chevron-drift bug), and the row's hover fill + hit
        // band stop where the text happens to end — a click still visually "in the row"
        // falls through to nothing.
        NSLayoutConstraint.activate(rowViews.map { $0.widthAnchor.constraint(equalTo: doc.widthAnchor) })
        // Explicit height, set in fittingHeight() to min(content, cap): the documentView keeps
        // its full intrinsic height (rows never compress — they stay full, with their subtitle)
        // and SCROLLS inside this capped frame. Starts at the cap; fittingHeight() shrinks it
        // to the actual content so a short lane leaves no dead space.
        let heightC = scroll.heightAnchor.constraint(equalToConstant: IslandGeometry.perPaneMaxHeight)
        NSLayoutConstraint.activate([
            doc.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            doc.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            doc.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),   // no horizontal scroll
            heightC,
        ])
        return (scroll, heightC)
    }

    // MARK: - pieces

    /// A caution line shown ONLY when the reading is degraded (poll stalled/failing) — a
    /// clock-with-warning + "Updated Nm ago" / "Reconnecting …", in the theme's `caution`.
    /// `nil` (no view) when fresh, so the normal island carries no freshness chrome.
    private func freshnessBanner(_ freshness: Freshness) -> NSView? {
        guard let text = FreshnessModel.label(for: freshness) else { return nil }
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "clock.badge.exclamationmark", accessibilityDescription: "reading may be stale")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        icon.contentTintColor = theme.caution
        icon.setContentHuggingPriority(.required, for: .horizontal)
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = theme.caution
        let stack = NSStackView(views: [icon, label])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        stack.setAccessibilityElement(true)
        stack.setAccessibilityLabel(text)
        return stack
    }

    /// The centered caught-up affirmation (D-copy `voice-plainspoken` as amended): fresh =
    /// two lines ("You're all caught up" 13px/500 inkPrimary · "Nothing needs you right now"
    /// 11px inkSecondary); degraded = the ONE as-of line (`line2 == nil`) beside the caution
    /// banner. Ink only, 0ms motion of its own — it appears with the island rebuild the
    /// user's expand caused. Strings decided in `GithudCore.CaughtUpPresenter` (tense-tested).
    private func affirmationBlock(line1: String, line2: String?) -> NSView {
        let first = NSTextField(labelWithString: line1)
        first.font = .systemFont(ofSize: 13, weight: .medium)
        first.textColor = theme.inkPrimary
        var lines: [NSView] = [first]
        if let line2 {
            let second = NSTextField(labelWithString: line2)
            second.font = .systemFont(ofSize: 11)
            second.textColor = theme.inkSecondary
            lines.append(second)
        }
        let stack = NSStackView(views: lines)
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false

        let block = NSView()
        block.translatesAutoresizingMaskIntoConstraints = false
        block.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: block.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: block.bottomAnchor, constant: -18),
            stack.centerXAnchor.constraint(equalTo: block.centerXAnchor),
        ])
        block.setAccessibilityElement(true)
        block.setAccessibilityRole(.staticText)
        block.setAccessibilityLabel(line2.map { "\(line1). \($0)" } ?? line1)
        return block
    }

    private func makeHeader(count: Int, caughtUpPhrase: String? = nil) -> NSView {
        // Radar empty: the slot carries the caught-up phrase when the presenter granted one
        // (live PRs below, confirmed first poll) — otherwise the bare wordmark, exactly as
        // before a confirmed poll or beside the full affirmation block (one treatment only).
        let title = NSTextField(labelWithString: count == 0 ? (caughtUpPhrase ?? "githud") : "Needs you")
        title.font = .systemFont(ofSize: 11, weight: .semibold)
        title.textColor = theme.inkSecondary

        var views: [NSView] = [title]
        if count > 0 {
            let badge = countBadge(count)
            badge.setContentHuggingPriority(.required, for: .horizontal)
            views.append(badge)
        }
        // a flexible trailing spacer pushes the gear to the right edge
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        views.append(spacer)

        if onGearTap != nil {
            // The gear opens the SETTINGS CARD (mark-and-settings option B, dogfood-
            // ratified 2026-07-14) — the tooltip says exactly that, no more menu listing.
            let gear = IconButton(symbol: "slider.horizontal.3",
                                  tooltip: PlainWords.settingsGearTooltip,
                                  tint: theme.inkSecondary, hover: theme.hoverFill) { [weak self] in
                if let gear = self?.gearButton { self?.onGearTap?(gear) }
            }
            gear.setContentHuggingPriority(.required, for: .horizontal)
            gearButton = gear
            views.append(gear)
        }

        if onCollapse != nil {
            let collapse = IconButton(symbol: "chevron.up", tooltip: "Collapse", tint: theme.inkSecondary,
                                      hover: theme.hoverFill) { [weak self] in self?.onCollapse?() }
            collapse.setContentHuggingPriority(.required, for: .horizontal)
            views.append(collapse)
        }

        let stack = NSStackView(views: views)
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    private func countBadge(_ count: Int) -> NSView {
        let label = NSTextField(labelWithString: "\(count)")
        label.font = .monospacedDigitSystemFont(ofSize: 11, weight: .bold)   // steady digit advance
        label.textColor = theme.badgeInk
        label.translatesAutoresizingMaskIntoConstraints = false

        let badge = NSView()
        badge.wantsLayer = true
        badge.layer?.backgroundColor = theme.accent.cgColor
        badge.layer?.cornerRadius = 8
        badge.layer?.cornerCurve = .continuous
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.addSubview(label)
        NSLayoutConstraint.activate([
            badge.heightAnchor.constraint(equalToConstant: 16),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 18),
            // Pin the capsule tightly around the number so its width is the number's
            // width + padding (an NSView has no intrinsic size to hug otherwise).
            label.leadingAnchor.constraint(equalTo: badge.leadingAnchor, constant: 7),
            label.trailingAnchor.constraint(equalTo: badge.trailingAnchor, constant: -7),
            label.centerYAnchor.constraint(equalTo: badge.centerYAnchor),
        ])
        return badge
    }

    /// The plain-words caption for a collapsed default-off subsection (WP 2026-07-12-001):
    /// a full-lane-width button (the island-row click convention) whose click flips the
    /// SAME preference the gear item flips. Plain 11px tertiary ink; the trailing "(show)"
    /// verb is underlined (the LedgerCardView styled-substring precedent) as its only
    /// affordance. `spoken` is the VoiceOver button label ("N gone quiet, show").
    /// `verb` is the token the view underlines as the affordance. It defaults to `(show)` because
    /// every lane-level caption is a collapsed one; a group's quiet tail passes `(hide)` when it is
    /// already revealed, so the same object carries either state (G1).
    private func captionButton(text: String, spoken: String, verb: String = PlainWords.showVerb,
                               indent: CGFloat = 0, onClick: (() -> Void)?) -> NSView {
        CaptionButtonView(text: text, verb: verb, spoken: spoken,
                          theme: theme, indent: indent, onClick: onClick)
    }

    /// A revealed subsection's header: the plain-words title on the left, an underlined
    /// (hide) control pinned to the lane's right edge that flips the same preference back
    /// off (WP 2026-07-12-001). The header label matches `sectionHeader`'s weight/ink.
    private func revealedHeader(_ title: String, onHide: (() -> Void)?) -> NSView {
        let label = sectionHeader(title)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let hide = HideControlView(theme: theme, onHide: onHide)
        hide.setContentHuggingPriority(.required, for: .horizontal)
        let stack = NSStackView(views: [label, spacer, hide])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        return stack
    }

    /// A lane/section header — same weight as the "Needs you" title, to delineate the
    /// H2 "Your PRs" lane from the H1 radar above it.
    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = theme.inkSecondary
        return label
    }

    /// An owner group's title inside the "Your PRs" lane (owner lens, grouped shape):
    /// same size/weight as a section header, one ink step quieter — a sub-structure
    /// inside the lane, not a rival lane. Pure text: the eye lives on the LANE header
    /// (ratified round 6), never on the titles.
    private func ownerSubHeader(_ title: String) -> NSTextField {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = theme.inkTertiary
        return label
    }

    /// A group's tail label (WP 2026-07-26-001; second tail added 2026-07-29-001) — "5 drafts" or
    /// "2 gone quiet", one ink step below the owner title that already named the org. It must read
    /// as SUBORDINATE, not as a rival sub-header: lighter weight, smaller, and no control on it.
    /// Position carries the rest — a tail always follows its group's live rows, never mixes.
    ///
    /// ONE HELPER FOR BOTH TAILS. What differs between them is not the label — it is whether a
    /// COLLAPSED form exists: drafts have none (the ratified no-caption asymmetry keeps the hide
    /// affordance in the gear), quiet collapses to `staleCaption`. That difference lives at the
    /// call site, where the pref is read; two near-identical label builders would be the same
    /// typography rule stated twice and drifting on the next respec.
    /// How far a tail's own ink sits inside the lane's left margin. Shared by the tail LABEL and
    /// a group's collapsed quiet CAPTION: at the margin the caption read as a lane-level section
    /// wedged between two owner groups rather than as that owner's tail — the exact mistake the
    /// label's indent was written to fix, so the number has one home (dogfood capture, U3).
    static let tailIndent: CGFloat = 14

    private func tailLabel(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = theme.inkTertiary
        label.alphaValue = 0.75
        label.translatesAutoresizingMaskIntoConstraints = false
        // INDENTED under its group. At the lane's left margin it read as a sibling of the
        // owner title — a rival section rather than that owner's tail. The indent is the
        // subordination cue the ratified mock carried (with the dimmed rows below it); the
        // wrapper spans the lane so the enclosing full-width pin still applies.
        let wrap = NSView()
        wrap.translatesAutoresizingMaskIntoConstraints = false
        wrap.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: wrap.leadingAnchor,
                                          constant: Self.tailIndent),
            label.topAnchor.constraint(equalTo: wrap.topAnchor),
            label.bottomAnchor.constraint(equalTo: wrap.bottomAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: wrap.trailingAnchor),
        ])
        return wrap
    }

    /// A folded owner's ledger line (owner lens): title + count (+ fresh) — the honesty
    /// ink a fold always leaves behind. Whole line = click target; an OWNER line's click
    /// unfolds that owner (reveal is forgiving); the merged "elsewhere" line opens the
    /// lens card instead (one owner can't be inferred from a merged line).
    private func lensLedgerLine(owner: String?, title: String, count: Int,
                                draftCount: Int, quietCount: Int, fresh: Int) -> NSView {
        let fold = onToggleFoldedOwner
        let card = onOpenLensCard
        let onClick: (() -> Void)? = owner.map { o in { fold?(o) } } ?? { card?() }
        let spoken = owner == nil
            ? PlainWords.lensElsewhereLedgerSpoken(count: count, draftCount: draftCount,
                                                   quietCount: quietCount, fresh: fresh)
            : PlainWords.lensLedgerSpoken(title, count: count, draftCount: draftCount,
                                          quietCount: quietCount, fresh: fresh)
        return LensLedgerLineView(text: PlainWords.lensLedger(title, count: count,
                                                              draftCount: draftCount,
                                                              quietCount: quietCount, fresh: fresh),
                                  fresh: fresh, spoken: spoken, theme: theme, onClick: onClick)
    }

}

/// The plain-words caption rendered as a button (WP 2026-07-12-001): the whole line is
/// the click target (full lane width, `theme.hoverFill`, pointing-hand — the island-row
/// convention), and a click flips the SAME preference the gear item flips. Doctrine: ink,
/// not chrome — 11px tertiary, the only added affordance is the underlined "(show)" verb
/// (styled-substring, the LedgerCardView precedent). VoiceOver: a button, spoken with the
/// verb as a word ("3 gone quiet, show"). Not a ⌃⌥G key-session stop (out of scope, recorded).
final class CaptionButtonView: IslandClickableView {
    private let onClick: (() -> Void)?

    /// `indent` subordinates the caption under an owner title (WP 2026-07-29-001) — the ink
    /// moves, the CLICK TARGET does not: a full-lane hover band is the island-row convention,
    /// and narrowing it would make a group's quiet caption harder to hit than the lane's.
    init(text: String, verb: String, spoken: String, theme: Theme, indent: CGFloat = 0,
         onClick: (() -> Void)?) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill   // base handles highlight + pointing-hand cursor

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attr = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: theme.inkTertiary])
        // Underline ONLY the trailing verb token — the affordance, not the whole caption.
        if let r = text.range(of: verb, options: .backwards) {
            attr.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                              range: NSRange(r, in: text))
        }
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = attr
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        // ~5pt vertical padding INSIDE the full-width target → a comfortable hit band that
        // matches the rows' feel; leading flush with the lane (or indented under a group),
        // trailing free.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(spoken)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    @objc private func clicked() { onClick?() }
}

/// A revealed subsection header's right-edge fold-back control (WP 2026-07-12-001): the
/// underlined "(hide)" verb, a small clickable target that flips the same preference back
/// off. VoiceOver: a button spoken "hide".
final class HideControlView: IslandClickableView {
    private let onHide: (() -> Void)?

    init(theme: Theme, onHide: (() -> Void)?) {
        self.onHide = onHide
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill

        let attr = NSMutableAttributedString(
            string: PlainWords.hideControl,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: theme.inkTertiary,
                         .underlineStyle: NSUnderlineStyle.single.rawValue])
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = attr
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(PlainWords.hideSpoken)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformPress() -> Bool { onHide?(); return true }
    @objc private func clicked() { onHide?() }
}

/// A folded owner's ledger line (owner lens, WP 2026-07-14-001): "acme · 3, 1 new" —
/// the honesty ink a fold always leaves behind (fold, not filter; the count always
/// prints). Chassis mirrors `CaptionButtonView` (full-lane click target, hoverFill,
/// 11px tertiary, ~5pt hit band) but carries NO verb token — ratified round 5 removed
/// "(show)"; the whole line opens the group (reveal is forgiving), and the "N new"
/// clause gets one ink step so the Sunday answer reads without a click. VoiceOver: a
/// button ("acme, 3 folded, 1 new, open"). Not a ⌃⌥G key-session stop (structure,
/// not a row — the caption precedent).
final class LensLedgerLineView: IslandClickableView {
    private let onClick: (() -> Void)?

    init(text: String, fresh: Int, spoken: String, theme: Theme, onClick: (() -> Void)?) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill   // base handles highlight + pointing-hand cursor

        let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let attr = NSMutableAttributedString(
            string: text, attributes: [.font: font, .foregroundColor: theme.inkTertiary])
        // The fresh clause is the line's one emphasis — ink step, never a badge.
        if fresh > 0, let r = text.range(of: "\(fresh) new", options: .backwards) {
            attr.addAttribute(.foregroundColor, value: theme.inkSecondary,
                              range: NSRange(r, in: text))
        }
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = attr
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 5),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -5),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(spoken)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
    @objc private func clicked() { onClick?() }
}

/// The "Your PRs" lane header when the owner lens has something to govern (≥2 owners
/// present, or anything folded): the section title + the lens EYE on the lane's right
/// edge. The eye is HOVER-REVEALED within the header band via alpha — never `isHidden`,
/// so VoiceOver reaches the button at all times (chrome only when a pointer approaches;
/// the ledger lines carry the persistent honesty). 120ms opacity, instant under Reduce
/// Motion — the InkFade grammar, no new animation vocabulary.
final class LensEyeHeaderView: NSView {
    private let eye: IconButton

    init(title: NSTextField, eye: IconButton) {
        self.eye = eye
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        eye.alphaValue = 0
        title.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [title, spacer, eye])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private var hoverTracking: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // Swap only OUR area — the blanket remove also killed AppKit's tooltip
        // tracking (same fix as IslandClickableView, dogfood 2026-07-18).
        if let hoverTracking { removeTrackingArea(hoverTracking) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self, userInfo: nil)
        hoverTracking = area
        addTrackingArea(area)
    }

    private func setEyeVisible(_ visible: Bool) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            eye.alphaValue = visible ? 1 : 0
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            ctx.allowsImplicitAnimation = true
            eye.animator().alphaValue = visible ? 1 : 0
        }
    }

    override func mouseEntered(with event: NSEvent) { setEyeVisible(true) }
    override func mouseExited(with event: NSEvent) { setEyeVisible(false) }
}

/// A vertical stack that reports `isFlipped = true`, so as an `NSScrollView` document view
/// the scroll opens at the TOP and scrolls downward (a non-flipped document would open at
/// the bottom).
private final class FlippedStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// A capped lane wearing the ratified bottom-fade overflow affordance (WP-3d; the D-morph
/// record's scope bleed, decided knowingly): when the lane's content exceeds its snapped
/// frame, the last 24px dissolve under a gradient MASK — "more below this edge" printed as
/// ink, not chrome (a mask, so it works over vibrancy where no solid overlay color exists).
///
/// Contract (doctrine-audited):
/// - STATIC at rest — the mask just sits there; on expand it arrives with the body ink
///   (the lane fades in already masked — no separate chrome animation).
/// - It disappears over 120ms when the USER scrolls the lane to its end, and returns on
///   scroll-back — motion mapped 1:1 to the user's own scroll (attention-non-theft).
/// - The scroll listener is EVENT-DRIVEN — a clip-view bounds-change notification, never
///   a timer — and lives ONLY while this view does: the island content is torn down on
///   collapse, so nothing observes and nothing is masked at idle (idle-footprint paid).
/// - Reduce Motion: the toggle is instant.
final class CappedLaneScrollView: NSScrollView {
    static let fadeHeight: CGFloat = 24
    private var gradient: CAGradientLayer?
    private var boundsObserver: NSObjectProtocol?
    private var fadeShown = false
    /// The clip view's last-seen scroll ORIGIN. The fade animates ONLY when this moves (a real
    /// user scroll). `boundsDidChangeNotification` also fires on SIZE/layout changes (every poll
    /// rebuild re-frames an overflowing lane), which must re-apply the mask WITHOUT motion —
    /// else the band pulses on the poll clock, not the user's scroll (attention-non-theft).
    private var lastClipOrigin: CGPoint = .zero

    /// Called by `fittingHeight()` once per render, after the lane's frame is snapped:
    /// `active` == the content overflows the snapped frame.
    func setBottomFade(active: Bool) {
        guard active else {
            teardownFade()
            return
        }
        wantsLayer = true
        if gradient == nil {
            let g = CAGradientLayer()
            g.startPoint = CGPoint(x: 0.5, y: 0)
            g.endPoint = CGPoint(x: 0.5, y: 1)
            layer?.mask = g
            gradient = g
        }
        if boundsObserver == nil {
            // EVENT-DRIVEN scroll listener: fires only when the clip view's bounds actually
            // change — no polling, no timer (idle-footprint).
            contentView.postsBoundsChangedNotifications = true
            lastClipOrigin = contentView.bounds.origin
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification, object: contentView, queue: .main
            ) { [weak self] _ in
                guard let self else { return }
                // Animate ONLY on an ORIGIN change (a live scroll); a size-only bounds change
                // (a poll rebuild re-framing the lane) re-applies the mask state statically.
                let origin = self.contentView.bounds.origin
                let scrolled = abs(origin.y - self.lastClipOrigin.y) > 0.5
                self.lastClipOrigin = origin
                self.refreshFade(animated: scrolled)
                // Content just moved under a (possibly stationary) pointer: tracking
                // areas won't send enter/exit for rows sliding beneath it, so lingering
                // hover fills are re-evaluated here (dogfood 2026-07-14). Same event,
                // no new listener — idle-footprint unchanged.
                if scrolled { self.refreshRowHover() }
            }
        }
        layoutGradient()
        // The arriving state is computed AFTER final layout (in `layout()`) — fittingHeight()
        // runs pre-layout, so the clip/doc frames here aren't final yet.
    }

    /// Replay a stashed scroll offset from the outgoing island onto this rebuilt lane WITHOUT
    /// animating the fade: a restore is the user's own prior position, not a new scroll (motion
    /// maps to the LIVE scroll only). Adopting the restored origin synchronously means the
    /// bounds notification the scroll fires reads "no move" → static; the final mask state is
    /// settled here at the restored position.
    func restoreScrollOffset(_ scroll: () -> Void) {
        scroll()
        lastClipOrigin = contentView.bounds.origin
        refreshFade(animated: false)
    }

    /// Re-check every clickable row's hover fill against the pointer's real position
    /// after content moved beneath it (see the bounds observer above).
    private func refreshRowHover() {
        guard let stack = documentView as? NSStackView else { return }
        for row in stack.arrangedSubviews {
            (row as? IslandClickableView)?.refreshHover()
        }
    }

    private func teardownFade() {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
        boundsObserver = nil
        layer?.mask = nil
        gradient = nil
        fadeShown = false
    }

    deinit {
        if let boundsObserver { NotificationCenter.default.removeObserver(boundsObserver) }
    }

    override func layout() {
        super.layout()
        layoutGradient()
        // Arrival state at the REAL geometry: fittingHeight() sizes the lane pre-layout, so the
        // mask's resting state must settle here, after the clip/doc are finally framed — always
        // statically (a layout change is never a user scroll). A live scroll changes the clip
        // ORIGIN and posts a bounds change (animated there) but does NOT trigger layout(), so
        // this can't stomp a scroll animation. Idempotent (setFadeShown guards on a real flip).
        guard gradient != nil else { return }
        lastClipOrigin = contentView.bounds.origin
        refreshFade(animated: false)
    }

    /// Keep the mask covering the lane, with the fade band on the VISUAL bottom edge
    /// regardless of layer-geometry flipping (AppKit flips backing layers for flipped
    /// view hierarchies — resolve at runtime instead of guessing).
    private func layoutGradient() {
        guard let gradient, let layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)   // geometry bookkeeping — never animates
        gradient.frame = layer.bounds
        let h = max(layer.bounds.height, 1)
        let band = min(1, Self.fadeHeight / h)
        if layer.isGeometryFlipped {
            gradient.locations = [0, NSNumber(value: 1 - band), 1]   // unit y=1 renders at the bottom
        } else {
            gradient.locations = [0, NSNumber(value: band), 1]       // unit y=0 renders at the bottom
        }
        gradient.colors = maskColors(faded: fadeShown, flipped: layer.isGeometryFlipped)
        CATransaction.commit()
    }

    private func maskColors(faded: Bool, flipped: Bool) -> [CGColor] {
        let opaque = CGColor(gray: 0, alpha: 1)
        let edge = CGColor(gray: 0, alpha: faded ? 0 : 1)
        return flipped ? [opaque, opaque, edge] : [edge, opaque, opaque]
    }

    /// At the end of the lane the fade lifts (nothing is below the edge — claiming
    /// otherwise would fabricate content); scrolled back up, it returns. 120ms ease-out,
    /// driven only by the bounds-change event above. Reduce Motion → instant.
    private func refreshFade(animated: Bool) {
        guard let doc = documentView, gradient != nil else { return }
        let visible = contentView.bounds
        let atEnd = visible.origin.y + visible.height >= doc.frame.height - 1
        setFadeShown(!atEnd, animated: animated)
    }

    private func setFadeShown(_ shown: Bool, animated: Bool) {
        guard shown != fadeShown, let gradient, let layer else { return }
        fadeShown = shown
        let colors = maskColors(faded: shown, flipped: layer.isGeometryFlipped)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let fade = CABasicAnimation(keyPath: "colors")
            fade.fromValue = gradient.presentation()?.colors ?? gradient.colors
            fade.toValue = colors
            fade.duration = 0.12
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            gradient.add(fade, forKey: "fadeToggle")
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.colors = colors
        CATransaction.commit()
    }
}

// MessageView (the orange-triangle paragraph card) is RETIRED (WP-4d): every state it
// carried — no token, wrong shape, 401, SSO-403, Keychain write failure — now lives in
// the handshake-ledger card (`LedgerCardView` + `GithudCore.TokenLedger`), where errors
// land on the exact receipt row that failed. It had no other consumers. This also
// retires its pre-color-doctrine fixed systemOrange icon (the ledger spends `danger`
// only on the failing row — a genuine intervene).

/// A subtle clickable footer that opens the full GitHub inbox — so a user can audit
/// for a MISS (the existential metric) among what githud suppressed. Reveal, in-app.
/// WP-6k: also carries the session-only key hint on its right edge (the "existing
/// footer line" the ratified spec names) — hidden at rest, shown only while the ⌃⌥G
/// session is live. The base `hitTest` flattens the whole footer to one target, so
/// the hint is pure ink: clicks anywhere on the line stay the inbox link, exactly as
/// the full-width footer behaves today.
final class InboxLinkView: IslandClickableView {
    private let hintLabel: NSTextField

    init(theme: Theme) {
        // "↑↓ move · ⏎ open · esc dismiss" — 11px inkTertiary, right-aligned. One glyph
        // diverges from the ratified string: ⏎ where the spec wrote ↩ (same key, the
        // more conventional mark) — recorded in the agenda, not silent (drift NIT 3).
        hintLabel = NSTextField(labelWithString: "↑↓ move · ⏎ open · esc dismiss")
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill   // base handles highlight + pointing-hand cursor

        // WP 2026-07-12-001: the preamble is retired from print — "Check for yourself" was
        // the button explaining itself; the link keeps that audit-invitation job by existing.
        // The intent survives where it's SPOKEN: `setAccessibilityLabel("Audit the full
        // GitHub inbox")` below is unchanged.
        let label = NSTextField(labelWithString: "GitHub inbox ↗")
        label.font = .systemFont(ofSize: 11)
        label.textColor = theme.inkTertiary
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)

        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = theme.inkTertiary
        hintLabel.isHidden = true                    // session-only chrome (F8 boundary)
        hintLabel.translatesAutoresizingMaskIntoConstraints = false
        hintLabel.setAccessibilityElement(false)     // visual hint; VO mirrors the selection itself
        addSubview(hintLabel)

        // WP 2026-07-12-001: grow the click band from text-height (~15px) to a comfortable
        // ~30px by padding INSIDE the existing full-width target (8pt top/bottom). The base
        // hitTest already flattens the footer to one target, so this is pure hit-band, no new
        // geometry. The hint stays centerY-tied to the label, so it rides the padding for free.
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            hintLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            hintLabel.centerYAnchor.constraint(equalTo: label.centerYAnchor),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(openInbox)))
        setAccessibilityElement(true)                                  // review F7
        setAccessibilityRole(.button)
        setAccessibilityLabel("Audit the full GitHub inbox")
    }

    /// WP-6k: hint on ⇄ off with the session — a hidden label, never a rebuild (the
    /// footer line's height is unchanged, so no reflow rides the toggle).
    func setHintVisible(_ visible: Bool) {
        hintLabel.isHidden = !visible
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformPress() -> Bool { openInbox(); return true }

    @objc private func openInbox() {
        if let url = URL(string: "https://github.com/notifications") { NSWorkspace.shared.open(url) }
    }
}

/// Fixed row text-column math (the island is fixed-width, so truncation is decidable at
/// build time, headless): 520 − 18·2 (content insets) − 20 (icon) − 8 (gap) = 456. A
/// chevroned row's text column gives up another 8 (gap) + 22 (chevron) = 426. The chevron
/// decision measures against the NO-chevron width — a row whose text fits at 456 hides
/// nothing, so it earns no chevron (adding one would CAUSE the truncation it reveals).
///
/// KNOWN LIMITATION (fix round, trust minor — recorded, accepted for dogfood): these
/// constants assume the lanes' forced `scrollerStyle = .overlay` (no reserved scroller
/// width). If a lane ever falls back to LEGACY scrollers (AppKit re-resolves the style on
/// preferred-style changes, e.g. "Always show scroll bars"), rows compress below 456 and
/// text can truncate with neither a chevron nor the removed OS tooltip. The honest fix if
/// dogfood ever hits it: measure `needsChevron` against the row's ACTUAL laid-out width.
private enum RowMetrics {
    static let textWidth: CGFloat = IslandContentView.width - 2 * 18 - 20 - 8
    static let chevronGap: CGFloat = 8
    static let chevronSize = NSSize(width: 22, height: 18)
    static let peekedTextWidth: CGFloat = textWidth - chevronGap - chevronSize.width
}

/// The trailing disclosure chevron (WP-3d′, D-reveal `chevron-inline-peek`): 22×18,
/// SF `chevron.down` 11px semibold — inkTertiary at rest, inkSecondary while the ROW is
/// hovered — with its own hover fill (radius 5, pointer hand). A REAL second hit target:
/// the row's `hitTest` carve-out routes clicks in this frame here and nowhere else, so a
/// peek click can never navigate. Rotates 180° over 140ms cubic-bezier(0.2,0,0,1) on
/// toggle — motion mapped 1:1 to the user's own click; Reduce Motion → instant.
final class PeekChevronView: IslandClickableView {
    private let icon = NSImageView()
    private let restTint: NSColor
    private let rowHoverTint: NSColor
    private let onToggle: () -> Void
    private var pointingUp = false

    init(theme: Theme, onToggle: @escaping () -> Void) {
        self.restTint = theme.inkTertiary
        self.rowHoverTint = theme.inkSecondary
        self.onToggle = onToggle
        super.init(frame: NSRect(origin: .zero, size: RowMetrics.chevronSize))
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill
        translatesAutoresizingMaskIntoConstraints = false

        icon.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        icon.contentTintColor = restTint
        icon.wantsLayer = true   // smooth frameCenterRotation
        // Frame-positioned (no constraints) inside the fixed 22×18 target, so
        // `frameCenterRotation` can spin it without fighting Auto Layout.
        let size = icon.fittingSize
        icon.frame = NSRect(x: (RowMetrics.chevronSize.width - size.width) / 2,
                            y: (RowMetrics.chevronSize.height - size.height) / 2,
                            width: size.width, height: size.height)
        icon.autoresizingMask = []
        addSubview(icon)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: RowMetrics.chevronSize.width),
            heightAnchor.constraint(equalToConstant: RowMetrics.chevronSize.height),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        // Not a VoiceOver stop: the ROW carries the "Show/Hide full text" custom action
        // (one spoken row, not two) — this is the pointer affordance only.
        setAccessibilityElement(false)
        icon.setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The row relays its own hover so the chevron brightens with it (spec: inkSecondary
    /// on row hover) — an ink change on the pointer's own movement, not idle motion.
    func setRowHovered(_ hovered: Bool) {
        icon.contentTintColor = hovered ? rowHoverTint : restTint
    }

    /// Cursor hand-back (fix round, minor 4): leaving the chevron usually lands INSIDE
    /// the still-hovered row (the chevron is carved out of it), and the row's own
    /// `mouseEntered` won't re-fire — the pointer never left its tracking area — so the
    /// base class's exit-to-arrow would strand an arrow cursor over a clickable row.
    /// Restore the pointing hand when the pointer is still inside a clickable parent row.
    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)   // clears the chevron's own fill + sets arrow
        if let row = superview as? IslandClickableView, row.hoverFill != nil,
           row.bounds.contains(row.convert(event.locationInWindow, from: nil)) {
            NSCursor.pointingHand.set()
        }
    }

    /// Point up while the peek is open. `animated` is false for a rebuild restore —
    /// replaying stashed state is not motion (attention-non-theft).
    func setPointingUp(_ up: Bool, animated: Bool) {
        guard up != pointingUp else { return }
        pointingUp = up
        let target: CGFloat = up ? 180 : 0
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
                icon.animator().frameCenterRotation = target
            }
        } else {
            icon.frameCenterRotation = target
        }
    }

    @objc private func tapped() { onToggle() }
}

/// One action-required row: a leading SF Symbol (ink by default; `danger` only for a
/// critical emergency — color doctrine) + title + "repo · actor · reason · age".
///
/// WP-3d′ inline peek: when the measured title OR subtitle OR excerpt truncates (the
/// Core predicate), the row grows a trailing chevron whose click — and ONLY whose click —
/// un-truncates in place (title ≤3 · subtitle ≤2 · excerpt ≤4 lines). Plain row click
/// stays Open-on-GitHub byte-for-byte; the `hitTest` carve-out (pure decision in
/// `PeekReveal.hitTarget`, tested) makes the two targets structurally unmixable.
/// Option-click anywhere on the row also toggles. The OS tooltip is REMOVED: truncated
/// rows reveal via the chevron (one channel), un-truncated rows have nothing to restate.
final class RadarRowView: IslandClickableView, KeySessionActionable {
    private let url: URL?
    private let onPeekToggle: ((Bool) -> Void)?
    private var chevron: PeekChevronView?
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private var excerptLabel: NSTextField?
    private(set) var peeked = false

    init(row: RadarRow, theme: Theme, peeked: Bool = false, onPeekToggle: ((Bool) -> Void)? = nil) {
        self.url = row.url.flatMap(URL.init(string:))
        self.onPeekToggle = onPeekToggle
        super.init(frame: .zero)

        // WP-6k ink-bar focus tokens (base class executes): hoverFill + inkPrimary bar.
        // Set unconditionally — a nil-url row is still selectable (⏎ just no-ops on it).
        keyFocusFill = theme.hoverFill
        keyFocusBarColor = theme.inkPrimary

        // The subtitle's age is formatted AT RENDER from the row's timestamp (never a baked
        // "· 2h") — so every rebuild (poll tick, expand) shows the correct age. `Date()` is the
        // render `now`; the scheduler re-renders when a coarse age bucket flips (RadarPresenter).
        let subtitleText = RadarPresenter.displaySubtitle(for: row, now: Date())

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)   // restrained SF weight, not web-bold
        title.textColor = theme.inkPrimary
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel = title

        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)   // ages align (e.g. "2h", "13m")
        subtitle.textColor = theme.inkSecondary
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel = subtitle

        var textViews: [NSView] = [title, subtitle]
        if let excerpt = row.excerpt, !excerpt.isEmpty {
            let preview = NSTextField(labelWithString: excerpt)
            preview.font = .systemFont(ofSize: 11)
            preview.textColor = theme.inkTertiary
            preview.lineBreakMode = .byTruncatingTail
            preview.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            excerptLabel = preview
            textViews.append(preview)
        }

        // The truncation predicate (D-reveal amendment 3, decided in Core): measured
        // against the fixed no-chevron column width — never unconditional chrome.
        let needsChevron = PeekReveal.needsChevron(
            titleFits: title.intrinsicContentSize.width <= RowMetrics.textWidth,
            subtitleFits: subtitle.intrinsicContentSize.width <= RowMetrics.textWidth,
            excerptFits: (excerptLabel?.intrinsicContentSize.width ?? 0) <= RowMetrics.textWidth)

        if url != nil || needsChevron {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(rowClicked)))
        }
        if url != nil {
            hoverFill = theme.hoverFill   // base IslandClickableView handles highlight + pointing-hand cursor
        }
        // Accessibility (review F7): the row is a gesture-driven NSView, so VoiceOver/keyboard
        // get nothing by default. Expose it as a labelled button that opens on GitHub.
        // The label speaks the FULL untruncated texts INCLUDING the excerpt (fix round,
        // minor 5 — the old title+subtitle label made the peek reveal something VO could
        // never hear; the D-reveal review amended sibling variants for exactly this).
        // With the excerpt spoken, the peek is a purely visual un-truncation → parity holds.
        setAccessibilityElement(true)
        setAccessibilityRole(url != nil ? .button : .staticText)
        setAccessibilityLabel(
            [row.title, subtitleText, row.excerpt]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ". "))

        let icon = NSImageView()
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        icon.image = NSImage(systemSymbolName: row.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        icon.contentTintColor = theme.radarGlyphColor(critical: row.isCritical)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let iconWrap = NSView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 20),
            // Height ≈ the title's line box + center the glyph in it, so the top-aligned
            // row puts the glyph on the TITLE's center (not the row's top edge, where it
            // read as clipped/too-high). Fixes "the icons' tops are clipped a little."
            iconWrap.heightAnchor.constraint(equalToConstant: 18),
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
        ])

        let textStack = NSStackView(views: textViews)
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        // Glyph anchored to the TITLE's line (via the 18pt wrap above), not the block's
        // center: block-centering wanders as the block grows — down to the subtitle on
        // excerpted rows, mid-block on a peeked one — while the chevron stays top-pinned.
        // SUPERSEDES iter 041's `.centerY` ("center the icon vertically"), which predates
        // peeks; re-ratified with the peek rationale 2026-07-09 (agenda amendments).
        let rowStack = NSStackView(views: [iconWrap, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        var cons = [
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if needsChevron {
            // Wrap math for the peeked state: the labels' preferred wrap width is the
            // chevroned column, so multi-line intrinsic heights are deterministic.
            for label in [titleLabel, subtitleLabel, excerptLabel].compactMap({ $0 }) {
                label.preferredMaxLayoutWidth = RowMetrics.peekedTextWidth
            }
            let chev = PeekChevronView(theme: theme) { [weak self] in self?.togglePeek() }
            addSubview(chev)
            chevron = chev
            cons += [
                rowStack.trailingAnchor.constraint(equalTo: chev.leadingAnchor,
                                                   constant: -RowMetrics.chevronGap),
                chev.trailingAnchor.constraint(equalTo: trailingAnchor),
                chev.topAnchor.constraint(equalTo: topAnchor),   // top-aligned to the title's line box
            ]
        } else {
            cons.append(rowStack.trailingAnchor.constraint(equalTo: trailingAnchor))
        }
        NSLayoutConstraint.activate(cons)

        if peeked, needsChevron {
            setPeeked(true, animatedChevron: false)   // restored across a rebuild — replayed state, 0ms
        }
        refreshPeekAction()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: peek mechanics

    /// The D-reveal carve-out (blocking amendment 1): `IslandClickableView.hitTest`
    /// flattens the row to ONE target so child labels never swallow first-mouse clicks —
    /// but the chevron is a REAL second target (a peek attempt must never navigate). The
    /// decision is the pure `PeekReveal.hitTarget`, tested headlessly in Core.
    override func hitTest(_ point: NSPoint) -> NSView? {
        switch PeekReveal.hitTarget(point: convert(point, from: superview),
                                    rowBounds: bounds, chevronFrame: chevron?.frame) {
        case .chevron: return chevron
        case .row: return self
        case .none: return nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        chevron?.setRowHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        chevron?.setRowHovered(false)
    }

    private func togglePeek() {
        guard chevron != nil else { return }
        setPeeked(!peeked, animatedChevron: true)
        onPeekToggle?(peeked)
    }

    /// Apply the peek state to the labels (ratified caps: title ≤3 · subtitle ≤2 ·
    /// excerpt ≤4 lines; single-line truncation otherwise).
    private func setPeeked(_ open: Bool, animatedChevron: Bool) {
        peeked = open
        applyLineCap(titleLabel, open ? PeekReveal.titleLineCap : 1)
        applyLineCap(subtitleLabel, open ? PeekReveal.subtitleLineCap : 1)
        if let excerptLabel { applyLineCap(excerptLabel, open ? PeekReveal.excerptLineCap : 1) }
        chevron?.setPointingUp(open, animated: animatedChevron)
        refreshPeekAction()
    }

    private func applyLineCap(_ label: NSTextField, _ cap: Int) {
        label.maximumNumberOfLines = cap
        label.lineBreakMode = cap == 1 ? .byTruncatingTail : .byWordWrapping
        label.cell?.truncatesLastVisibleLine = cap > 1   // an over-cap peek still shows its ellipsis honestly
    }

    /// VoiceOver: ONE custom action on the row ("Show full text"/"Hide full text")
    /// toggling the same state. The row's label already speaks the full text, so spoken
    /// parity holds either way — the action keeps the sighted and spoken affordances equal.
    private func refreshPeekAction() {
        guard chevron != nil else { return }
        let name = peeked ? "Hide full text" : "Show full text"
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: name) { [weak self] in
            self?.togglePeek()
            return true
        }])
    }

    @objc private func rowClicked() {
        // Option-click anywhere on the row toggles the peek (the ratified power path);
        // a plain click is Open-on-GitHub, byte-for-byte today's behavior.
        if chevron != nil, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            togglePeek()
            return
        }
        openInBrowser()
    }

    override func accessibilityPerformPress() -> Bool {
        guard url != nil else { return false }
        openInBrowser(); return true
    }

    // MARK: WP-6k key-session actions (the EXISTING paths, keyboard-driven)

    /// ⏎ — the same Open-on-GitHub path a plain click runs, incl. its nil-url no-op
    /// guard. Returns whether an open actually fired.
    @discardableResult func performOpen() -> Bool {
        guard url != nil else { return false }
        openInBrowser()
        return true
    }

    /// Space — the chevron's own toggle (motion sanction identical to a chevron click:
    /// the 140ms reflow rides the same onPeekToggle seam). No-op without a chevron.
    @discardableResult func performPeekToggle() -> Bool {
        guard chevron != nil else { return false }
        togglePeek()
        return true
    }

    /// Open-on-GitHub — opens the thread in the browser without activating the HUD
    /// (focus-non-theft). We open, we don't act from the HUD (the H3 guardrail).
    @objc private func openInBrowser() {
        if let url { NSWorkspace.shared.open(url) }
    }
}

/// One H2 pulse row: a state-tinted leading glyph (theme decides hue + fill/outline) +
/// PR title + "repo #n · CI · review · merge · age". Clickable → Open-on-GitHub.
/// Carries the same WP-3d′ inline peek as `RadarRowView` (title ≤3 · subtitle ≤2; no
/// excerpt on pulse rows) — see that class for the carve-out/tooltip/a11y contracts.
final class PulseRowView: IslandClickableView, KeySessionActionable {
    private let url: URL?
    private let onPeekToggle: ((Bool) -> Void)?
    private var chevron: PeekChevronView?
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private(set) var peeked = false

    /// TAIL DEMOTION (WP 2026-07-26-001, widened by 2026-07-29-001), derived from the row — never
    /// passed in. The predicate is one idea: **not in the live glance**. A draft is your own WIP
    /// and a quiet row has been rotting a fortnight; neither is a peer of live work, so the title
    /// steps down to the secondary ink the subtitles use and the state badge steps back with it.
    /// Without it a blocked draft — or a conflicted 16-week PR, which rolls up blocked exactly the
    /// same way — shouts as loudly as blocked live work, the thing pulling them out of the glance
    /// existed to prevent.
    ///
    /// Derived, not a parameter, because it is a fact the ROW carries: `sections(for:)` puts
    /// `isDraft` rows in `drafts` and `isStale` rows in `stale`, and keeps both out of `active`, so
    /// the demotion lands in exactly the places that want it and nowhere else. As a call-site flag
    /// it was forgettable, and it got forgotten — the flat shape's terminal region shipped without
    /// it and needed a reviewer to catch (commit d2a90d8). A future render path cannot forget a
    /// value it never supplies, and V3 added two more render paths at once.
    /// `elideOwner`/`emphasizeOwner` stay parameters: those depend on the surrounding title, which
    /// is knowledge the row genuinely does not have.
    ///
    /// VISIBLE CONSEQUENCE, deliberate: flat-shape quiet rows dim too, where before V3 only drafts
    /// did. One rule, both shapes, both tails. Flagged in the WP brief as glass-settled rather than
    /// argued; the revert is this one predicate.
    ///
    /// The demotion is applied PER ELEMENT, never as `alphaValue` on the row: this view's layer
    /// is where `setKeyFocused` paints the selection fill, and the 3pt ink bar is added as its
    /// SUBVIEW (see HUDPanel.setKeyFocused) — a row-level alpha composites both, leaving the
    /// ⌃⌥G cursor dimmest exactly where the keyboard walk ends, and dimming the hover band that
    /// says "this is clickable". Ink and weight only; the peek, the hover band, the click
    /// target and the a11y form are untouched (VoiceOver already speaks "draft" — the subtitle
    /// carries it from PulsePresenter's composition members).
    init(row: PulseRow, theme: Theme, peeked: Bool = false,
         elideOwner: Bool = false, emphasizeOwner: String? = nil,
         onPeekToggle: ((Bool) -> Void)? = nil) {
        let subdued = row.isDraft || row.isStale
        self.url = URL(string: row.url)
        self.onPeekToggle = onPeekToggle
        super.init(frame: .zero)

        // WP-6k ink-bar focus tokens — mirrors RadarRowView (see its comment).
        keyFocusFill = theme.hoverFill
        keyFocusBarColor = theme.inkPrimary

        // Age formatted AT RENDER from the row's timestamp (never baked) — mirrors RadarRowView.
        // Owner lens: `elideOwner` drops the prefix a title already carries (or the
        // viewer's own); VoiceOver below always speaks the FULL form regardless.
        let subtitleText = PulsePresenter.displaySubtitle(for: row, now: Date(), elideOwner: elideOwner)

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: subdued ? .regular : .medium)
        title.textColor = subdued ? theme.inkSecondary : theme.inkPrimary
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel = title

        let subtitle = NSTextField(labelWithString: "")
        let subtitleFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)   // ages align (e.g. "2h", "13m")
        let subtitleAttr = NSMutableAttributedString(
            string: subtitleText,
            attributes: [.font: subtitleFont, .foregroundColor: theme.inkSecondary])
        // Owner lens, flat run: a foreign org's leading token gets ONE ink step (medium +
        // primary ink) — A's quiet typography; position + ink, never a badge. Applied only
        // when the token actually leads the composed string (styled-substring precedent).
        if let owner = emphasizeOwner, subtitleText.hasPrefix(owner + "/"),
           let r = subtitleText.range(of: owner) {
            subtitleAttr.addAttributes(
                [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                 .foregroundColor: theme.inkPrimary],
                range: NSRange(r, in: subtitleText))
        }
        subtitle.attributedStringValue = subtitleAttr
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel = subtitle

        // Truncation predicate (Core-owned OR; no excerpt on pulse rows → trivially fits).
        let needsChevron = PeekReveal.needsChevron(
            titleFits: title.intrinsicContentSize.width <= RowMetrics.textWidth,
            subtitleFits: subtitle.intrinsicContentSize.width <= RowMetrics.textWidth,
            excerptFits: true)

        if url != nil || needsChevron {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(rowClicked)))
        }
        if url != nil {
            hoverFill = theme.hoverFill
        }
        setAccessibilityElement(true)                                  // review F7
        setAccessibilityRole(url != nil ? .button : .staticText)
        // VoiceOver always speaks the FULL owner/repo form — elision and emphasis are
        // visual-only (owner lens; the gray-swap a11y law: spoken meaning never degrades).
        setAccessibilityLabel("\(row.title). \(PulsePresenter.displaySubtitle(for: row, now: Date()))")
        // OS tooltip removed (D-reveal truncated-only rule) — the chevron is the one
        // reveal channel; a fully-visible row has nothing to restate.

        // PR status uses GitHub's OWN canonical icons (green ✓ / red ✕ / amber ● / gray
        // conflict warning), theme-independent — status is GitHub's visual language, not
        // githud's chrome — so a PR reads identically in every theme.
        let glyphView: NSView = GitHubStatusBadge(.forPulse(state: row.state, merge: row.merge))
        glyphView.translatesAutoresizingMaskIntoConstraints = false
        glyphView.setContentHuggingPriority(.required, for: .horizontal)
        // A tail row's badge steps back with its text. Set HERE, on the badge, not on the row:
        // see the `subdued` note above — an alpha on the row view composites its focus bar and
        // hover fill too, and the ⌃⌥G cursor must not be dimmest exactly where the walk ends.
        if subdued { glyphView.alphaValue = 0.72 }

        let iconWrap = NSView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(glyphView)
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 20),
            iconWrap.heightAnchor.constraint(equalToConstant: 18),
            glyphView.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            glyphView.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
        ])

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        // Badge anchored to the TITLE's line, not the block's center — mirrors
        // RadarRowView (see its comment): peek-stable, level with the chevron.
        let rowStack = NSStackView(views: [iconWrap, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        var cons = [
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if needsChevron {
            for label in [titleLabel, subtitleLabel].compactMap({ $0 }) {
                label.preferredMaxLayoutWidth = RowMetrics.peekedTextWidth
            }
            let chev = PeekChevronView(theme: theme) { [weak self] in self?.togglePeek() }
            addSubview(chev)
            chevron = chev
            cons += [
                rowStack.trailingAnchor.constraint(equalTo: chev.leadingAnchor,
                                                   constant: -RowMetrics.chevronGap),
                chev.trailingAnchor.constraint(equalTo: trailingAnchor),
                chev.topAnchor.constraint(equalTo: topAnchor),   // top-aligned to the title's line box
            ]
        } else {
            cons.append(rowStack.trailingAnchor.constraint(equalTo: trailingAnchor))
        }
        NSLayoutConstraint.activate(cons)

        if peeked, needsChevron {
            setPeeked(true, animatedChevron: false)   // restored across a rebuild — replayed state, 0ms
        }
        refreshPeekAction()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: peek mechanics (mirrors RadarRowView — see its doc comments)

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch PeekReveal.hitTarget(point: convert(point, from: superview),
                                    rowBounds: bounds, chevronFrame: chevron?.frame) {
        case .chevron: return chevron
        case .row: return self
        case .none: return nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        chevron?.setRowHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        chevron?.setRowHovered(false)
    }

    private func togglePeek() {
        guard chevron != nil else { return }
        setPeeked(!peeked, animatedChevron: true)
        onPeekToggle?(peeked)
    }

    private func setPeeked(_ open: Bool, animatedChevron: Bool) {
        peeked = open
        applyLineCap(titleLabel, open ? PeekReveal.titleLineCap : 1)
        applyLineCap(subtitleLabel, open ? PeekReveal.subtitleLineCap : 1)
        chevron?.setPointingUp(open, animated: animatedChevron)
        refreshPeekAction()
    }

    private func applyLineCap(_ label: NSTextField, _ cap: Int) {
        label.maximumNumberOfLines = cap
        label.lineBreakMode = cap == 1 ? .byTruncatingTail : .byWordWrapping
        label.cell?.truncatesLastVisibleLine = cap > 1
    }

    private func refreshPeekAction() {
        guard chevron != nil else { return }
        let name = peeked ? "Hide full text" : "Show full text"
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: name) { [weak self] in
            self?.togglePeek()
            return true
        }])
    }

    @objc private func rowClicked() {
        if chevron != nil, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            togglePeek()
            return
        }
        openInBrowser()
    }

    override func accessibilityPerformPress() -> Bool {
        guard url != nil else { return false }
        openInBrowser(); return true
    }

    // MARK: WP-6k key-session actions — mirrors RadarRowView (see its comments)

    @discardableResult func performOpen() -> Bool {
        guard url != nil else { return false }
        openInBrowser()
        return true
    }

    @discardableResult func performPeekToggle() -> Bool {
        guard chevron != nil else { return false }
        togglePeek()
        return true
    }

    @objc private func openInBrowser() {
        if let url { NSWorkspace.shared.open(url) }
    }
}

/// One standing-inbound row (WP 2026-07-09-001): a leading kind glyph (PR pull-arrow /
/// issue dot-circle, ink — nothing here is a color-doctrine emergency) + title +
/// "repo #n · @opener · waiting-age". Clickable → Open-on-GitHub. Carries the same
/// WP-3d′ inline peek and WP-6k key-session contracts as `PulseRowView` (see
/// `RadarRowView` for the carve-out/tooltip/a11y documentation) — a third copy of the
/// row mechanics, disclosed: extracting a shared peek base across three landed, reviewed
/// row classes is a refactor candidate, not a rider on a feature commit.
final class InboundRowView: IslandClickableView, KeySessionActionable {
    private let url: URL?
    private let onPeekToggle: ((Bool) -> Void)?
    private var chevron: PeekChevronView?
    private var titleLabel: NSTextField!
    private var subtitleLabel: NSTextField!
    private(set) var peeked = false

    init(row: InboundRow, theme: Theme, peeked: Bool = false, onPeekToggle: ((Bool) -> Void)? = nil) {
        self.url = URL(string: row.url)
        self.onPeekToggle = onPeekToggle
        super.init(frame: .zero)

        keyFocusFill = theme.hoverFill
        keyFocusBarColor = theme.inkPrimary

        // Waiting-age formatted AT RENDER from the row's opened-at timestamp (never baked).
        let subtitleText = InboundPresenter.displaySubtitle(for: row, now: Date())

        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let title = NSTextField(labelWithString: row.title)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.textColor = theme.inkPrimary
        title.lineBreakMode = .byTruncatingTail
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel = title

        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        subtitle.textColor = theme.inkSecondary
        subtitle.lineBreakMode = .byTruncatingTail
        subtitle.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        subtitleLabel = subtitle

        let needsChevron = PeekReveal.needsChevron(
            titleFits: title.intrinsicContentSize.width <= RowMetrics.textWidth,
            subtitleFits: subtitle.intrinsicContentSize.width <= RowMetrics.textWidth,
            excerptFits: true)

        if url != nil || needsChevron {
            addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(rowClicked)))
        }
        if url != nil {
            hoverFill = theme.hoverFill
        }
        setAccessibilityElement(true)
        setAccessibilityRole(url != nil ? .button : .staticText)
        setAccessibilityLabel("\(row.title). \(subtitleText)")

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: row.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        icon.contentTintColor = theme.inkSecondary   // ink: rank is position, kind is shape
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.setContentHuggingPriority(.required, for: .horizontal)

        let iconWrap = NSView()
        iconWrap.translatesAutoresizingMaskIntoConstraints = false
        iconWrap.addSubview(icon)
        NSLayoutConstraint.activate([
            iconWrap.widthAnchor.constraint(equalToConstant: 20),
            iconWrap.heightAnchor.constraint(equalToConstant: 18),
            icon.centerXAnchor.constraint(equalTo: iconWrap.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconWrap.centerYAnchor),
        ])

        let textStack = NSStackView(views: [title, subtitle])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 1

        // Glyph on the TITLE's line — the same anchoring the other rows settled on
        // (lane-row fix 94e4461): stable under peeks, level with the chevron.
        let rowStack = NSStackView(views: [iconWrap, textStack])
        rowStack.orientation = .horizontal
        rowStack.alignment = .top
        rowStack.spacing = 8
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rowStack)
        var cons = [
            rowStack.leadingAnchor.constraint(equalTo: leadingAnchor),
            rowStack.topAnchor.constraint(equalTo: topAnchor),
            rowStack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ]
        if needsChevron {
            for label in [titleLabel, subtitleLabel].compactMap({ $0 }) {
                label.preferredMaxLayoutWidth = RowMetrics.peekedTextWidth
            }
            let chev = PeekChevronView(theme: theme) { [weak self] in self?.togglePeek() }
            addSubview(chev)
            chevron = chev
            cons += [
                rowStack.trailingAnchor.constraint(equalTo: chev.leadingAnchor,
                                                   constant: -RowMetrics.chevronGap),
                chev.trailingAnchor.constraint(equalTo: trailingAnchor),
                chev.topAnchor.constraint(equalTo: topAnchor),
            ]
        } else {
            cons.append(rowStack.trailingAnchor.constraint(equalTo: trailingAnchor))
        }
        NSLayoutConstraint.activate(cons)

        if peeked, needsChevron {
            setPeeked(true, animatedChevron: false)   // restored across a rebuild — replayed state, 0ms
        }
        refreshPeekAction()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: peek mechanics (mirrors PulseRowView — see RadarRowView's doc comments)

    override func hitTest(_ point: NSPoint) -> NSView? {
        switch PeekReveal.hitTarget(point: convert(point, from: superview),
                                    rowBounds: bounds, chevronFrame: chevron?.frame) {
        case .chevron: return chevron
        case .row: return self
        case .none: return nil
        }
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        chevron?.setRowHovered(true)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        chevron?.setRowHovered(false)
    }

    private func togglePeek() {
        guard chevron != nil else { return }
        setPeeked(!peeked, animatedChevron: true)
        onPeekToggle?(peeked)
    }

    private func setPeeked(_ open: Bool, animatedChevron: Bool) {
        peeked = open
        applyLineCap(titleLabel, open ? PeekReveal.titleLineCap : 1)
        applyLineCap(subtitleLabel, open ? PeekReveal.subtitleLineCap : 1)
        chevron?.setPointingUp(open, animated: animatedChevron)
        refreshPeekAction()
    }

    private func applyLineCap(_ label: NSTextField, _ cap: Int) {
        label.maximumNumberOfLines = cap
        label.lineBreakMode = cap == 1 ? .byTruncatingTail : .byWordWrapping
        label.cell?.truncatesLastVisibleLine = cap > 1
    }

    private func refreshPeekAction() {
        guard chevron != nil else { return }
        let name = peeked ? "Hide full text" : "Show full text"
        setAccessibilityCustomActions([NSAccessibilityCustomAction(name: name) { [weak self] in
            self?.togglePeek()
            return true
        }])
    }

    @objc private func rowClicked() {
        if chevron != nil, NSApp.currentEvent?.modifierFlags.contains(.option) == true {
            togglePeek()
            return
        }
        openInBrowser()
    }

    override func accessibilityPerformPress() -> Bool {
        guard url != nil else { return false }
        openInBrowser(); return true
    }

    // MARK: WP-6k key-session actions — mirrors RadarRowView (see its comments)

    @discardableResult func performOpen() -> Bool {
        guard url != nil else { return false }
        openInBrowser()
        return true
    }

    @discardableResult func performPeekToggle() -> Bool {
        guard chevron != nil else { return false }
        togglePeek()
        return true
    }

    @objc private func openInBrowser() {
        if let url { NSWorkspace.shared.open(url) }
    }
}

extension IslandContentView {
    /// One dimmed departure-receipt row ("Just cleared", plan 2026-07-21-001): repo ·
    /// reason · title in tertiary ink, the known reason suffix right-aligned. One VO
    /// stop speaking the same facts. No affordance beyond reading — the receipt's whole
    /// job is answering "where did it go?".
    func clearedRowView(_ row: ClearedRow) -> NSView {
        // Clickable (land-triage F3): the plan's contract is click = Open on GitHub —
        // the receipt answers "where did it go", the click takes you THERE.
        let container = ClearedRowView(url: row.url, theme: theme)
        container.translatesAutoresizingMaskIntoConstraints = false

        let text = NSTextField(labelWithString: "\(row.repo) · \(row.effectiveReason) · \(row.title)")
        text.font = .systemFont(ofSize: 12)
        text.textColor = theme.inkTertiary
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(text)

        var trailing = container.trailingAnchor
        if let why = row.whyText {
            let suffix = NSTextField(labelWithString: why)
            suffix.font = .systemFont(ofSize: 11)
            suffix.textColor = theme.inkTertiary
            suffix.translatesAutoresizingMaskIntoConstraints = false
            suffix.setContentHuggingPriority(.required, for: .horizontal)
            suffix.setContentCompressionResistancePriority(.required, for: .horizontal)
            container.addSubview(suffix)
            NSLayoutConstraint.activate([
                suffix.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                suffix.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            ])
            trailing = suffix.leadingAnchor
        }
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 24),
            text.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailing, constant: -8),
            text.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])

        container.setAccessibilityElement(true)
        container.setAccessibilityRole(row.url == nil ? .staticText : .button)
        let spokenWhy = row.whyText.map { ", \($0.replacingOccurrences(of: " ✓", with: ""))" } ?? ""
        container.setAccessibilityLabel("just cleared: \(row.title), \(row.effectiveReason)\(spokenWhy)")
        return container
    }
}

/// The receipt row's clickable base — hover + click → Open on GitHub (land-triage F3),
/// the same carve-out-free pattern as the caption buttons.
private final class ClearedRowView: IslandClickableView {
    private let url: String?
    init(url: String?, theme: Theme) {
        self.url = url
        super.init(frame: .zero)
        guard url != nil else { return }
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func tapped() { open() }
    override func accessibilityPerformPress() -> Bool { open(); return true }
    private func open() {
        if let url = url.flatMap(URL.init(string:)) { NSWorkspace.shared.open(url) }
    }
}
