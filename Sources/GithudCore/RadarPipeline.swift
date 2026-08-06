import Foundation

/// The I/O seam the live scheduler drives, instead of a hard-wired `RadarPipeline`.
/// Extracting it (WP-1a) makes the scheduler shell independent of the concrete pipeline
/// (a fake can stand in). The TRUST-CRITICAL decisions do not live here — they live in
/// `GithudCore.PollReducer` (pure + fully unit-tested) and, since WP 2026-07-17-001, in
/// `RadarReading` (the reading's own pure state + transitions); this protocol only
/// abstracts the blocking I/O the shell feeds into those. The reducer still consumes
/// only the narrow `PollReducer.RadarRefresh` the shell maps from `Result`.
public protocol RadarSource: AnyObject {
    var preferences: SurfacePreferences { get set }
    func refresh() -> Swift.Result<RadarPipeline.Result, GitHubClientError>
    func fetchPulse() -> Swift.Result<[PullRequestPulse], GitHubClientError>
    /// The standing inbound sweep — the ADOPTED reading (incomplete searches never
    /// remove; the reading's completeness/totalCount ride along for the reducer's
    /// confirmation stamp + the scheduler's truncation disclosure).
    func fetchInbound() -> Swift.Result<InboundReading, GitHubClientError>
    func recomputeRadar() -> [RankedThread]
    /// Did the last tick arm a re-projection — `/user` resolving with cached threads
    /// (the inbound derivation flips off-network), OR the 304-path re-verify flipping a
    /// surfaced subject to merged/closed (dogfood 2026-07-16)? ONE consolidated one-shot
    /// (WP 2026-07-17-001): both latches clear on every call, so the old two-call
    /// "consume both, never short-circuit" footgun is structurally gone. Declines with
    /// an empty cache — a snapshot-painted radar must not be wiped by an empty
    /// re-projection.
    func consumeResolutions() -> Bool
    /// The signed-in login once `GET /user` resolved (nil before). Read by the scheduler
    /// after each tick to feed the owner lens's "yours" rendering (WP 2026-07-14-001).
    var currentSelfLogin: String? { get }
    /// The standing reviews-owed baseline (search truth, PRE-dedup) — captured per tick
    /// for snapshot persistence, so standing truth survives the launch boundary.
    var currentReviewsOwed: [InboundItem] { get }
    /// Seed the reviews baseline from a persisted snapshot BEFORE the first tick — a
    /// failed first sweep must keep last-good, and last-good lives across launches
    /// (triage F2). A seed never unlocks re-projection (see RadarReading).
    func seedReviewsBaseline(_ items: [InboundItem])
    /// The session-scoped departure receipts (plan 2026-07-21-001, "Just cleared") —
    /// captured per tick by the scheduler, display-only downstream.
    var currentClearedRows: [ClearedRow] { get }
}

/// The shared "one refresh" pipeline: conditional `GET /notifications` → enrich
/// (repo-scope-aware) → self-login → SignalClassifier radar + suppressed. BLOCKING
/// (uses semaphores) — call OFF the main thread. Since WP 2026-07-17-001 this class is
/// ONLY the I/O shell: every carried fact and every policy decision lives in one
/// `RadarReading` (pure, tested); the shell owns the wall-clock budgets and the six
/// blocking wrappers. Used by both `githud probe` and the live PollScheduler so the
/// fetch/enrich/self logic lives in ONE place.
public final class RadarPipeline: RadarSource {
    private let client: GitHubClient
    /// THE reading — all state, all transitions, all tested (`RadarReading`).
    private var reading = RadarReading()

    // The blocking methods below assert they are NOT on the main queue — turning a
    // silent ~30s main-thread hang (a frozen HUD) into an immediate debug crash.
    // Unconditional: the live scheduler polls off-main by construction, and
    // ProbeCommand hops its body onto a background queue before driving the pipeline.

    /// Which reasons the user surfaces. A change re-computes the radar from the cached
    /// threads (no re-fetch) — see `recomputeRadar`.
    public var preferences: SurfacePreferences {
        get { reading.preferences }
        set { reading.preferences = newValue }
    }

    public init(client: GitHubClient) {
        self.client = client
    }

    public var currentSelfLogin: String? { reading.selfLogin }

    /// The standing reviews-owed baseline (search truth, PRE-dedup) — the probe's audit
    /// surface: this list must match github.com/pulls/review-requested item-for-item
    /// (WP 2026-07-17-002's kill condition). Empty before the first completed sweep.
    public var currentReviewsOwed: [InboundItem] { reading.reviewsBaseline?.items ?? [] }

    public func seedReviewsBaseline(_ items: [InboundItem]) {
        reading.seedReviewsBaseline(items)
    }

    public var currentClearedRows: [ClearedRow] { reading.clearedRows() }

    /// Re-run the radar on the last fetched threads with the current preferences.
    public func recomputeRadar() -> [RankedThread] {
        reading.radar()
    }

    public struct Result {
        public let notModified: Bool
        public let nextPollAfter: Int
        public let radarPreEnrich: [RankedThread]   // before enrichment/self-demote
        public let radar: [RankedThread]            // after
        public let suppressed: [RankedThread]
        public let threadCount: Int
        public let enriched: Int
        public let subjectStateEnriched: Int        // how many got a merged/closed/open verdict this refresh
        public let resolvedThreads: [NotificationThread]   // enriched threads (for debugging subject state)
        public let skippedPrivate: Int
        public let hasRepoScope: Bool
        public let rateRemaining: Int?
        public let scopes: String?
        public let reasonHistogram: [String: Int]
        /// The reviews-owed sweep completed (a COMPLETE reading) THIS tick — the
        /// affirmation's confirmation fact (WP 2026-07-17-002). False when the sweep
        /// was skipped (login unresolved), failed, or came back incomplete.
        public let reviewsComplete: Bool

        public var demotedByEnrichment: Int { radarPreEnrich.count - radar.count }
    }

    public func refresh() -> Swift.Result<Result, GitHubClientError> {
        dispatchPrecondition(condition: .notOnQueue(.main))
        resolveSelfIfNeeded()
        guard let outcome = blockingFetch(validators: reading.validators) else {
            return .failure(.transport("request timed out"))
        }
        switch outcome {
        case .failure(let error):
            return .failure(error)
        case .success(let resp):
            reading.adoptValidators(resp.pollPlan.nextValidators)
            let delay = resp.pollPlan.nextPollAfterSeconds
            // The reviews-owed standing sweep rides EVERY tick (both legs): a 304 of
            // /notifications says nothing about reviews arriving or departing. An
            // owed-set change arms the re-projection latch inside adoptReviews, so it
            // renders even on a notModified tick.
            let reviewsComplete = sweepReviews()
            if resp.notModified {
                // The 304 staleness hole (dogfood 2026-07-16): closing a PR
                // you've unsubscribed from generates NO new notification, so the inbox
                // can 304 indefinitely while a resolved subject sits in "Needs you".
                // Throttled re-verify of the surfaced set; a flip re-projects via the
                // consumeResolutions() seam.
                reverifySubjectStatesIfDue()
                return .success(Result(
                    notModified: true, nextPollAfter: delay,
                    radarPreEnrich: [], radar: [], suppressed: [],
                    threadCount: 0, enriched: 0, subjectStateEnriched: 0, resolvedThreads: [],
                    skippedPrivate: 0,
                    hasRepoScope: RadarReading.hasRepo(resp.oauthScopes),
                    rateRemaining: resp.rateLimit?.remaining,
                    scopes: resp.oauthScopes, reasonHistogram: [:],
                    reviewsComplete: reviewsComplete))
            }

            let radarPre = SignalClassifier.radar(resp.threads, selfLogin: reading.selfLogin,
                                                  preferences: reading.preferences)
            reading.adopt200(threads: resp.threads, scopes: resp.oauthScopes)
            var enriched = 0
            // Bounded enrichment (review F6): cap the wall-clock spent enriching per
            // refresh so a slow network can't stall the FIRST render for minutes.
            // Un-enriched threads still SURFACE (never-miss) and re-enter the targets
            // on the next changed poll. WHICH indices, in WHICH pass order, and WHAT is
            // stored are `RadarReading` policy (tested); the deadline is wall-clock I/O
            // and stays here. Subject-state runs FIRST — low-volume, so it never starves
            // on the shared budget; terminal-only caching lives in
            // `RadarReading.applySubjectVerdict` (the 304 re-verify rule).
            let enrichDeadline = Date().addingTimeInterval(12)
            let subjectTargets = reading.subjectStateTargets()
            var subjectStateEnriched = 0
            for index in subjectTargets.hits {
                if Date() >= enrichDeadline { break }
                if let url = reading.threads[index].subject.url,
                   let state = blockingSubjectState(url) {
                    reading.applySubjectVerdict(at: index, state: state)
                    subjectStateEnriched += 1
                }
            }
            // Comment-author enrichment (bot/self demotion + the excerpt): gets whatever
            // of the budget remains.
            let authorTargets = reading.commentAuthorTargets()
            for index in authorTargets.hits {
                if Date() >= enrichDeadline { break }
                if let url = reading.threads[index].subject.latestCommentUrl,
                   let author = blockingAuthor(url) {
                    reading.cacheCommentAuthor(at: index, login: author.login, body: author.body)
                    enriched += 1
                }
            }
            // Parity note vs the pre-extraction loop: `skippedPrivate` now counts the
            // FULL scope-blocked set (targets are computed up front), where the old loop
            // stopped counting at the deadline break — strictly more honest, and zero
            // for any token with repo scope.
            let skippedPrivate = subjectTargets.skippedPrivate + authorTargets.skippedPrivate

            return .success(Result(
                notModified: false, nextPollAfter: delay,
                radarPreEnrich: radarPre,
                radar: reading.radar(),
                suppressed: reading.suppressed(),
                threadCount: reading.threads.count, enriched: enriched,
                subjectStateEnriched: subjectStateEnriched,
                resolvedThreads: reading.threads.filter { $0.subjectState != nil },
                skippedPrivate: skippedPrivate,
                hasRepoScope: reading.repoScope, rateRemaining: resp.rateLimit?.remaining,
                scopes: resp.oauthScopes, reasonHistogram: reading.reasonHistogram(),
                reviewsComplete: reviewsComplete))
        }
    }

    /// The reviews-owed sweep (WP 2026-07-17-002): fetch + adopt, returning THIS tick's
    /// completeness. Login unresolved → skipped (false); failure → baseline kept, false.
    private func sweepReviews() -> Bool {
        guard let login = reading.selfLogin else { return false }
        let outcome = blocking(timeout: 20) { client.fetchReviewRequestedSearch(login: login, completion: $0) }
        guard case .success(let new) = outcome ?? .failure(.transport("no result")) else { return false }
        _ = reading.adoptReviews(new)
        // Completeness withheld on the 50-cap too (no silent caps): a truncated page
        // means owed reviews beyond it are absent, so "complete" would be a lie — and it
        // costs nothing, because a truncated sweep renders 50 rows and the affirmation
        // is unreachable anyway. The ADOPTION above stays unconditional: page-1 items
        // are stable under created-asc sort (departures only shift younger items IN), so
        // a truncated reading never falsely removes a still-owed row — marking it
        // incomplete for adopt would freeze the baseline instead (Codex P2, round 5).
        return !new.incomplete && new.items.count >= new.totalCount
    }

    // MARK: - helpers

    private func resolveSelfIfNeeded() {
        guard !reading.selfResolved else { return }
        // Only a login actually OBTAINED marks resolved (review F9) — the rule itself
        // lives in `RadarReading.resolvedSelf` (nil is a no-op → retry next refresh).
        guard let outcome = blocking(timeout: 15, { client.fetchAuthenticatedUserLogin(completion: $0) })
        else { return }
        reading.resolvedSelf(try? outcome.get())
    }

    /// One-shot read of the re-projection latches (see the protocol doc). Queue-confined:
    /// only ever called on the scheduler's serial poll queue, right after `refresh()`.
    public func consumeResolutions() -> Bool {
        reading.consumeResolutions()
    }

    // NOTE (code review iter 24): the blocking-semaphore pattern below is safe from
    // deadlock — GitHubClient uses URLSession dataTask completions, which fire on the
    // session's own background queue, never this poll queue. So waiting here never
    // blocks the thread that must deliver the completion.

    /// Run one of the client's callback APIs to completion on THIS thread, with a
    /// wall-clock cap: the result, or `nil` when the wait timed out. The one home of the
    /// semaphore pattern the six wrappers below used to spell out one by one — each site
    /// keeps its OWN timeout and its own handling of the result. The semaphore is created
    /// fresh per call, so no signal can leak across calls, and waiting here is still safe
    /// (see the deadlock note above): completions land on the session's queue, not this one.
    private func blocking<T>(timeout: TimeInterval,
                             _ call: (@escaping (Swift.Result<T, GitHubClientError>) -> Void) -> Void)
        -> Swift.Result<T, GitHubClientError>? {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Swift.Result<T, GitHubClientError>?
        call { result in
            outcome = result
            semaphore.signal()
        }
        if semaphore.wait(timeout: .now() + timeout) == .timedOut { return nil }
        return outcome
    }

    private func blockingFetch(validators: PollValidators) -> Swift.Result<NotificationsResponse, GitHubClientError>? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return blocking(timeout: 30) { client.fetchNotifications(validators: validators, completion: $0) }
    }

    /// Fetch the H2 pulse (open-PR CI/review/merge state) via one GraphQL query.
    /// Blocking (semaphore) — call OFF the main thread; same deadlock-safety note as
    /// `blockingFetch` (completions fire on the session's queue, never this one).
    /// Independent of the notifications validators — GraphQL has no 304.
    public func fetchPulse() -> Swift.Result<[PullRequestPulse], GitHubClientError> {
        dispatchPrecondition(condition: .notOnQueue(.main))
        return blocking(timeout: 20) { client.fetchOpenPullRequests(completion: $0) }
            ?? .failure(.transport("pulse request timed out"))
    }

    /// The standing inbound sweep (WP 2026-07-09-001). The search query needs the LITERAL
    /// login — unresolved → an honest failure (the reducer keeps last-good), never an
    /// empty "nothing at your door" fabrication. The adopt rule (incomplete searches
    /// never remove) lives in `RadarReading.adoptInbound`.
    public func fetchInbound() -> Swift.Result<InboundReading, GitHubClientError> {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let selfLogin = reading.selfLogin else {
            return .failure(.transport("self login unresolved — sweep skipped"))
        }
        let outcome = blocking(timeout: 20) { client.fetchInboundSearch(login: selfLogin, completion: $0) }
        switch outcome ?? .failure(.transport("inbound sweep timed out")) {
        case .success(let new):
            return .success(reading.adoptInbound(new))
        case .failure(let error):
            return .failure(error)
        }
    }

    private func blockingAuthor(_ urlString: String) -> (login: String, body: String?)? {
        // 6s: tight per-fetch cap so the enrichment budget holds. Failure/timeout → nil.
        let outcome = blocking(timeout: 6) { client.fetchLatestCommentAuthor(urlString: urlString, completion: $0) }
        guard let value = try? outcome?.get() else { return nil }
        return (value.login, value.body)
    }

    /// Re-check the SURFACED action set's subject states against the live API — the
    /// 304-path honesty pass (dogfood 2026-07-16 + 2026-07-18). Two facts the feed's
    /// 304 hides: a resolved PR/issue generates no new notification, and
    /// marking a thread READ does not bump the feed's Last-Modified (the lexical
    /// Release mention — read on GitHub, lingering on the glass until an unrelated
    /// notification arrived). Both checks ride one throttle window and one deadline;
    /// the READ pass runs second, over the rows still surfaced AFTER the subject flips
    /// (freshly-resolved rows don't spend read budget). Predicates and transitions live
    /// in `RadarReading` (tested); the deadline and the GETs live here.
    private func reverifySubjectStatesIfDue() {
        let now = Date()
        guard reading.reverifyDue(now: now) else { return }
        reading.stampReverify(now: now)
        let deadline = now.addingTimeInterval(12)
        var flipped = false
        for index in reading.reverifyTargets() {
            if Date() >= deadline { break }
            guard let url = reading.threads[index].subject.url,
                  let state = blockingSubjectState(url) else { continue }
            if reading.applySubjectVerdict(at: index, state: state) { flipped = true }
        }
        var readIDs: Set<String> = []
        for index in reading.readCheckTargets() {
            if Date() >= deadline { break }
            let id = reading.threads[index].id
            if blockingThreadUnread(id) == false { readIDs.insert(id) }
        }
        if !readIDs.isEmpty, reading.applyThreadsRead(ids: readIDs) { flipped = true }
        if flipped { reading.markSubjectResolution() }
    }

    private func blockingSubjectState(_ urlString: String) -> SubjectLifecycle? {
        // Same tight per-fetch cap as the author enrichment. Failure/timeout → nil.
        try? blocking(timeout: 6) { client.fetchSubjectState(urlString: urlString, completion: $0) }?.get()
    }

    /// nil on failure/timeout — a failed check NEVER reads as "read" (never-miss:
    /// only a positive `unread: false` from GitHub removes a row).
    private func blockingThreadUnread(_ threadID: String) -> Bool? {
        try? blocking(timeout: 6) { client.fetchThreadUnread(threadID: threadID, completion: $0) }?.get()
    }
}
