import CoreGraphics
import Foundation

/// WP-3x — the slot-morph pill's fingerprint/diff brain (the ratified G-crossfade pick,
/// `slot-morph-inkfocus`, pill half). Pure — no AppKit — so every transition rule is
/// headlessly testable. The view layer (`CollapsedPillView` + `HUDPanelController`)
/// consumes the `Plan`; it never re-derives any rule below.
///
/// The chassis every pill state renders into (geometry unchanged from the shipped pill):
///
///     [stale prefix slot · 19px, only when degraded] [glyph cell] [gap 6] [value cell]
///
/// ═══════════════════════════════════════════════════════════════════════════════════
/// INVARIANT (ratified, G-crossfade C — written where the diff lives, per the record):
///
///     **no motion where no fact changed.**
///
/// - An identical fingerprint plans no cell fade and no cell repaint (the CALLER's hard-cut
///   still does a single-frame pill rebuild — 0ms, visually identical; the invariant is
///   "no MOTION where no fact changed," which this honors — not "no rebuild").
/// - An equal-digit value tick (3→4, and per the review's binding clarification ANY
///   equal-digit count tick INCLUDING gauge segment counts, e.g. ✓2→✓1) is INSTANT, 0ms —
///   exactly today's single-frame swap; tabular digits mean zero pixels move.
/// - Only a cell whose FACT crossed states may crossfade (120ms), and only THAT cell;
///   rule (b)'s enumeration is exhaustive for what fades.
/// - The ink↔danger critical transition is carried by the ordinary GLYPH-cell crossfade
///   (rule c): isCritical is part of the glyph fact, so any critical arrival/departure —
///   including check→radar(critical) (a security alert from a clear pill) — is already a
///   glyph-fact change that fades. No separate flag marks it (a computed-but-unconsumed one
///   was a false witness with a radar→radar-only blind spot; deleted).
/// - Reduce Motion zeroes every duration (enforced by the caller, which owns AppKit).
/// - One transition per poll burst (the existing render coalescer enforces this); a
///   second change landing mid-fade jumps to the end state (caller falls back to the
///   instant path while a fade is in flight).
/// ═══════════════════════════════════════════════════════════════════════════════════
public enum PillMorph {

    /// The three chassis cells.
    public enum Cell: String, CaseIterable, Sendable, Hashable {
        case prefix   // the degraded-freshness caution clock slot
        case glyph    // the leading glyph (loading dot / radar reason / check)
        case value    // the count text or the segmented gauge
    }

    /// The glyph cell's fact.
    public enum Glyph: Equatable, Sendable {
        case loading                                 // pre-first-poll dim dot
        case radar(symbol: String, critical: Bool)   // top reason's symbol; danger tint iff critical
        case check                                   // inbox clear, no live PRs — CONFIRMED read
        /// Clear-LOOKING but not confirmed read (ratified A2, 2026-07-21): the pill must
        /// never wear the earned check over an inbox githud hasn't actually read this
        /// session (the island's affirmation gate, drawn). Distinct STATE — the final
        /// mark arrives with the logo path; rendering is a placeholder until then.
        case checkUnconfirmed
        case none                                    // gauge state — glyphs live inside the segments
    }

    /// One gauge segment's fact (state + its rendered count string).
    public struct GaugeSegmentPrint: Equatable, Sendable {
        public let state: PulseState
        public let count: String
        public init(state: PulseState, count: String) {
            self.state = state
            self.count = count
        }
    }

    /// A standing queue's fact within a composed value cell (D-pill §3). `mark` is the
    /// count-free presence (standingMarked — someone is at the door, no number); `count`
    /// carries the drawn digits (standingCounted). One case, so the standing tier can never
    /// draw a number the spoken parity omits and vice-versa.
    public enum QueuePrint: Equatable, Sendable {
        case mark
        case count(String)
    }

    /// The value cell's fact.
    public enum Value: Equatable, Sendable {
        case none                        // loading / bare-check states carry no value cell
        case count(String)               // "needs you" count OR the standing tray+count (queue-only)
        case gauge([GaugeSegmentPrint])  // caught-up living gauge, in display order
        /// The composed standing tier (D-pill): the living gauge PLUS a standing queue,
        /// side by side. Only the two proven-disjoint facts compose (gauge ⊕ queue) — the
        /// killed composed-lanes mechanics do not transfer; a structure change fades the
        /// whole value cell (no per-segment engine).
        case standing(gauge: [GaugeSegmentPrint], queue: QueuePrint)
    }

    /// The standing queue's still-life glyph (`tray.fill`) — the tense split the record
    /// keeps deliberate: the RADAR's arriving-knock inbound reason stays
    /// `tray.and.arrow.down.fill` (RadarPresenter, untouched); the pill's STANDING queue
    /// (a waiting line, not an arrival) draws this still tray.
    public static let standingTraySymbol = "tray.fill"

    /// Everything the collapsed pill renders, as comparable facts.
    public struct Fingerprint: Equatable, Sendable {
        public let stalePrefix: Bool
        public let glyph: Glyph
        public let value: Value
        public init(stalePrefix: Bool, glyph: Glyph, value: Value) {
            self.stalePrefix = stalePrefix
            self.glyph = glyph
            self.value = value
        }
    }

    /// The pill's resolved content decision for one (style × state) — the SINGLE decision
    /// tree that `fingerprint` / `width` / the spoken a11y value all consume, so the three
    /// can never drift (F5). The per-fact clock flags (`showsPollFact` / `showsSweepFact`)
    /// let the D1 stale prefix pick the right clock (poll for radar/gauge/check, sweep for
    /// any inbound count/mark) — and degrade a composed claim from its stalest member.
    public struct Resolved: Equatable, Sendable {
        public let glyph: Glyph
        public let value: Value
        /// A poll-clock fact (radar / gauge / check / loading) is on display.
        public let showsPollFact: Bool
        /// A sweep-clock fact (any standing inbound count or mark) is on display.
        public let showsSweepFact: Bool
        public init(glyph: Glyph, value: Value, showsPollFact: Bool, showsSweepFact: Bool) {
            self.glyph = glyph
            self.value = value
            self.showsPollFact = showsPollFact
            self.showsSweepFact = showsSweepFact
        }
    }

    /// The ONE decision tree, per pill style. The acute region (loading → radar → critical)
    /// is identical across styles; the styles diverge only where the inbox is clear and a
    /// standing queue meets the living gauge. The gauge is computed over
    /// `PulsePresenter.sections(for:).active` (the ONE home of the live-work rule), exactly
    /// as the expanded lane and the spoken value do — so no surface can drift from another.
    /// `clearConfirmed` = radarConfirmed ∧ inboundConfirmed ∧ reviewsConfirmed, computed
    /// at the shell seam (AppModel owns the three facts + the per-session reset). Default
    /// FALSE — fail-closed, the inbound/reviews-confirmation precedent: a call site that
    /// doesn't know the fact draws the unconfirmed check, never the earned one.
    public static func resolve(style: PillStyle, rows: [RadarRow], pulse: [PulseRow],
                               loading: Bool, inboundActive: Int,
                               clearConfirmed: Bool = false) -> Resolved {
        if loading {
            return Resolved(glyph: .loading, value: .none, showsPollFact: true, showsSweepFact: false)
        }
        if let top = rows.first {
            return Resolved(glyph: .radar(symbol: top.symbolName,
                                          critical: rows.contains { $0.isCritical }),
                            value: .count(String(rows.count)),
                            showsPollFact: true, showsSweepFact: false)
        }
        let gauge = PulsePresenter.gauge(rows: PulsePresenter.sections(for: pulse).active)
        let queue = inboundActive
        // The shared queue-only tier (all styles): a standing queue with NO live PRs draws
        // the still tray + count — the F1 "dead" inbound tier, now reachable. Sweep clock.
        func queueOnly() -> Resolved {
            Resolved(glyph: .radar(symbol: standingTraySymbol, critical: false),
                     value: .count(String(queue)),
                     showsPollFact: false, showsSweepFact: true)
        }
        func gaugeOnly(_ g: PulseGauge) -> Resolved {
            Resolved(glyph: .none, value: .gauge(prints(g)),
                     showsPollFact: true, showsSweepFact: false)
        }
        // The bare check is a CLAIM ("all caught up"), not a count — it rides the same
        // three-lane confirmation gate as the island's affirmation. Counts and the gauge
        // are facts and stay ungated (their honesty rides the freshness clocks).
        let check = Resolved(glyph: clearConfirmed ? .check : .checkUnconfirmed,
                             value: .none, showsPollFact: true, showsSweepFact: false)

        switch style {
        case .queueLeads:
            // Ladder-strict as amended (D2): INBOUND above gauge. A standing queue is
            // exclusive — it walls off the gauge (recorded utility cost, answered by config).
            if queue > 0 { return queueOnly() }
            if let gauge { return gaugeOnly(gauge) }
            return check

        case .standingMarked, .standingCounted:
            // The standing tier composes the proven-disjoint gauge ⊕ queue side by side.
            if let gauge, queue > 0 {
                let q: QueuePrint = style == .standingCounted ? .count(String(queue)) : .mark
                return Resolved(glyph: .none, value: .standing(gauge: prints(gauge), queue: q),
                                showsPollFact: true, showsSweepFact: true)
            }
            if let gauge { return gaugeOnly(gauge) }
            if queue > 0 { return queueOnly() }
            return check
        }
    }

    private static func prints(_ gauge: PulseGauge) -> [GaugeSegmentPrint] {
        gauge.segments.map { GaugeSegmentPrint(state: $0.state, count: String($0.count)) }
    }

    /// D1 — the per-fact stale clock (WP 2026-07-10-001 §1). The displayed pill composes a
    /// poll-clock fact (radar/gauge/check) and/or a sweep-clock fact (any inbound count/mark);
    /// the caution prefix reads the WORST of whichever clocks its facts actually depend on. A
    /// composed standing claim is only as fresh as its stalest member; a poll-only or
    /// sweep-only state reads that one clock. Pure, shared by `fingerprint` and the spoken
    /// value so the drawn clock glyph and the spoken "…stale…" prefix can never disagree.
    public static func prefixFreshness(_ resolved: Resolved,
                                       pollFreshness: Freshness,
                                       sweepFreshness: Freshness) -> Freshness {
        switch (resolved.showsPollFact, resolved.showsSweepFact) {
        case (true, true):   return FreshnessModel.worst(pollFreshness, sweepFreshness)
        case (true, false):  return pollFreshness
        case (false, true):  return sweepFreshness
        case (false, false): return .fresh   // unreachable — something always renders
        }
    }

    /// Mirror of `CollapsedPillView`'s own decision tree (via `resolve`), with the D1 stale
    /// prefix picked per displayed fact. `freshness` is the POLL clock (radar/pulse spine);
    /// `sweepFreshness` is the inbound sweep clock (`FreshnessModel.sweepStatus`). Existing
    /// callers that pass neither `sweepFreshness` nor `style` get the fresh-sweep, default-
    /// style behavior — identical to the pre-config pill for the POLL-CLOCK states
    /// (loading / radar / gauge / check); the QUEUE region changed deliberately with this WP
    /// (still-life `tray.fill`, the D2 inbound-above-gauge order, the sweep clock's prefix).
    public static func fingerprint(rows: [RadarRow], pulse: [PulseRow],
                                   loading: Bool, freshness: Freshness,
                                   sweepFreshness: Freshness = .fresh,
                                   inboundActive: Int = 0,
                                   style: PillStyle = .queueLeads,
                                   clearConfirmed: Bool = false) -> Fingerprint {
        let resolved = resolve(style: style, rows: rows, pulse: pulse,
                               loading: loading, inboundActive: inboundActive,
                               clearConfirmed: clearConfirmed)
        let prefix = prefixFreshness(resolved, pollFreshness: freshness, sweepFreshness: sweepFreshness)
        return Fingerprint(stalePrefix: prefix.isDegraded, glyph: resolved.glyph, value: resolved.value)
    }

    // MARK: - width (pure, so the F5 matrix pins it alongside fingerprint + spoken)

    /// The collapsed pill's full width for a resolved fingerprint — pure Core so the
    /// style-matrix test can pin width beside the fingerprint and spoken value (the three
    /// cannot drift). `CollapsedPillView.size(for:)` is a thin wrapper over this. Geometry
    /// is verbatim from the shipped pill's formulas, extended for the two composed cases.
    public static func width(for fingerprint: Fingerprint) -> CGFloat {
        let stalePad: CGFloat = fingerprint.stalePrefix ? 19 : 0   // the caution clock slot
        return baseWidth(fingerprint.value) + stalePad
    }

    /// One gauge SEGMENT's own advance: glyph 16 + gap 4 + digits·9 (no inter-segment gap).
    private static func segmentAdvance(digits: Int) -> CGFloat {
        let d = max(1, digits)
        return CGFloat(16 + 4 + d * 9)
    }

    /// The whole gauge: outer padding 24 + each segment's advance + a 6pt gap between segments.
    private static func gaugeWidth(_ segments: [GaugeSegmentPrint]) -> CGFloat {
        var width: CGFloat = 24
        for (i, seg) in segments.enumerated() {
            if i > 0 { width += 6 }
            width += segmentAdvance(digits: seg.count.count)
        }
        return width
    }

    /// The radar/inbound count pill: glyph 18 + gap 6 + digits·10 + trailing padding 26.
    private static func countWidth(_ text: String) -> CGFloat {
        let d = max(1, text.count)
        return CGFloat(18 + 6 + d * 10 + 26)
    }

    private static func baseWidth(_ value: Value) -> CGFloat {
        switch value {
        case .none:
            return 52                                    // loading dot / bare check
        case .count(let text):
            return countWidth(text)                      // radar-need OR queue-only tray+count
        case .gauge(let segments):
            return gaugeWidth(segments)
        case .standing(let gauge, let queue):
            switch queue {
            case .mark:
                // standingMarked: the 11pt count-free tray mark adds a fixed +20pt.
                return gaugeWidth(gauge) + 20
            case .count(let q):
                // standingCounted: the queue rides as one more segment on the gauge atoms
                // (gap 6 + segment advance) — e.g. ✓3⚠4+5 → 123pt.
                return gaugeWidth(gauge) + 6 + segmentAdvance(digits: q.count)
            }
        }
    }

    /// The transition decision for one render.
    public struct Plan: Equatable, Sendable {
        /// Cells whose fact changed — they must repaint (instantly or fading).
        public let changed: Set<Cell>
        /// The subset that crossfades 120ms — cross-state changes ONLY (rule b/c). The glyph
        /// cell here carries the ink↔danger critical transition when isCritical crossed (rule
        /// c) — no separate marker; isCritical is part of the glyph fact. Equal-digit value
        /// ticks are in `changed` but never here (rule a: instant).
        public let fades: Set<Cell>

        /// No cell's fact changed, so the plan carries no motion and no cell-level repaint.
        /// (The caller still rebuilds the collapsed pill via the ordinary 0ms hard-cut swap on
        /// such a render — a single frame, visually identical, so no motion is witnessed; the
        /// invariant is "no MOTION where no fact changed," not "no rebuild.")
        public var isNoop: Bool { changed.isEmpty }
        /// No cell crossfades → the whole render is today's 0ms single-frame swap.
        public var isInstant: Bool { fades.isEmpty }

        public init(changed: Set<Cell>, fades: Set<Cell>) {
            self.changed = changed
            self.fades = fades
        }
    }

    /// Diff two fingerprints into a plan. `nil` previous (first render / returning from
    /// the expanded island or a surface rebuild) → instant full paint: the morph animates
    /// only between two pill states that were both actually on screen.
    public static func plan(from old: Fingerprint?, to new: Fingerprint) -> Plan {
        guard let old else {
            return Plan(changed: Set(Cell.allCases), fades: [])
        }
        guard old != new else {
            // The invariant's ground case: no fact changed → no motion, no repaint.
            return Plan(changed: [], fades: [])
        }
        var changed: Set<Cell> = []
        var fades: Set<Cell> = []
        if old.stalePrefix != new.stalePrefix {
            changed.insert(.prefix)
            fades.insert(.prefix)   // degraded-reading arrival/clearing is a state crossing
        }
        if old.glyph != new.glyph {
            changed.insert(.glyph)
            fades.insert(.glyph)    // ink↔danger critical crossings ride this same glyph fade (rule c)
        }
        if old.value != new.value {
            changed.insert(.value)
            if !isEqualDigitTick(from: old.value, to: new.value) {
                fades.insert(.value)   // digit-count change / count↔gauge / structure change
            }
        }
        return Plan(changed: changed, fades: fades)
    }

    /// Rule (a), as the review clarified it and the D-pill config extends it: ANY equal-digit
    /// count tick is instant — a same-digit needs-you count (3→4), a gauge whose segment
    /// STRUCTURE is unchanged with only the numbers ticking (✓2→✓1), AND a standing tier
    /// whose gauge structure, queue-print case, and every digit count are unchanged. Any
    /// STRUCTURE change (a segment appears, the queue arrives/departs, mark↔count) is a
    /// cross-state change that fades the whole value cell — today's gauge grammar, extended
    /// to the composed tier (NO per-segment engine).
    static func isEqualDigitTick(from old: Value, to new: Value) -> Bool {
        switch (old, new) {
        case (.count(let a), .count(let b)):
            return a.count == b.count
        case (.gauge(let a), .gauge(let b)):
            return gaugeStructureTick(a, b)
        case (.standing(let ga, let qa), .standing(let gb, let qb)):
            return gaugeStructureTick(ga, gb) && queuePrintTick(qa, qb)
        default:
            return false
        }
    }

    /// Same gauge structure (states, order, per-segment digit count) with only the numbers
    /// possibly ticking — the instant-tick predicate shared by `.gauge` and `.standing`.
    private static func gaugeStructureTick(_ a: [GaugeSegmentPrint], _ b: [GaugeSegmentPrint]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy {
            $0.state == $1.state && $0.count.count == $1.count.count
        }
    }

    /// A queue-print is an instant tick only within the SAME case: mark↔mark (no digits),
    /// or count↔count with equal digit counts. mark↔count is a structure change → fade.
    private static func queuePrintTick(_ a: QueuePrint, _ b: QueuePrint) -> Bool {
        switch (a, b) {
        case (.mark, .mark):                 return true
        case (.count(let x), .count(let y)): return x.count == y.count
        default:                             return false
        }
    }
}
