import Foundation

/// WP 2026-07-17-001 — the radar's READING: every piece of state the pipeline carries
/// between polls, with every policy decision as a pure transition (`PollReducer`'s
/// sibling: injected clock, no I/O, no queues). `RadarPipeline` is now only the
/// blocking-I/O shell around one instance of this — which puts the cache-invalidation
/// rules that produced this branch's real bugs (terminal-only verdict caching, the
/// 304 re-verify throttle, the one-shot re-projection latches) inside the test
/// runner's reach.
public struct RadarReading {
    /// The enriched thread cache — the recompute + re-verify baseline. Mutated only
    /// through the transitions below.
    public private(set) var threads: [NotificationThread] = []
    /// Conditional-GET validators, re-adopted on every 200 AND 304 (`PollPlan.from`
    /// keeps prior values when a 304 omits them — never overwrite with nil upstream).
    public private(set) var validators = PollValidators()
    /// Which reasons the user surfaces. A change re-computes off-network.
    public var preferences: SurfacePreferences = .auto
    public private(set) var selfLogin: String?
    public private(set) var selfResolved = false
    /// Repo scope from the last 200 — the re-verify pass reuses the same private-repo
    /// skip (a scope-blocked GET would just burn its timeout against the deadline).
    public private(set) var repoScope = false
    /// The inbound sweep's adopt baseline (incomplete searches never remove).
    public private(set) var inboundBaseline: InboundReading?
    /// The reviews-owed sweep's adopt baseline (WP 2026-07-17-002) — read surface kept
    /// here (pipeline + probe); the state itself lives in `standingReviews`.
    public var reviewsBaseline: InboundReading? { standingReviews.baseline }
    /// The 304 re-verify throttle clock — stamped on ATTEMPT, not on flip, so a verify
    /// that finds nothing still consumes its window.
    public private(set) var lastSubjectVerify = Date.distantPast

    // One-shot re-projection latches. Consumed TOGETHER (`consumeResolutions`) so the
    // old two-call fixed-order footgun (both had to be called every tick, no
    // short-circuit) is structurally impossible.
    private var selfJustResolved = false
    private var subjectJustResolved = false
    /// A read-check positively removed a thread this run — live thread truth exists
    /// even if the set is now empty (land-triage F2; see `consumeResolutions`).
    private var threadTruthVerified = false
    /// The standing reviews-owed SEARCH side, whole — see `StandingReviews` (bottom of
    /// this file). This reading keeps the THREAD side and the merge where both meet.
    private var standingReviews = StandingReviews()
    /// url → the unread thread's `updatedAt` while the search last owed it — the
    /// GENERATION a discharge binds to (land-verdict P1). Maintained at adopt time.
    private var owedThreadGen: [String: String] = [:]
    /// The session-scoped departure buffer (plan 2026-07-21-001, "Just cleared"): the
    /// last 8 rows that left "Needs you", newest first, with a reason ONLY when this
    /// reading actually knows it (read-check / discharge / verdict — a plain feed drop
    /// stays reason-less, never a guess). Surfaced-only capture; display-only downstream
    /// (never enters radar()/counts/affirmation); never persisted (session tense).
    public private(set) var recentlyCleared: [ClearedEntry] = []

    /// url → the bound generation a discharge applies to. A re-request re-notifies the
    /// SAME thread and bumps `updatedAt` past the binding, so the fresh ask surfaces
    /// even while the search index still lags — evidence discharges one generation,
    /// never the PR forever.
    private var dischargeBindings: [String: String] = [:]

    public init() {}

    // MARK: - fetch adoption

    /// Adopt a response's validators (200 and 304 alike — the 304 leg must stay
    /// conditional on the next tick too).
    public mutating func adoptValidators(_ next: PollValidators) {
        validators = next
    }

    /// Adopt a 200's decoded threads + scope. Enrichment happens after, through
    /// `applySubjectVerdict` / `cacheCommentAuthor` on the indices the targets name.
    public mutating func adopt200(threads: [NotificationThread], scopes: String?) {
        // Departure capture (plan 2026-07-21-001): surfaced threads absent from the new
        // feed left "Needs you" for a reason GitHub does not state — read elsewhere,
        // done, unsubscribed. Captured reason-less (never a guess). A thread that
        // RE-ARRIVES leaves the buffer: it is back on the radar, not "cleared".
        let newIDs = Set(threads.map { $0.id })
        for old in self.threads where !newIDs.contains(old.id) {
            captureCleared(old, why: nil)
        }
        self.threads = threads
        self.repoScope = Self.hasRepo(scopes)
        reconcileDischarges()   // the thread side moved — generations may have advanced
        // Re-arrival = back ON THE RADAR, not merely back in the feed (land-triage F1):
        // a DISCHARGED thread still sits unread in the feed — that is the CLI-review
        // case itself — and its "review submitted ✓" receipt must survive every 200
        // that keeps listing it. Only a row the user can actually see again un-clears.
        let radarIDs = Set(radar().map { $0.thread.id })
        recentlyCleared.removeAll { radarIDs.contains($0.thread.id) }
    }

    /// THE "currently on the radar" predicate (land-triage F1 residual): surfaces()
    /// alone is not the glass — a DISCHARGED thread passes preferences yet renders
    /// nowhere. Every consumer that means "the row the user can see" — capture
    /// eligibility, the read-check targets, the subject re-verify targets — must use
    /// this, or a discharged thread gets probed/re-captured as if it were live.
    private func isOnRadar(_ t: NotificationThread) -> Bool {
        preferences.surfaces(t, selfLogin: selfLogin) && !isDischarged(t)
    }

    /// Buffer a departure IF the thread was actually ON THE RADAR (a suppressed or
    /// already-discharged thread's exit never "cleared from Needs you" — its receipt,
    /// if any, already tells the truth). Dedup by id (re-capture replaces), cap 8.
    private mutating func captureCleared(_ thread: NotificationThread, why: ClearedWhy?) {
        guard isOnRadar(thread) else { return }
        // A reason-less re-capture never DOWNGRADES a known reason (land-triage F1):
        // the discharged thread finally leaving the feed is still "review submitted ✓",
        // not a mystery departure.
        if why == nil, let existing = recentlyCleared.first(where: { $0.thread.id == thread.id }),
           existing.why != nil { return }
        recentlyCleared.removeAll { $0.thread.id == thread.id }
        recentlyCleared.insert(ClearedEntry(thread: thread, why: why), at: 0)
        if recentlyCleared.count > 8 { recentlyCleared.removeLast(recentlyCleared.count - 8) }
    }

    /// "repo" scope parse — the one rule for private-repo enrichment eligibility.
    public static func hasRepo(_ scopes: String?) -> Bool {
        (scopes ?? "").split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.contains("repo")
    }

    // MARK: - enrichment targeting (the shell iterates; the policy lives here)

    public struct EnrichmentTargets {
        public let hits: [Int]           // indices to fetch, in pass order
        public let skippedPrivate: Int   // scope-blocked (counted, never fetched)
    }

    /// Pass 1 — subject state (LOW-VOLUME, runs first so it never starves on the shared
    /// budget; see the F6 note in the pipeline). Ordered by thread position.
    public func subjectStateTargets() -> EnrichmentTargets {
        targets { SignalClassifier.needsSubjectState($0, selfLogin: selfLogin) }
    }

    /// Pass 2 — latest-comment author (bot/self demotion + the excerpt).
    public func commentAuthorTargets() -> EnrichmentTargets {
        targets { SignalClassifier.needsCommentAuthor($0, selfLogin: selfLogin) }
    }

    private func targets(_ needs: (NotificationThread) -> Bool) -> EnrichmentTargets {
        var hits: [Int] = []
        var skipped = 0
        for index in threads.indices where needs(threads[index]) {
            if threads[index].repository.isPrivate && !repoScope { skipped += 1; continue }
            hits.append(index)
        }
        return EnrichmentTargets(hits: hits, skippedPrivate: skipped)
    }

    /// Store a fetched subject verdict — TERMINAL ONLY (merged/closed can't un-happen).
    /// "open" is perishable: caching it froze a thread as forever-open across 304s
    /// (dogfood 2026-07-16 — `needsSubjectState` re-checks nil, never a
    /// cached "open"). Returns whether a terminal verdict was stored.
    @discardableResult
    public mutating func applySubjectVerdict(at index: Int, state: String) -> Bool {
        guard state == "merged" || state == "closed" else { return false }
        // Departure capture BEFORE the verdict lands — surfaces() must judge the
        // pre-verdict truth ("was this row on the glass?"), and only reasons whose ask
        // dies with the subject actually depart on a verdict (the read-me class stays).
        if SignalClassifier.asksDieWithSubject.contains(threads[index].reason) {
            captureCleared(threads[index], why: state == "merged" ? .merged : .closed)
        }
        threads[index].subjectState = state
        return true
    }

    public mutating func cacheCommentAuthor(at index: Int, login: String, body: String?) {
        threads[index].latestCommentAuthorLogin = login
        threads[index].latestCommentExcerpt = RadarPresenter.excerpt(from: body)
    }

    // MARK: - self resolution (F9)

    /// Adopt a completed `GET /user`. Only a NON-NIL login marks resolved — a completed-
    /// but-failed request must retry next refresh, or self-activity demotion is
    /// permanently disabled (review F9). First resolution arms the re-projection latch.
    public mutating func resolvedSelf(_ login: String?) {
        guard !selfResolved, let login else { return }
        selfLogin = login
        selfResolved = true
        selfJustResolved = true
    }

    // MARK: - 304 re-verify (the honesty pass)

    /// Throttle: one attempt per window. The STAMP happens in `stampReverify` on
    /// attempt — a verify that finds nothing still consumes its window.
    public func reverifyDue(now: Date, window: TimeInterval = 600) -> Bool {
        now.timeIntervalSince(lastSubjectVerify) >= window
    }

    public mutating func stampReverify(now: Date) {
        lastSubjectVerify = now
    }

    /// The surfaced, still-unresolved action set — the only rows worth a re-verify GET:
    /// unread ∧ (state unknown OR legacy-cached "open") ∧ PR/Issue ∧ has-url ∧
    /// currently surfaced ∧ readable under the current scope.
    public func reverifyTargets() -> [Int] {
        threads.indices.filter { index in
            let t = threads[index]
            return t.unread
                && (t.subjectState == nil || t.subjectState == "open")
                && (t.subject.type == "PullRequest" || t.subject.type == "Issue")
                && t.subject.url != nil
                && isOnRadar(t)
                && !(t.repository.isPrivate && !repoScope)
        }
    }

    /// A re-verify flip happened (subject resolved OR thread read) — arm the latch.
    public mutating func markSubjectResolution() {
        subjectJustResolved = true
    }

    /// 304-path READ-check targets: every currently-SURFACED row, ANY subject type —
    /// the founding case is a Release mention (dogfood 2026-07-18: visiting the release
    /// page marks the thread read, but Release subjects are outside the subject-state
    /// re-verify's PR/Issue world entirely, and the feed 304s across read transitions).
    /// Call AFTER the subject pass, so freshly-resolved rows don't spend read budget.
    public func readCheckTargets() -> [Int] {
        threads.indices.filter { isOnRadar(threads[$0]) }
    }

    /// Adopt read transitions: these threads LEFT the unread feed (read on GitHub) —
    /// remove them, exactly as the next 200 would if the feed didn't 304 across reads.
    /// Returns whether anything was removed (the caller arms the re-projection latch).
    public mutating func applyThreadsRead(ids: Set<String>) -> Bool {
        let before = threads.count
        for t in threads where ids.contains(t.id) { captureCleared(t, why: .read) }
        threads.removeAll { ids.contains($0.id) }
        // A read-check removal is a POSITIVE per-thread verification from GitHub — live
        // truth even when it empties the set (land-triage F2): the projection guard's
        // cold-snapshot protection applies only before any live evidence exists.
        if threads.count != before { threadTruthVerified = true }
        return threads.count != before
    }

    // MARK: - re-projection latches

    /// One-shot, consolidated: true when ANY latch was armed AND this reading holds live
    /// truth to re-project. All latches clear on every call (per-tick consumption — a
    /// latch must never survive into a later tick). "Live truth" = cached threads OR a
    /// reviews sweep that RAN this run (`standingReviews.sweptThisRun` — an EMPTY completed sweep
    /// counts: the last owed review departing must clear its row even on a 304 tick,
    /// never linger as a ghost). A SEEDED baseline is deliberately not enough: the seed
    /// is last-session paint, and letting it project would wipe the snapshot's thread
    /// rows on a failed first tick (triage F2 — the seed restores standing truth, it
    /// must not unlock re-projection). Validators are in-memory, so a 304 (the only
    /// tick that consumes this latch) always follows a same-run 200 — an empty
    /// projection here is honest, not a cold-start wipe.
    public mutating func consumeResolutions() -> Bool {
        let reviewsChanged = standingReviews.consumeJustChanged()   // unconditional: latches
        let armed = selfJustResolved || subjectJustResolved || reviewsChanged   // never survive a tick
        selfJustResolved = false
        subjectJustResolved = false
        let hasProjection = !threads.isEmpty || standingReviews.sweptThisRun || threadTruthVerified
        return armed && hasProjection
    }

    // MARK: - reviews-owed standing source (WP 2026-07-17-002)
    //
    // The SEARCH side (adopt/union/seed/latch/evidence) lives whole in
    // `StandingReviews`; only the operations that need BOTH sources — dedup and
    // discharge, where search truth meets the thread cache — stay on this reading.

    public mutating func adoptReviews(_ new: InboundReading) -> InboundReading {
        let adopted = standingReviews.adopt(new)
        reconcileDischarges()
        return adopted
    }

    public mutating func seedReviewsBaseline(_ items: [InboundItem]) {
        standingReviews.seed(items)
    }

    /// The synthetic review-owed threads: baseline items NOT already represented by a
    /// real notification thread. Dedup key = html url (the one existing converter,
    /// `RadarPresenter.htmlURL`, on the thread side; the search item carries it
    /// directly). A real thread claims its PR ONLY when it carries a LIVE ask (see
    /// `reviewAskURL`) — that row surfaces the owed review with richer facts
    /// (enrichment, excerpt). An AMBIENT thread on the same PR (`ci_activity`,
    /// `comment`, …) must NOT eat the synthetic: it may never surface (default-off
    /// reason, bot-demoted), and even surfaced it asks something else — dropping the
    /// synthetic there re-opens the exact read-notification miss this source exists to
    /// close (Codex P1, WP-B round). Two rows for one PR with two distinct asks is the
    /// plan's blessed cross-lane coexistence, not a duplicate.
    public func reviewOwedThreads() -> [NotificationThread] {
        guard let baseline = standingReviews.baseline, !baseline.items.isEmpty else { return [] }
        let realURLs = Set(threads.compactMap { reviewAskURL($0, requireLiveSubject: true) })
        return baseline.items
            .filter { !realURLs.contains($0.url) }
            .map { NotificationThread.reviewOwed(from: $0) }
    }

    /// The url of a real thread's review ask (`review_requested` only) — the ONE
    /// predicate both dedup and discharge match on, with their one deliberate
    /// difference parameterized: DEDUP requires a live subject (nil/"open" verdict),
    /// because a terminally-resolved request cannot represent a still-open owed review
    /// (the reopened-PR edge must yield to the synthetic). DISCHARGE takes any verdict:
    /// a dead thread is already off the radar, so matching it is a harmless no-op.
    /// The asymmetry is intentional, not drift (refactor pass 2026-07-17).
    private func reviewAskURL(_ t: NotificationThread, requireLiveSubject: Bool) -> String? {
        guard t.reason == "review_requested" else { return nil }
        if requireLiveSubject, t.subjectState != nil, t.subjectState != "open" { return nil }
        return RadarPresenter.htmlURL(for: t)
    }

    // MARK: - inbound baseline

    /// `InboundReading.adopt` with the baseline owned here: an incomplete search keeps
    /// the previous reading whole; the adopted reading becomes the new baseline.
    public mutating func adoptInbound(_ new: InboundReading) -> InboundReading {
        let adopted = InboundReading.adopt(previous: inboundBaseline, new: new)
        inboundBaseline = adopted
        return adopted
    }

    // MARK: - projections (delegate to the one classification home)

    /// The radar over BOTH sources — real threads + deduped synthetic review-owed
    /// threads. One merged array is the whole design (WP 2026-07-17-002): the pill
    /// count, the menu-bar glyph, the affirmation's emptiness gate, and the island all
    /// read this set, so the four surfaces cannot disagree.
    public func radar() -> [RankedThread] {
        let active = dischargeBindings.isEmpty ? threads : threads.filter { !isDischarged($0) }
        return SignalClassifier.radar(active + reviewOwedThreads(),
                                      selfLogin: selfLogin, preferences: preferences)
    }

    public func suppressed() -> [RankedThread] {
        var rows = SignalClassifier.suppressed(threads + reviewOwedThreads(),
                                               selfLogin: selfLogin, preferences: preferences)
        // Discharged review requests stay AUDITABLE (the suppressed set is the miss
        // audit surface) — appended manually, because the classifier would still
        // surface them: the discharge fact lives in this reading, not in classify().
        rows += threads
            .filter { isDischarged($0) && preferences.surfaces($0, selfLogin: selfLogin) }
            .map { RankedThread(thread: $0,
                                classification: SignalClassifier.classify($0, selfLogin: selfLogin),
                                effectiveReason: SignalClassifier.effectiveReason($0, selfLogin: selfLogin)) }
        // Re-sort the MERGE (land-verdict P2): the probe audits `prefix(25)` under a
        // "most-likely-miss first" promise, and a 95-urgency discharged row appended
        // after 500 classifier-sorted rows would be buried below the very surface that
        // exists to catch it.
        return rows.sorted { $0.classification.urgency > $1.classification.urgency }
    }

    /// A thread is discharged only when it IS the bound generation (land-verdict P1):
    /// the same url with a bumped `updatedAt` is a NEW ask (re-request re-notifies the
    /// same thread) and must surface even while the search index lags its arrival.
    private func isDischarged(_ t: NotificationThread) -> Bool {
        guard !dischargeBindings.isEmpty,
              let url = reviewAskURL(t, requireLiveSubject: false) else { return false }
        return dischargeBindings[url] == t.updatedAt
    }

    /// Re-derive discharge state after EITHER source moved (both adopts call this —
    /// `radar()`/`suppressed()` stay pure reads). Order matters:
    /// 1. Bind urls newly entering discharge candidacy to the LATEST generation their
    ///    thread had while owed. A url that departs with no recorded generation (the
    ///    web flow read its thread) never binds — a later re-request thread is a fresh
    ///    generation by construction. (Accepted bound: a re-request landing INSIDE the
    ///    departure-lag window — after the review, before the index reflects it — binds
    ///    and is briefly suppressed until the index carries B back into the baseline,
    ///    which kills the binding. Self-healing within index lag, the same bound the
    ///    synthetic path accepts for departures. Freezing the FIRST owed generation
    ///    instead would no-op the discharge for any PR with activity while owed.)
    /// 2. Existing bindings stay frozen (re-binding to a bumped generation would
    ///    re-suppress the fresh ask) and die when candidacy ends (owed again).
    /// 3. Refresh the owed-generation ledger for the currently-owed set.
    private mutating func reconcileDischarges() {
        let candidates = standingReviews.dischargedURLs()
        for url in candidates where dischargeBindings[url] == nil {
            if let gen = owedThreadGen[url] {
                // Departure capture BEFORE the binding installs (land-triage F1
                // residual): capture eligibility is isOnRadar, and installing the
                // binding first would make the thread discharged — rejecting the very
                // receipt this door exists to mint.
                if let t = threads.first(where: { reviewAskURL($0, requireLiveSubject: false) == url
                                                  && $0.updatedAt == gen }) {
                    captureCleared(t, why: .reviewSubmitted)
                }
                dischargeBindings[url] = gen
            }
        }
        dischargeBindings = dischargeBindings.filter { candidates.contains($0.key) }
        let owedNow = Set(standingReviews.baseline?.items.map { $0.url } ?? [])
        for t in threads {
            guard let url = reviewAskURL(t, requireLiveSubject: false),
                  owedNow.contains(url) else { continue }
            owedThreadGen[url] = t.updatedAt
        }
        owedThreadGen = owedThreadGen.filter { owedNow.contains($0.key) }
    }

    public func reasonHistogram() -> [String: Int] {
        var histogram: [String: Int] = [:]
        for thread in threads { histogram[thread.reason, default: 0] += 1 }
        return histogram
    }
}

/// The standing reviews-owed SEARCH side, whole (refactor 2026-07-17): seven review
/// rounds accreted adopt / truncation-union / seed / change-latch / departure-evidence
/// policy onto `RadarReading` one patch at a time — this value is that policy's single
/// home, so its state transitions read as one unit. `RadarReading` owns the THREAD side
/// and the merge (dedup + discharge apply where the two sources meet).
struct StandingReviews: Sendable {
    /// The adopted search truth (nil before the first sweep or seed).
    private(set) var baseline: InboundReading?
    /// DEPARTURE evidence (Codex 5b P2): every url a COMPLETE sweep listed as owed this
    /// run. Seeds and truncated unions (incomplete) never contribute — stale or partial
    /// truth must not discharge a real notification.
    private var everOwedURLs: Set<String> = []
    /// A sweep actually RAN this run (adopt, not seed) — the projection guard's "live
    /// truth" bit; a seeded baseline never sets it (triage F2).
    private(set) var sweptThisRun = false
    /// The adopted reading changed — arms the 304-tick re-projection repaint.
    private var justChanged = false

    /// Adopt a sweep — `InboundReading.adopt` semantics (an incomplete search never
    /// removes standing truth). Arms the repaint latch when the adopted READING changed
    /// at all — not just the url set: a retitle or new-commit `updated_at` on a
    /// still-owed PR feeds the synthetic's title and ageing, and on a 304-quiet inbox
    /// that latch is the only repaint path (Codex P2, round 4). A first sweep that
    /// finds nothing stays silent (nil → empty is not a change anyone can see).
    mutating func adopt(_ new: InboundReading) -> InboundReading {
        let adopted: InboundReading
        if !new.incomplete, new.items.count < new.totalCount, let previous = baseline {
            // TRUNCATED page (the 50-cap, triage F1): the tail is invisible, so a
            // replace would fabricate departures for items pushed past the boundary —
            // page-1 membership is NOT stable under created-asc, because a review
            // request landing on an OLD PR sorts ahead of everything younger. Union:
            // the page's truth plus prior items the page can't see. Beyond-page
            // departures linger until the owed set fits one page — a budgeted false
            // alarm, never a fabricated "handled" (the pulse-honesty rule).
            let pageURLs = Set(new.items.map { $0.url })
            adopted = InboundReading(
                items: new.items + previous.items.filter { !pageURLs.contains($0.url) },
                incomplete: true, totalCount: new.totalCount)
        } else {
            adopted = InboundReading.adopt(previous: baseline, new: new)
        }
        let changed = baseline.map { $0 != adopted } ?? !adopted.items.isEmpty
        if changed { justChanged = true }
        sweptThisRun = true
        if !adopted.incomplete { everOwedURLs.formUnion(adopted.items.map { $0.url }) }
        baseline = adopted
        return adopted
    }

    /// Seed from a persisted snapshot (cold launch, before the first tick): standing
    /// truth must survive the LAUNCH boundary, or a first tick whose notifications
    /// succeed while the reviews search fails wipes still-owed rows (triage F2). A seed
    /// is a paint, not a read — no latch arms, `sweptThisRun` stays false, and the next
    /// COMPLETE sweep replaces it wholesale via the normal adopt path.
    mutating func seed(_ items: [InboundItem]) {
        guard baseline == nil, !items.isEmpty else { return }
        baseline = InboundReading(items: items, incomplete: true, totalCount: items.count)
    }

    /// One-shot read of the repaint latch (consumed every tick, never survives one).
    mutating func consumeJustChanged() -> Bool {
        defer { justChanged = false }
        return justChanged
    }

    /// The review-submitted discharge set (Codex 5b P2): urls whose debt a COMPLETE
    /// sweep has proven repaid — owed in a prior complete sweep this run, absent from
    /// the current complete baseline. Mere absence is NOT enough: a just-arrived
    /// request whose notification beat the search index was never owed-then-departed,
    /// and absence-based discharge would eat it during the lag window (the never-miss
    /// trap). An incomplete baseline (seed, truncated union) discharges nothing.
    func dischargedURLs() -> Set<String> {
        guard let baseline, !baseline.incomplete else { return [] }
        return everOwedURLs.subtracting(baseline.items.map { $0.url })
    }
}

// MARK: - "Just cleared" (plan 2026-07-21-001)

/// Why a row left "Needs you" — present ONLY when the reading actually knows (the
/// reason-honesty rule: a plain feed departure carries nil, never a guess).
public enum ClearedWhy: Equatable, Sendable {
    case read              // the thread read-check saw unread:false
    case reviewSubmitted   // the reviews sweep proved the debt repaid (discharge)
    case merged
    case closed
}

/// One buffered departure — the thread as it last surfaced, plus the known reason.
public struct ClearedEntry: Equatable, Sendable {
    public let thread: NotificationThread
    public let why: ClearedWhy?
    public init(thread: NotificationThread, why: ClearedWhy?) {
        self.thread = thread
        self.why = why
    }
}

/// One display row for the revealed "Just cleared" band — pure facts, App draws.
public struct ClearedRow: Equatable, Sendable {
    public let id: String
    public let repo: String
    public let title: String
    public let effectiveReason: String
    public let whyText: String?   // "read ✓" / "review submitted ✓" / "merged" / "closed" / nil
    /// Open-on-GitHub, the action ceiling (land-triage F3) — same converter as radar rows.
    public let url: String?
    public init(id: String, repo: String, title: String, effectiveReason: String, whyText: String?,
                url: String? = nil) {
        self.id = id; self.repo = repo; self.title = title
        self.effectiveReason = effectiveReason; self.whyText = whyText
        self.url = url
    }
}

extension RadarReading {
    /// The buffer as display rows (newest first) — the effective reason derived here,
    /// where selfLogin lives, exactly like radar()/suppressed() do.
    public func clearedRows() -> [ClearedRow] {
        recentlyCleared.map { entry in
            ClearedRow(id: entry.thread.id,
                       repo: entry.thread.repository.fullName,
                       title: entry.thread.subject.title,
                       effectiveReason: SignalClassifier.effectiveReason(entry.thread, selfLogin: selfLogin),
                       whyText: entry.why.map(PlainWords.clearedWhyText),
                       url: RadarPresenter.htmlURL(for: entry.thread))
        }
    }
}
