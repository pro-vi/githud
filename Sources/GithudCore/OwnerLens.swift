import Foundation

// The OWNER LENS (WP 2026-07-14-001, widened by 2026-07-26-001 and 2026-07-29-001) — the
// second, self-contained half of what `PulsePresenter.swift` used to carry. Nothing here is
// renamed or re-scoped: the layout lives in an `extension PulsePresenter`, so every member
// keeps its exact spelling (`PulsePresenter.lensLayout`, `PulsePresenter.OwnerBucket`,
// `PulsePresenter.LensLayout.empty`) and no call site moved. The other half of that file
// stays what it always was: turning one pulse into one row.

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

extension PulsePresenter {
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
        return rows.filter { (RadarPresenter.date(fromISO8601: $0.timestamp) ?? .distantPast) > since }.count
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
        return RadarPresenter.displayLine(repo: repoSansOwner(of: row), subtitle: row.subtitle,
                                          timestamp: row.timestamp, now: now)
    }
}
