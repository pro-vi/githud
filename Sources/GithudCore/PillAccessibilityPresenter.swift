import Foundation

/// Builds the collapsed pill's `accessibilityValue` — from the SAME inputs
/// `CollapsedPillView` uses to choose its glyph, translated to speech. Pure (no AppKit),
/// so VoiceOver's actual announcement is unit-testable without a window server; the view
/// sets `setAccessibilityValue` to whatever this returns, every render.
///
/// The pill is the product's thesis surface (H1's "does GitHub need me right now?" made
/// glanceable) — WP-5i's contract calls it "currently mute" (a static "githud — expand"
/// label, never a value) and names this the gray-swap a11y law's ultimate test: if the
/// spoken value carries the same meaning the color/shape/count visuals do, the law holds
/// even for a user who can't see color at all.
///
/// Copy is D-copy `voice-plainspoken` AS AMENDED (ratified 2026-07-06, WP-3d′ sweep).
/// Priority mirrors the visual stack in `CollapsedPillView.init` exactly:
///  1. `loading` (no radar has landed yet — never fake "all clear") →
///     "githud — checking GitHub" (the value carries the wordmark itself; see
///     `StatusGlyphPresenter.toolTip`, which no longer re-prefixes it — that pair was
///     the old "githud — githud, loading" double wordmark)
///  2. `rows` non-empty → "<N> need(s) you" (+ ", including a security alert" when any
///     row `isCritical` — NAMES the one reserved emergency; the copy hard-couples to
///     `SignalClassifier.criticalReasons == {security_alert}`, tripwired in tests)
///  3. `rows` empty + an open-PR gauge exists (H2's "living gauge", non-draft/non-stale
///     PRs only, mirroring the pill's own filter) → "<ready> ready, <blocked> blocked"
///     (or "<waiting> waiting" when neither ready nor blocked is present)
///  4. otherwise → "You're all caught up" (`CaughtUpPresenter.caughtUpLine` — the same
///     affirmation the expanded island prints, one home so the surfaces can't drift)
/// A degraded `Freshness` reading prepends "Reading may be stale — updated {age} ago. "
/// to whichever of the above applies — mirroring the pill's stale-clock glyph, which
/// renders independent of the rest of the stack (color doctrine: `caution` marks a
/// degraded READING, never a data state, so it composes with every other case rather
/// than replacing one).
public enum PillAccessibilityPresenter {
    public static func value(rows: [RadarRow], pulse: [PulseRow] = [], freshness: Freshness = .fresh,
                              sweepFreshness: Freshness = .fresh,
                              loading: Bool = false, inboundActive: Int = 0,
                              style: PillStyle = .queueLeads,
                              clearConfirmed: Bool = false) -> String {
        // Walk the SAME resolved decision the drawn pill does (`PillMorph.resolve`), so the
        // spoken value can never claim a fact the pill doesn't draw, per style, in lockstep.
        let resolved = PillMorph.resolve(style: style, rows: rows, pulse: pulse,
                                         loading: loading, inboundActive: inboundActive,
                                         clearConfirmed: clearConfirmed)
        let body = bodyValue(resolved)
        // D1 — the prefix reads the SAME per-fact clock the drawn caution glyph does.
        let prefix = PillMorph.prefixFreshness(resolved, pollFreshness: freshness, sweepFreshness: sweepFreshness)
        guard prefix.isDegraded else { return body }
        // D-copy degraded prefix names the age (plainspoken: say when the reading is
        // from). ageSeconds == 0 on a degraded reading ⇔ NO success was ever recorded
        // (`.failing` can fire before the first success; a never-swept sweep clock too) —
        // naming an age there would fabricate an update that never happened, so age-free.
        if let age = CaughtUpPresenter.ageSeconds(prefix), age > 0 {
            return "Reading may be stale — updated \(FreshnessModel.ageText(age)) ago. \(body)"
        }
        return "Reading may be stale. \(body)"
    }

    /// The spoken body for a resolved pill state. Derived from the resolved fact (glyph +
    /// value + clock flags) so it stays in lockstep with what is drawn: a `.count` that is a
    /// sweep fact is the standing queue ("N waiting at your door"); a `.count` that is a poll
    /// fact is the needs-you radar ("N need you"). The composed tier speaks the gauge clause
    /// plus the queue clause — counted names the number, marked keeps STRICT count-free parity.
    private static func bodyValue(_ resolved: PillMorph.Resolved) -> String {
        switch resolved.value {
        case .none:
            if case .loading = resolved.glyph { return "githud — checking GitHub" }
            if case .checkUnconfirmed = resolved.glyph {
                return CaughtUpPresenter.unconfirmedClearLine   // never speak the earned affirmation
            }
            return CaughtUpPresenter.caughtUpLine   // bare check (the shared affirmation line)
        case .count(let text):
            if resolved.showsSweepFact { return doorClause(text) }   // the standing queue
            // Needs-you radar. ", including a security alert" NAMES the one reserved critical
            // (D-copy) — valid only while criticalReasons == {security_alert} (test tripwire).
            let critical: Bool
            if case .radar(_, let c) = resolved.glyph { critical = c } else { critical = false }
            let countPhrase = text == "1" ? "1 needs you" : "\(text) need you"
            return critical ? "\(countPhrase), including a security alert" : countPhrase
        case .gauge(let segments):
            return gaugeClause(segments)
        case .standing(let gauge, let queue):
            switch queue {
            case .count(let q):
                return "\(gaugeClause(gauge)). \(doorClause(q))"
            case .mark:
                // Strict count-free parity: the drawn mark carries no number, so neither
                // does the speech — "no one by count" is never "confirmed empty".
                return "\(gaugeClause(gauge)); people waiting at your door"
            }
        }
    }

    /// The living gauge clause, over the SAME `sections(for:).active` the drawn pill uses.
    private static func gaugeClause(_ segments: [PillMorph.GaugeSegmentPrint]) -> String {
        segments.map { "\($0.count) \(label(for: $0.state))" }.joined(separator: ", ")
    }

    private static func doorClause(_ count: String) -> String {
        count == "1" ? "1 waiting at your door" : "\(count) waiting at your door"
    }

    private static func label(for state: PulseState) -> String {
        switch state {
        case .ready:   return "ready"
        case .blocked: return "blocked"
        case .waiting: return "waiting"
        case .draft:   return "draft"   // unreachable — drafts are filtered out of the gauge input
        }
    }
}
