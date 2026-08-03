import Foundation

/// WP-3d′ — the caught-up affirmation (D-copy `voice-plainspoken` AS AMENDED, ratified
/// 2026-07-06). Pure: which affirmation the expanded island renders, in which tense,
/// gated how — so the trust-critical rules are headlessly tested and the view just inks
/// whatever this returns.
///
/// The four rules, all load-bearing:
///
/// 1. **The radar-confirmation gate (fix round, trust major 1a).** The affirmation renders
///    ONLY when the RADAR lane has a confirmed read behind it — `radarConfirmed`, which the
///    app model flips on a live radar success (or a snapshot whose radar lane genuinely
///    succeeded last session). NOT the looser `hasData`: a pulse-only snapshot (the inbox
///    fetch failed all session while GraphQL succeeded → `radar: []`,
///    `lastRadarSuccessAt: nil`) paints data and sets `hasData`, but affirming "caught up"
///    off it would claim an inbox githud has never once read, anchored to a pulse-lane age.
///
/// 2. **The live-work rule, shared with the pill.** "Caught up" means the radar is empty
///    AND the pulse has no LIVE rows — computed over `PulsePresenter.sections(for:).active`,
///    the ONE presenter home of the rule (WP-6a dedupe). A stale/draft-only pulse is
///    spoken as caught-up by the pill ("You're all caught up") and must read the same
///    here; the default-off subsections still render their own honest content below.
///
/// 3. **The tense rule (the BINDING amendment).** Under ANY degraded freshness the
///    affirmation leaves the present tense — "All caught up as of {age} ago" — because a
///    cold-launch snapshot paint is ALWAYS `.stale` (`FreshnessModel.forSnapshot`): a
///    present-tense "You're all caught up" over a reading that may be minutes dead is a
///    fabricated state. "You're all caught up" + "right now" render ONLY under `.fresh`.
///
/// 4. **The age-0 guard (fix round, trust major 1b — the pill's own rule, mirrored).**
///    A degraded reading whose `ageSeconds == 0` means NO success time was ever recorded;
///    naming an age there ("as of 1s ago") would fabricate an update that never happened.
///    The degraded line stays past-anchored but time-free: "…as of the last check".
///    Same guard + rationale as `PillAccessibilityPresenter`'s degraded prefix.
///
/// Exactly ONE treatment per state — the full-caught-up BLOCK or the with-PRs HEADER
/// phrase, never both, and never per-lane filler (the placeholder stays banned).
public enum CaughtUpPresenter {
    /// The one affirmation line — shared with the pill's spoken clear value
    /// (`PillAccessibilityPresenter`) so the two surfaces can never drift.
    public static let caughtUpLine = "You're all caught up"
    /// The clear-LOOKING-but-unconfirmed spoken line (ratified A2, 2026-07-21): the pill
    /// and glyph must never speak the earned affirmation over a reading whose lanes were
    /// not all confirmed read — the same gate `display` enforces visually by silence.
    public static let unconfirmedClearLine = "Clear so far — not every source confirmed yet"
    /// Line 2 of the fresh block. "right now" is freshness-gated by construction: this
    /// string appears only in the `.fresh` branch below.
    public static let nothingNeedsYouLine = "Nothing needs you right now"

    /// What the expanded island renders for the caught-up question.
    public enum Display: Equatable, Sendable {
        /// Radar non-empty, or no confirmed radar read yet — no affirmation anywhere.
        case none
        /// Fully caught up (radar empty + no live PRs): the centered affirmation block.
        /// Fresh → two lines; degraded → ONE as-of line (`line2 == nil`) beside the
        /// existing caution banner (which the view renders unchanged).
        case block(line1: String, line2: String?)
        /// Radar empty but live PRs exist: the header slot (today the bare wordmark)
        /// carries the state; the "Your PRs" lane renders as today. Never a lane filler.
        case headerPhrase(String)
    }

    /// The decision. `rows`/`pulse` are the same presented rows the island renders;
    /// the live-rule derivation happens HERE (not in the view) so it cannot drift from
    /// the pill's own gauge input. `radarConfirmed` is rule 1's gate — the model's
    /// radar-lane confirmation, never the looser painted-data fact.
    public static func display(rows: [RadarRow], pulse: [PulseRow],
                               radarConfirmed: Bool, freshness: Freshness,
                               inboundActive: Int = 0, inboundConfirmed: Bool = false,
                               reviewsConfirmed: Bool = false) -> Display {
        // The standing inbound queue gates BOTH affirmation forms (WP 2026-07-09-001):
        // "you're all caught up" beside a contributor who has waited since December is a
        // fabricated state — the same trust sin the radar-confirmed gate closes, arriving
        // through a different door. And `inboundConfirmed` is that gate's own symmetry
        // (review round 1, trust MAJOR): an empty queue counts ONLY once a COMPLETE sweep
        // has actually read it — a failed/unresolved/incomplete first sweep leaves an
        // empty-looking lane that was never read, exactly the never-affirm-an-unread-inbox
        // rule one lane over. Fail-closed default: an un-updated caller can never affirm.
        // `reviewsConfirmed` (WP 2026-07-17-002) is the same symmetry for the reviews-owed
        // standing sweep: `rows.isEmpty` already counts synthetic review rows (they merge
        // into the ONE radar array), but zero rows over a sweep that never completed is an
        // unread state — never affirmed. Same fail-closed default.
        guard radarConfirmed, rows.isEmpty, inboundActive == 0, inboundConfirmed,
              reviewsConfirmed else { return .none }
        let liveRows = PulsePresenter.sections(for: pulse).active
        // Rule 4: age 0 on a degraded reading ⇔ no recorded success time — the phrase
        // stays past-anchored ("as of …") but never names a fabricated timestamp.
        let asOf: String?
        switch ageSeconds(freshness) {
        case .none: asOf = nil                                          // fresh
        case .some(let age) where age > 0: asOf = "as of \(FreshnessModel.ageText(age)) ago"
        case .some: asOf = "as of the last check"                       // degraded, time unknown
        }
        if liveRows.isEmpty {
            if let asOf {
                // Degraded: one line, past-anchored — the amendment. The caution banner
                // composes above it; the block itself never claims the present.
                return .block(line1: "All caught up \(asOf)", line2: nil)
            }
            return .block(line1: caughtUpLine, line2: nothingNeedsYouLine)
        }
        if let asOf {
            return .headerPhrase("Caught up \(asOf)")
        }
        return .headerPhrase("All caught up")
    }

    /// The degraded reading's age, `nil` when fresh. Both degraded cases carry
    /// `ageSeconds`, so every "as of {age} ago" string is buildable with no new plumbing
    /// (the D-copy review verified this). Ages format via `FreshnessModel.ageText` —
    /// the same vocabulary the caution banner speaks.
    static func ageSeconds(_ freshness: Freshness) -> Int? {
        switch freshness {
        case .fresh: return nil
        case .stale(let age): return age
        case .failing(_, let age): return age
        }
    }
}
