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

/// One entry of the owner-lens layout over ALL THREE regions of "Your PRs", in exact
/// render order (WP 2026-07-14-001, widened by 2026-07-26-001 and 2026-07-29-001). The lens
/// layers AFTER `sections(for:)`, which still owns the live/quiet/draft split. Two orthogonal
/// preferences drive it: shape (`groupByOwner`: titled groups vs the one flat list) and who
/// leads (`foldedOwners`, applied in BOTH shapes — the ratified amendment). A folded owner is
/// never dropped: it compresses to a `.ledger` line whose count always prints.
public enum LensEntry: Sendable, Equatable {
    /// Flat-shape leading rows, original active order (owner prefixes stay on rows).
    case rows([PulseRow])
    /// Grouped-shape owner group: `title` is "yours" or the owner as first-cased in the
    /// data; rows under a title render with the owner prefix elided (the title said it).
    ///
    /// `drafts` (WP 2026-07-26-001) is the owner's own WIP; `quiet` (WP 2026-07-29-001) is its
    /// rotting backlog. Both are subordinate rows that belong to this owner but are never peers
    /// of `rows`: they render after them POSITIONALLY, drafts then quiet, and never join their
    /// state sort. That positional rule is the 2026-06-18 inversion guard restated at group
    /// scope (a draft with failing CI rolls up `.blocked`, and so does a conflicted 16-week PR;
    /// merging either into the sort would float it above live work — see the signal-taxonomy
    /// plan). Named per region, not `tail`, because there are two of them and this file already
    /// calls the >2-folded merge "the tail valve".
    ///
    /// The payload order IS the render order. What differs per tail is the CHROME, and that is
    /// the view's business: drafts wear a bare count label (the ratified no-caption asymmetry —
    /// hidden means invisible), quiet wears a collapsed caption that IS its affordance ("2 gone
    /// quiet (show)"). That per-region difference is exactly why this is three named payloads
    /// and not a uniform `[Region: [PulseRow]]` map.
    case group(owner: String, title: String, rows: [PulseRow],
               drafts: [PulseRow], quiet: [PulseRow])
    /// A folded owner's ledger line — counts + activity-since-last-opened. `owner == nil`
    /// is the merged "elsewhere" line (>2 folded owners); its click opens the lens card.
    /// `draftCount` and `quietCount` are the folded tails' sizes: a fold hides an owner's
    /// drafts and its quiet along with its live rows, so the line must admit all three
    /// (fold, not filter). `fresh` stays LIVE-only — neither a draft you opened yourself nor
    /// a PR that has been rotting for a fortnight is work that just arrived.
    case ledger(owner: String?, title: String, count: Int, draftCount: Int,
                quietCount: Int, fresh: Int)
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

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    /// Age in seconds from an ISO8601 stamp. Unparseable → `.infinity` (treated as old:
    /// never "fresh"; a non-draft with an unparseable updatedAt is conservatively stale).
    static func ageSeconds(fromISO8601 string: String, now: Date) -> TimeInterval {
        guard let date = iso.date(from: string) else { return .infinity }
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
        let age = RadarPresenter.age(fromISO8601: row.timestamp, now: now)
        return [row.repo, row.subtitle, age.isEmpty ? nil : age]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The coarse displayed-age bucket per pulse row — see `RadarPresenter.ageSignature`. The
    /// scheduler re-renders the lane when this flips (a real age change), never otherwise.
    public static func ageSignature(for rows: [PulseRow], now: Date) -> [String] {
        rows.map { RadarPresenter.age(fromISO8601: $0.timestamp, now: now) }
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

    // MARK: - Owner lens (WP 2026-07-14-001)

    /// The row's repo owner — the prefix of `repo` ("owner/repo #7") before the first
    /// slash. This is the ONE derivation (authority: GraphQL `nameWithOwner`); malformed
    /// input (no slash) degrades to the whole string — stable grouping, never a crash.
    public static func owner(of row: PulseRow) -> String {
        if let slash = row.repo.firstIndex(of: "/") { return String(row.repo[..<slash]) }
        return row.repo
    }

    /// The repo token with the owner elided — "repo #7" — for rows under an owner title
    /// (the title said it; repeating it per row is the ink the titles pay for).
    public static func repoSansOwner(of row: PulseRow) -> String {
        if let slash = row.repo.firstIndex(of: "/") {
            return String(row.repo[row.repo.index(after: slash)...])
        }
        return row.repo
    }

    /// Group title: the viewer's own login reads as "yours" (case-insensitive; GitHub's
    /// rule). No login yet (auth in flight) → the raw owner, honestly.
    public static func lensTitle(owner: String, selfLogin: String?) -> String {
        if let login = selfLogin, owner.lowercased() == login.lowercased() {
            return PlainWords.yoursTitle
        }
        return owner
    }

    /// Rows with activity since this machine last opened the owner's group (keys are
    /// lowercased owners). Never-opened → 0, not all — a fold you never looked at
    /// shouldn't shout. Unparseable timestamps count as old (never "new").
    static func freshCount(rows: [PulseRow], since: Date?) -> Int {
        guard let since else { return 0 }
        return rows.filter { (iso.date(from: $0.timestamp) ?? .distantPast) > since }.count
    }

    /// The effective owner display order (dogfood 2026-07-14: drag-to-reorder): the
    /// user's placed owners first, in their order; unplaced owners after, in discovery
    /// (lead-row) order. One rule for the lane's groups, the ledger lines, the card's
    /// rows, and the gear submenu — the four surfaces can never disagree.
    static func lensOrderedKeys(_ discovery: [String], prefs: LensPreferences) -> [String] {
        func rank(_ key: String) -> (Int, Int) {
            if let placed = prefs.ownerOrder.firstIndex(of: key) { return (0, placed) }
            return (1, discovery.firstIndex(of: key) ?? discovery.count)
        }
        return discovery.sorted { rank($0) < rank($1) }
    }

    /// One owner's share of the lane, across all three regions: its LIVE rows (the glance), its
    /// DRAFT tail (subordinate WIP) and its QUIET tail (the rotting backlog). All three keep their
    /// input order — this type only partitions, never sorts.
    public struct OwnerBucket: Sendable, Equatable {
        /// Lowercased login — the identity every lens pref keys on (GitHub's own rule).
        public let key: String
        /// First-seen display casing, for anything the user reads.
        public let owner: String
        public var live: [PulseRow] = []
        public var drafts: [PulseRow] = []
        public var quiet: [PulseRow] = []
    }

    /// Partition the lane's rows by owner in DISCOVERY ORDER: live owners first by lead-row rank,
    /// then owners seen only in drafts, then owners seen only in quiet. That ordering is a ratified
    /// decision — it is what sinks an unplaced tail-only owner below everyone with live work — and
    /// this is its ONE home.
    ///
    /// It was three. `lensLayout`, `LensChooser.make` and the probe each walked live-then-drafts by
    /// hand, each with its own spelling of the first-seen test, and each under a comment asserting
    /// it implemented "the one rule" — which made the comments load-bearing where a function should
    /// be. WP 2026-07-26-001 extended all three by hand; WP 2026-07-29-001 added a third region and
    /// extended this one function instead, which is the whole point of the extraction.
    ///
    /// Every returned bucket has at least one row in some region — buckets exist only because a row
    /// was seen. Downstream leans on that: the lone-header guard counts buckets, not live rows.
    public static func ownerBuckets(live: [PulseRow], drafts: [PulseRow],
                                    quiet: [PulseRow]) -> [OwnerBucket] {
        var order: [String] = []
        var buckets: [String: OwnerBucket] = [:]
        func key(for row: PulseRow) -> String {
            let display = owner(of: row)
            let k = display.lowercased()
            if buckets[k] == nil {
                order.append(k)
                buckets[k] = OwnerBucket(key: k, owner: display)
            }
            return k
        }
        for row in live { buckets[key(for: row)]?.live.append(row) }
        for row in drafts { buckets[key(for: row)]?.drafts.append(row) }
        for row in quiet { buckets[key(for: row)]?.quiet.append(row) }
        return order.compactMap { buckets[$0] }
    }

    /// The whole answer `lensLayout` computed: the entries in render order, the rows that stay
    /// TERMINAL in flat shape, and the shape decision itself.
    ///
    /// WHY A VALUE AND NOT A BARE ARRAY. `isGrouped(_:)` and `terminalDrafts(after:drafts:prefs:)`
    /// used to be public free functions that REBUILT an answer `lensLayout` already had, and every
    /// consumer had to remember to call them. That seam has bitten this WP twice (the flat shape ×
    /// the key walk). With a second terminal region it would double the forget-hazard: a consumer
    /// could render the drafts region and silently drop the quiet one, or the walk could compute
    /// one shape rule while the view computed another. Returning both sets in one value makes
    /// "half-consumed" unrepresentable — and both are `[]` when grouped, so a row can never have
    /// two homes.
    public struct LensLayout: Sendable, Equatable {
        /// Groups / rows / ledger lines, in exact render order.
        public let entries: [LensEntry]
        /// Flat shape only: the drafts that render as the terminal "Draft PRs" region,
        /// fold-filtered. `[]` when grouped — grouped shape already tails every group.
        public let terminalDrafts: [PulseRow]
        /// Flat shape only: the quiet rows that render as the terminal "gone quiet" family,
        /// fold-filtered. `[]` when grouped. NOTE the caller still decides whether to draw them
        /// as rows or as a collapsed caption — `showStale` gates rendering, not membership.
        public let terminalQuiet: [PulseRow]
        /// True when the layout wears owner titles. Carried from the shape decision, never
        /// re-inferred by scanning entries.
        public let isGrouped: Bool

        /// Nothing to lay out — the empty lane.
        static let empty = LensLayout(entries: [], terminalDrafts: [], terminalQuiet: [],
                                      isGrouped: false)
    }

    /// The owner-lens layout over ALL THREE of the lane's regions — call with `sections.active`,
    /// `sections.drafts` (gated on `showDrafts`, see `lensRegions`) and `sections.stale`
    /// (NEVER gated, see the same doc). Rules, in order:
    ///   • owners partition preserving input order; a group's rank = its lead LIVE row's rank
    ///     (the state sort is preserved at group granularity, never re-sorted within);
    ///   • leading content first — titled groups when `groupByOwner` AND ≥2 leading owners
    ///     with content (the lone-header guard), else one flat run;
    ///   • each group ends with its own `drafts` then its own `quiet` — positional, never merged
    ///     into the group's state sort (the 2026-06-18 inversion guard at group scope, now for
    ///     two tails: a blocked draft AND a conflicted 16-week row both sink);
    ///   • folded owners sink below as counted ledger lines carrying ALL THREE counts, in the
    ///     same rank order; more than two folded owners merge into one "elsewhere" line.
    ///
    /// THE GUARD COUNTS OWNERS, NOT LIVE OWNERS (dogfood 2026-07-29). It briefly counted only
    /// owners with LIVE rows, to hold an invariant that flipping `showDrafts` could never move
    /// the lane between grouped and flat. That invariant cost more than it bought: folding an
    /// owner until one live owner remained dropped the lane to flat, which silently un-grouped
    /// the drafts — the per-org feature turning itself off exactly when a user reached for the
    /// lens. Reported from the real lane ("in lens i disabled yours … in draft PRs i see other
    /// orgs still"). Now: two leading owners with content means titles, whichever regions their
    /// content came from. Accepted cost: revealing drafts can add titles to a one-live-owner lane.
    ///
    /// TAIL-ONLY OWNERS (WP 2026-07-26-001, ratified: "facebook should be there as an org")
    /// are first-class — they get a group with an empty live region. Among UNPLACED owners
    /// they sink below everyone with live work; a `ownerOrder` placement still outranks
    /// everything, so a tail-only owner the user dragged up genuinely leads. WP 2026-07-29-001
    /// extends that precedent to quiet: an org whose only rows are 16 weeks old still gets a
    /// title and a fold. That consistency is deliberate and named as the thing to watch.
    ///
    /// The caller gates `drafts` on the `showDrafts` pref: pass `[]` when drafts are hidden,
    /// so a folded ledger never claims drafts the pref is hiding lane-wide. `quiet` is NOT
    /// gated — its count must survive being hidden, or the collapsed caption has nothing to say.
    ///
    /// INVARIANT (fold, not filter): every input row — live, draft or quiet — appears exactly
    /// once, as a visible row, a tail row, a terminal row, or inside a ledger count, in BOTH
    /// shapes. In flat shape the tails are not emitted (a flat list has no groups to tail, same
    /// reason the drag order is a GROUP order); they come back as `terminalDrafts` /
    /// `terminalQuiet`, filtered through `leadingRows(_:prefs:)` so a folded owner's tails stay
    /// hidden and its ledger line stays honest. `lastOpened` keys are lowercased.
    public static func lensLayout(live: [PulseRow], drafts: [PulseRow], quiet: [PulseRow],
                                  prefs: LensPreferences, selfLogin: String?,
                                  lastOpened: [String: Date]) -> LensLayout {
        guard !live.isEmpty || !drafts.isEmpty || !quiet.isEmpty else { return .empty }

        // Discovery + partition live in `ownerBuckets` (one home, three former copies). Its
        // order — live owners by lead-row rank, then draft-only, then quiet-only — is what lets
        // `lensOrderedKeys` sink an unplaced tail-only owner with no special case.
        let partition = ownerBuckets(live: live, drafts: drafts, quiet: quiet)
        let order = partition.map(\.key)
        let buckets = Dictionary(uniqueKeysWithValues: partition.map { ($0.key, $0) })

        let ordered = lensOrderedKeys(order, prefs: prefs)
        let leading = ordered.filter { prefs.leads($0) }
        let folded = ordered.filter { prefs.isFolded($0) }
        var entries: [LensEntry] = []

        // The lone-header guard counts leading owners with ANY content. Every bucket exists
        // because a row was seen, so `leading.count` IS that count — no filter needed.
        let isGrouped = prefs.groupByOwner && leading.count >= 2
        if isGrouped {
            // Grouped shape: groups follow the effective order (user's drag order, then
            // lead-row rank); rows inside each group keep the active sort untouched, and
            // the two tails follow them positionally, drafts before quiet.
            for key in leading {
                guard let bucket = buckets[key] else { continue }
                entries.append(.group(owner: bucket.owner,
                                      title: lensTitle(owner: bucket.owner, selfLogin: selfLogin),
                                      rows: bucket.live,
                                      drafts: bucket.drafts,
                                      quiet: bucket.quiet))
            }
        } else {
            // Flat shape stays state-sorted (the drag order is a GROUP order; a flat
            // list has no groups to order — and none to tail).
            let rows = leadingRows(live, prefs: prefs)
            if !rows.isEmpty { entries.append(.rows(rows)) }
        }

        // A fold hides an owner's tails along with its live rows, so the ledger counts all three.
        // `fresh` stays LIVE-only: "N new" means work that arrived. A draft you opened yourself
        // is not that, and neither is a PR that has been rotting for a fortnight — counting
        // either would leave a busy org permanently shouting.
        func ledgerEntry(_ keys: [String], owner: String?, title: String) -> LensEntry {
            var live = 0, drafts = 0, quiet = 0, fresh = 0
            for key in keys {
                guard let bucket = buckets[key] else { continue }
                live += bucket.live.count
                drafts += bucket.drafts.count
                quiet += bucket.quiet.count
                fresh += freshCount(rows: bucket.live, since: lastOpened[key])
            }
            return .ledger(owner: owner, title: title, count: live, draftCount: drafts,
                           quietCount: quiet, fresh: fresh)
        }
        if folded.count > 2 {
            entries.append(ledgerEntry(folded, owner: nil, title: PlainWords.lensElsewhereTitle))
        } else {
            for key in folded {
                guard let bucket = buckets[key] else { continue }
                entries.append(ledgerEntry([key], owner: bucket.owner,
                                           title: lensTitle(owner: bucket.owner, selfLogin: selfLogin)))
            }
        }

        // THE ONE HOME of the terminal-region rule. Grouped shape already tails every group, so a
        // terminal region would be a second, contradictory home for the same rows — empty. Flat
        // shape has no groups to tail, so its tails stay terminal, fold-filtered so a folded
        // owner's WIP and backlog hide with the rest of its work.
        //
        // Both sets are computed here, together, precisely so no consumer can produce one and
        // forget the other — the drift that two hand-written copies of this rule would guarantee,
        // each staying green against its own tests while disagreeing with the other.
        return LensLayout(entries: entries,
                          terminalDrafts: isGrouped ? [] : leadingRows(drafts, prefs: prefs),
                          terminalQuiet: isGrouped ? [] : leadingRows(quiet, prefs: prefs),
                          isGrouped: isGrouped)
    }

    /// Rows a lane may show: a folded owner's work is hidden and counted on its ledger line
    /// instead. Row-generic on purpose — the flat shape filters its LIVE run and BOTH terminal
    /// regions through the same call, so the fold rule really does have one spelling. (It had
    /// two: this predicate, and an inlined `foldedOwners.contains(owner(of:).lowercased())`
    /// thirty lines away inside the function whose doc claimed one home.)
    ///
    /// Internal, not public: only `lensLayout` calls it now. It went public when consumers had to
    /// rebuild the terminal region themselves; `LensLayout` hands them the answer instead, and a
    /// public fold predicate is just an invitation to compute a fourth copy of the shape rule.
    static func leadingRows(_ rows: [PulseRow], prefs: LensPreferences) -> [PulseRow] {
        rows.filter { !prefs.isFolded(owner(of: $0)) }
    }

    /// `displaySubtitle` with the owner prefix optionally elided (rows under an owner
    /// title). Same render-time age rule as the base form.
    public static func displaySubtitle(for row: PulseRow, now: Date, elideOwner: Bool) -> String {
        guard elideOwner else { return displaySubtitle(for: row, now: now) }
        let age = RadarPresenter.age(fromISO8601: row.timestamp, now: now)
        return [repoSansOwner(of: row), row.subtitle, age.isEmpty ? nil : age]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
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
