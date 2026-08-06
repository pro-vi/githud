import Foundation

/// A display-ready pulse row (pure data — no AppKit), so the "Your PRs" lane can be
/// unit-tested headlessly and the view layer stays dumb. Mirrors `RadarRow`. `Codable` so
/// the last-good lane survives a relaunch (see `SnapshotStore`).
public struct PulseRow: Sendable, Equatable, Codable {
    /// STABLE row identity — "owner/repo#7" (D-reveal amendment 2, WP-3d′): the peek stash
    /// keys on this, mirroring `RadarRow.id`. Constant for the PR's whole life, unlike its
    /// state/subtitle. (The `url` would also be stable for a PR, but the stash key is the
    /// same NAMED concept on both row types — never the url, per the amendment.)
    public let id: String
    public let repo: String         // "owner/repo #7"
    public let title: String        // the PR title
    public let subtitle: String     // "CI passing · approved" — the age is NOT baked in
    public let timestamp: String    // ISO8601 updatedAt — the age is formatted AT RENDER from this
    public let state: PulseState    // the rollup verdict (drives the glyph + tint)
    public let symbolName: String   // SF Symbol for the state
    public let url: String          // Open-on-GitHub
    public let isDraft: Bool        // grouping fact — drafts go in their own (default-off) subsection
    public let isStale: Bool        // grouping fact — untouched > staleAfter: a rotting PR drops to the (default-off) Stale group, OUT of the live glance
    public let isFresh: Bool        // just-raised (opened ≤ freshWithin) — floats to the top of the live lane (position only; no novelty chrome — consult RUBRIC #attention-non-theft)
    public let merge: MergeState    // raw mergeability — a `.conflicting` PR gets GitHub's own conflict glyph
    /// Per-row change signature over the displayed texts + their age source + the rollup
    /// state (see `RadarRow.changeSignature` — same rule): a changed signature drops the
    /// row's open peek, because the content is new and must re-truncate honestly.
    public let changeSignature: String
}

/// The collapsed-pill gauge over your non-draft open PRs, for when the H1 inbox is clear
/// (the "living gauge" — H2's thesis). Counts the two ACTIONABLE extremes — ready (merge
/// it) and blocked (fix it) — which the pill renders as count-matched segments
/// (✓ready · ⚠blocked): good news leads, the real backlog follows. `waiting` is in-flight
/// (not your move) so it stays out of the glance UNLESS it's the only state present.
public struct PulseGauge: Sendable, Equatable {
    public let ready: Int
    public let blocked: Int
    public let waiting: Int

    /// Pill segments in display order: ready ✓, then blocked ⚠; or a lone waiting ◔ if
    /// nothing is ready/blocked. Each renders as a themed glyph + count.
    public var segments: [(state: PulseState, count: Int)] {
        var s: [(state: PulseState, count: Int)] = []
        if ready > 0 { s.append((.ready, ready)) }
        if blocked > 0 { s.append((.blocked, blocked)) }
        if s.isEmpty && waiting > 0 { s.append((.waiting, waiting)) }
        return s
    }
}

/// The "Your PRs" lane split into its three rendered groups. `active` is the live glance
/// (always shown); `stale` (rotting, untouched 14d+) and `drafts` are default-off
/// subsections. Pre-sorted by `PulsePresenter.sections`.
public struct PulseSections: Sendable, Equatable {
    public let active: [PulseRow]
    public let stale: [PulseRow]
    public let drafts: [PulseRow]

    /// The regions the OWNER LENS governs, with the `showDrafts` pref already applied — the one
    /// home for WP 2026-07-26-001's rule that the pref gates at the caller. "At the caller" had
    /// become "in every caller": five sites (the island, the key walk, both chooser doors, the
    /// probe) each wrote `showDrafts ? drafts : []`, so there were five chances to omit it and
    /// omitting is silent — drafts leak into a surface with the pref off.
    ///
    /// Returns `live` untouched so a call site reads as one destructure.
    ///
    /// NO `showStale:` PARAMETER, and that is the load-bearing decision of WP 2026-07-29-001 —
    /// not an oversight. The two prefs gate at DIFFERENT LAYERS because the two regions have
    /// different grammars:
    ///
    ///   • `showDrafts` gates the lens's INPUT (here). Drafts have no collapsed caption — the
    ///     ratified asymmetry is that hidden drafts stay FULLY invisible — so "hidden" and
    ///     "absent" mean the same thing, and `[]` is exactly right.
    ///   • `showStale` gates the group's RENDERING (in the view). Quiet's whole grammar is that
    ///     it LEAVES A COUNT BEHIND: "2 gone quiet (show)" is both the honesty and the
    ///     affordance. Gate its input and a quiet-only owner would vanish along with its count,
    ///     which breaks fold-not-filter.
    ///
    /// So `sections.stale` is passed to `lensLayout` separately and unconditionally.
    public func lensRegions(showDrafts: Bool) -> (live: [PulseRow], drafts: [PulseRow]) {
        (live: active, drafts: showDrafts ? drafts : [])
    }
}

/// Turns pulses into glanceable rows. Relative age uses an injected `now` (shared
/// with `RadarPresenter`) so it is deterministic in tests. Mirrors `RadarPresenter`.
public enum PulsePresenter {
    /// SF Symbol conveying the *rollup state* (the shape carries the verdict; the view
    /// tints it per the color doctrine: blocked=danger, ready=success, waiting/draft=ink).
    public static func symbolName(for state: PulseState) -> String {
        switch state {
        case .blocked: return "exclamationmark.triangle.fill"
        case .ready:   return "checkmark.circle.fill"
        case .waiting: return "clock.fill"
        case .draft:   return "pencil.circle"
        }
    }

    /// CI member label — ALWAYS shown (it's the most informative member, and "no
    /// checks" must never read as "passing").
    static func ciLabel(_ ci: CIState) -> String {
        switch ci {
        case .passing: return "CI passing"
        case .failing: return "CI failing"
        case .pending: return "CI running"
        case .none:    return "no checks"
        }
    }

    /// Review member label — shown only when there's a decision (`.none` = no review
    /// required → omitted to keep the subtitle tight).
    static func reviewLabel(_ review: ReviewState) -> String? {
        switch review {
        case .approved:         return "approved"
        case .changesRequested: return "changes requested"
        case .reviewRequired:   return "review required"
        case .none:             return nil
        }
    }

    /// Merge member label — shown only when it's a *problem or unknown* (`mergeable`
    /// is implied by a `ready` verdict; naming it every time is noise). Conflicts and
    /// "checking…" are always surfaced, so the rollup is never opaque about them.
    static func mergeProblemLabel(_ merge: MergeState) -> String? {
        switch merge {
        case .mergeable:   return nil
        case .conflicting: return "conflicts"
        case .unknown:     return "checking…"
        }
    }

    /// The composition members (CI · review · merge-problem · draft) — WITHOUT the age, which
    /// is appended at render from the row's `timestamp` (see `displaySubtitle`), so a long-lived
    /// row never shows a stale "· 2h".
    public static func subtitle(for pulse: PullRequestPulse) -> String {
        var parts: [String] = [ciLabel(pulse.ci)]
        if let review = reviewLabel(pulse.review) { parts.append(review) }
        if let merge = mergeProblemLabel(pulse.merge) { parts.append(merge) }
        if pulse.isDraft { parts.append("draft") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Liveness (the second sort axis: age changes what `blocked` MEANS)
    //
    // A 4-month-old blocked PR (CI failing, conflicts) is not "your urgent move" — it's
    // *rotting*. State alone can't tell a fresh block ("CI just failed, fix it") from a
    // dead one. So liveness partitions the lane BEFORE state sorts within it:
    //   stale  — non-draft, untouched > `staleAfter`  → the rotting backlog (default-off group)
    //   fresh  — opened ≤ `freshWithin`                → just-raised, floats to the top of the live lane
    // Both are pure functions of (timestamps × now), so the whole split is fixture-testable.

    /// Untouched longer than this → stale (drops out of the live glance into the Stale group).
    /// 14d is grounded in the live data: a clean gap separates this-week work from the
    /// months-old backlog (consult the design probe). Drafts are NEVER stale (their own group).
    public static let staleAfter: TimeInterval = 14 * 86_400
    /// Opened within this → "just-raised" (your agent just cut the PR) → top of the live lane.
    /// 4h ≈ "this work session" — tight enough to mean *recent*, loose enough to survive a
    /// coffee break. Position is the only cue (no badge): novelty chrome is the named enemy.
    public static let freshWithin: TimeInterval = 4 * 3_600

    /// Age in seconds from an ISO8601 stamp. Unparseable → `.infinity` (treated as old:
    /// never "fresh"; a non-draft with an unparseable updatedAt is conservatively stale).
    /// Parses with `RadarPresenter`'s formatter — one `ISO8601DateFormatter` for the module.
    static func ageSeconds(fromISO8601 string: String, now: Date) -> TimeInterval {
        guard let date = RadarPresenter.date(fromISO8601: string) else { return .infinity }
        return max(0, now.timeIntervalSince(date))
    }

    /// Rotting: a non-draft PR with no activity in `staleAfter`. Drafts are excluded — they
    /// already have their own intentional group ("ignore me, WIP" ≠ "forgotten").
    public static func isStale(_ pulse: PullRequestPulse, now: Date) -> Bool {
        !pulse.isDraft && ageSeconds(fromISO8601: pulse.updatedAt, now: now) > staleAfter
    }
    /// Just-raised: opened within `freshWithin`. (A fresh PR can still be stale-by-update?
    /// No — created ≤ updated, so fresh ⇒ recently updated ⇒ never stale.)
    public static func isFresh(_ pulse: PullRequestPulse, now: Date) -> Bool {
        ageSeconds(fromISO8601: pulse.createdAt, now: now) <= freshWithin
    }

    public static func row(for pulse: PullRequestPulse, now: Date) -> PulseRow {
        let subtitleText = subtitle(for: pulse)
        return PulseRow(
            id: "\(pulse.repo)#\(pulse.number)",
            repo: "\(pulse.repo) #\(pulse.number)",
            title: pulse.title,
            subtitle: subtitleText,
            timestamp: pulse.updatedAt,
            state: pulse.state,
            symbolName: symbolName(for: pulse.state),
            url: pulse.url,
            isDraft: pulse.isDraft,
            isStale: isStale(pulse, now: now),
            isFresh: isFresh(pulse, now: now),
            merge: pulse.merge,
            // Same rule + separator as RadarPresenter.changeSignature; the rollup state
            // rides along for safety even though every state change also renames a
            // subtitle member (the honesty mappers keep the subtitle composition visible).
            changeSignature: [pulse.title, subtitleText, pulse.updatedAt,
                              pulse.state.rawValue].joined(separator: "\u{1f}")
        )
    }

    /// The full "Your PRs" subtitle line the island renders — "repo · <subtitle> · age" — with
    /// the age formatted AT RENDER from the row's `timestamp` (never baked). Mirrors
    /// `RadarPresenter.displaySubtitle`; the view calls it with `Date()`, tests with an injected
    /// `now` (so the shown string is a pure, testable function — no stale baked age possible).
    public static func displaySubtitle(for row: PulseRow, now: Date) -> String {
        RadarPresenter.displayLine(repo: row.repo, subtitle: row.subtitle,
                                   timestamp: row.timestamp, now: now)
    }

    /// The coarse displayed-age bucket per pulse row — see `RadarPresenter.ageSignature`. The
    /// scheduler re-renders the lane when this flips (a real age change), never otherwise.
    public static func ageSignature(for rows: [PulseRow], now: Date) -> [String] {
        RadarPresenter.ageSignature(forTimestamps: rows.map(\.timestamp), now: now)
    }

    /// The lane split into its three groups (each pre-sorted). The view renders `active`
    /// always, `stale`/`drafts` as default-off subsections. This is the single source of
    /// truth for ordering — `rows(for:)` is just these three concatenated.
    public static func sections(for pulses: [PullRequestPulse], now: Date) -> PulseSections {
        // Worst-first within a tier, newest-first as tiebreak — the proven glance order,
        // now HONEST because stale PRs were partitioned out before it runs.
        func stateThenUpdated(_ a: PullRequestPulse, _ b: PullRequestPulse) -> Bool {
            a.state.sortWeight != b.state.sortWeight ? a.state.sortWeight > b.state.sortWeight
                                                     : a.updatedAt > b.updatedAt
        }
        let drafts = pulses.filter { $0.isDraft }.sorted(by: stateThenUpdated)
        let nonDraft = pulses.filter { !$0.isDraft }
        // Stale: most-recently-touched first (likeliest to still matter / be worth closing).
        let stale = nonDraft.filter { isStale($0, now: now) }.sorted { $0.updatedAt > $1.updatedAt }
        // Active: just-raised float to the very top (newest-raised first, a fresh block still
        // leading a fresh wait), then the normal worst-first glance over the rest.
        let active = nonDraft.filter { !isStale($0, now: now) }.sorted { a, b in
            let af = isFresh(a, now: now), bf = isFresh(b, now: now)
            if af != bf { return af }                                  // fresh before settled
            if af {                                                    // both just-raised…
                return a.state.sortWeight != b.state.sortWeight ? a.state.sortWeight > b.state.sortWeight
                                                                : a.createdAt > b.createdAt   // …newest-raised first
            }
            return stateThenUpdated(a, b)                              // both settled → glance order
        }
        return PulseSections(active: active.map { row(for: $0, now: now) },
                             stale:  stale.map  { row(for: $0, now: now) },
                             drafts: drafts.map { row(for: $0, now: now) })
    }

    /// Flat, fully-ordered rows: active (live) → stale → drafts. The view/pill regroup by
    /// the `isStale`/`isDraft` flags each row carries, so the pipeline stays a simple
    /// `[PulseRow]` while the ordering + grouping live here (pure + testable).
    public static func rows(for pulses: [PullRequestPulse], now: Date) -> [PulseRow] {
        let s = sections(for: pulses, now: now)
        return s.active + s.stale + s.drafts
    }

    /// The lane split for ALREADY-PRESENTED rows — regroups by the `isDraft`/`isStale`
    /// facts each `PulseRow` already carries (computed once in `row(for:)`), preserving
    /// input order within each group (so a flat, pre-ordered `[PulseRow]` round-trips to
    /// active→stale→drafts unchanged). THE single home of the live-work rule
    /// (`active` = `!isDraft && !isStale`, the live glance) that every view surface AND the
    /// collapsed pill's accessibility value consume — so the drawn pill, the expanded lane,
    /// and the spoken value can never drift from one another. (The pipeline's
    /// `sections(for:now:)` above is where the flags are first COMPUTED from timestamps +
    /// sorted; this is where the presented rows are REGROUPED for display. The transport
    /// between them stays a flat `[PulseRow]`, so nothing in the poll/snapshot spine changes.)
    public static func sections(for rows: [PulseRow]) -> PulseSections {
        PulseSections(active: rows.filter { !$0.isDraft && !$0.isStale },
                      stale:  rows.filter { !$0.isDraft && $0.isStale },
                      drafts: rows.filter { $0.isDraft })
    }

    /// The pill gauge: ready/blocked/waiting counts over the rows the pill holds (the
    /// caller passes non-draft rows — drafts never enter the calm glance). `nil` when
    /// there are no PRs (pill falls back to its bare-check state).
    public static func gauge(rows: [PulseRow]) -> PulseGauge? {
        guard !rows.isEmpty else { return nil }
        var ready = 0, blocked = 0, waiting = 0
        for row in rows {
            switch row.state {
            case .ready:   ready += 1
            case .blocked: blocked += 1
            case .waiting: waiting += 1
            case .draft:   break   // excluded from the glance (caller also filters)
            }
        }
        if ready == 0 && blocked == 0 && waiting == 0 { return nil }
        return PulseGauge(ready: ready, blocked: blocked, waiting: waiting)
    }


    /// Change-detection signature for a pulse set: every presentation-affecting field, NOT
    /// just the rolled-up state — so a draft→non-draft flip (which moves a PR between the
    /// hidden Drafts group and the live "Your PRs" lane) OR a CI/review/merge change that
    /// doesn't alter the verdict still re-renders. A blocked draft becoming a blocked
    /// non-draft (state unchanged) was the silent-miss the coarse key caused. Excludes the
    /// derived relative age, like the radar key. Pure + testable.
    public static func changeKey(for pulses: [PullRequestPulse]) -> [String] {
        pulses.map {
            ["\($0.repo)#\($0.number)", $0.state.rawValue, String($0.isDraft),
             $0.ci.rawValue, $0.review.rawValue, $0.merge.rawValue, $0.title,
             $0.createdAt, $0.updatedAt]
                .joined(separator: "\u{1f}")
        }
    }
}
