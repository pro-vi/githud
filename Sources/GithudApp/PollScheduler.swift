import AppKit
import GithudCore
import Network

/// Drives LIVE polling in the running app via a `RadarSource`: a conditional
/// `GET /notifications` on the server's `X-Poll-Interval` (+ jitter), refreshing the
/// island ON CHANGE only.
///
/// As of WP-1a this is a THIN SHELL. Every trust-critical decision — 401/403 auth-stop,
/// rate-limit pause, transient retry, 200/304 freshness, radar/pulse change-detection —
/// lives in the pure, injected-clock `GithudCore.PollReducer` (fully unit-tested). The
/// shell owns only the impure edges: the DispatchQueue + Timer, the blocking source calls,
/// jitter, and interpreting the reducer's effects into UI callbacks. It feeds outcomes +
/// `Date()` into the reducer and performs what comes back.
///
/// idle-footprint: the ~60s conditional poll is the app's *core function*, not UI
/// animation — a 304 is free (no rate cost, no work), and the island only redraws when the
/// radar's thread set actually changes. No CADisplayLink, no per-frame timer. This refactor
/// is behavior-preserving: it adds NO new repeating timer — the single one-shot reschedule
/// timer is unchanged.
final class PollScheduler {
    private let source: RadarSource
    private let onRadar: ([RadarRow]) -> Void
    private let queue = DispatchQueue(label: "me.provi.githud.poll")

    /// All poll state (last render keys, last success, failure streak, last freshness)
    /// lives in the pure reducer's value type; the shell just threads it across ticks.
    private var state = PollReducer.PollState()
    private var timer: Timer?
    private var running = false

    /// Whether a poll's blocking work is currently in flight (main-confined). The reducer
    /// can't see this, so the shell owns it: `pollNow` coalesces to nothing while a poll is
    /// already running, and `poll()` never overlaps itself.
    private var inFlight = false

    /// Poll-now observers (WP-1b). Both are EVENT-DRIVEN, not timers — they fire only on a
    /// real OS event (wake / network path change), so idle-footprint is untouched (no
    /// permanent repeating timer, no CADisplayLink). start() creates them, stop() tears
    /// them down — no leaks after stop.
    private var wakeObserver: NSObjectProtocol?
    private var pathMonitor: NWPathMonitor?
    private let pathQueue = DispatchQueue(label: "me.provi.githud.path")

    /// Called once if the token is rejected (401/non-rate 403) — the app shows a "fix your
    /// token" state instead of silently retrying a dead token. Carries the REASON (WP-4e) so
    /// the app routes 401 (invalid/expired) vs 403 (SSO/scope) to distinct guidance.
    var onAuthFailure: ((AuthFailureReason) -> Void)?

    /// The H2 lane: open-PR pulse rows, refreshed on change (independent of the radar).
    var onPulse: (([PulseRow]) -> Void)?
    var onInbound: (([InboundRow]) -> Void)?
    /// A COMPLETE sweep succeeded — the inbound lane's confirmation seam (the affirmation
    /// and the pill's all-clear gate on the model fact this flips; an incomplete or failed
    /// sweep never fires it — never confirm a queue that was never fully read).
    var onInboundConfirmed: (() -> Void)?

    /// WP-4d first-poll-outcome seam (thin, by design): every completed poll tick reports
    /// the radar refresh's outcome in the pure seam vocabulary — `.success` (200/304,
    /// GitHub answered for the token), `.transientFailure` (genuinely no answer), or
    /// `.rateLimited(pauseSeconds:)` (GitHub answered "slow down" — the fix round's
    /// distinction: an answered request may never render as silence). Auth failures are
    /// excluded — they ride `onAuthFailure` (which also stops the loop). Mapped by
    /// `PollReducer.attemptOutcome` from the SAME result the reducer consumed, so the
    /// seam can never disagree with the render; the ledger card's "GitHub" row is the
    /// consumer, and with no card up it's a no-op.
    var onPollOutcome: ((PollAttemptOutcome) -> Void)?

    /// WP-3d′ fix 1a (round 2) — the radar-lane CONFIRMATION seam: fired on every
    /// completed poll whose radar outcome is `.success` (200/304 — a genuine read of the
    /// inbox for the token), REGARDLESS of render emission. The caught-up affirmation's
    /// `radarConfirmed` gate rides THIS, never the `onRadar` render callback: `onRadar`
    /// also carries `.preferencesRecomputed` renders (an off-network re-projection of a
    /// possibly never-fetched cache — not a read, must not confirm), and the recompute's
    /// `lastKey` adoption means an identical-key first success emits NO render (so gating
    /// confirmation on the render would never flip it — a permanent false negative).
    /// Fired only from `poll()`; `setPreferences`/`pollNow` have no read to report.
    var onRadarConfirmed: (() -> Void)?

    /// Degraded-reading-confidence cue (the sanctioned `caution` use). Emitted on CHANGE
    /// only — `.fresh` while polls land, a `.stale`/`.failing` value when they don't.
    var onFreshness: ((Freshness) -> Void)?

    /// The SWEEP clock crossed fresh↔stale (D1, WP 2026-07-10-001 fix round F-1) — fired
    /// exactly once per boolean crossing, both directions, off the reducer's
    /// `.emitSweepFreshness`. The consumer (AppDelegate → AppModel) treats it as a repaint
    /// poke: the render recomputes the actual prefix from the model's own sweep date, so
    /// the payload is informational (logged, never re-derived from).
    var onSweepFreshness: ((Freshness) -> Void)?

    /// A COMPLETE reviews-owed sweep succeeded (WP 2026-07-17-002) — the affirmation's
    /// confirmation seam, the inbound twin. Never fired for skipped/failed/incomplete.
    var onReviewsConfirmed: (() -> Void)?
    /// When a complete reviews sweep last succeeded — snapshot provenance (seeded on
    /// cold launch; persisted so the launch paint confirms only over a real prior read).
    private var lastReviewsSuccessAt: Date?
    func seedReviewsSuccess(_ date: Date?) {
        assert(!running, "seed before start()")
        lastReviewsSuccessAt = date
    }
    /// The owed baseline as of the last tick — captured queue-side (where the source
    /// mutates), read main-side by `persistSnapshot` (the `resolvedSelfLogin` pattern).
    private var lastReviewsOwedItems: [InboundItem] = []
    /// The "Just cleared" departure receipts (plan 2026-07-21-001) — delivered per tick;
    /// the model change-guards, so steady buffers render nothing.
    var onCleared: (([ClearedRow]) -> Void)?

    /// Cold-launch seed (triage F2): restore standing review truth into the source
    /// BEFORE the first tick, so a failed first sweep keeps last-good across launches.
    func seedReviewsBaseline(_ items: [InboundItem]) {
        assert(!running, "seed before start()")
        source.seedReviewsBaseline(items)
        lastReviewsOwedItems = items
    }

    /// The signed-in login resolved (GET /user) — fired once per DISTINCT resolution
    /// (change-tracked here, so steady ticks are silent), main-delivered like every seam.
    /// The owner lens consumes it: "yours" titles + the viewer's own prefix elision
    /// (WP 2026-07-14-001).
    var onSelfLogin: ((String) -> Void)?
    private var lastReportedSelfLogin: String?

    init(client: GitHubClient, preferences: SurfacePreferences = .auto, onRadar: @escaping ([RadarRow]) -> Void) {
        // The pipeline's blocking methods precondition off-main unconditionally — a
        // main-thread call is a ~30s HUD freeze surfaced as an immediate debug crash.
        let pipeline = RadarPipeline(client: client)
        pipeline.preferences = preferences                 // first poll uses the saved prefs
        self.source = pipeline
        self.onRadar = onRadar
    }

    func start() {
        guard !running else { return }
        running = true
        // Poll-now triggers: a wake-from-sleep and a network path change are both REAL
        // events (squarely within no-faked-realtime) that warrant an immediate, debounced
        // poll rather than waiting out the ~60s tick. Observed here so their lifecycle is
        // bound to the scheduler's (torn down in stop()).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.pollNow()
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // Only a transition to a usable path (back online) warrants a poll; a drop to
            // unsatisfied would just fail-fast. The debounce coalesces the burst NWPath
            // emits on start / interface flaps.
            if path.status == .satisfied { self?.pollNow() }
        }
        monitor.start(queue: pathQueue)
        pathMonitor = monitor
        poll()
    }

    func stop() {
        running = false
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        pathMonitor?.cancel()   // NWPathMonitor is single-use; start() makes a fresh one
        pathMonitor = nil
    }

    /// The debounced immediate-poll entry point (WP-1b) — wired to wake, NWPathMonitor, and
    /// (post-merge, by the runner) `HUDPanelController.onExpandChange`. The pure reducer
    /// DECIDES accept/refuse: it refuses during an active rate-limit pause (honoring
    /// GitHub's reset outranks immediacy — HARD requirement) and coalesces a request that
    /// lands within `PollReducer.pollNowDebounce`. The shell adds the in-flight guard the
    /// reducer can't see. Safe to call from any queue.
    func pollNow() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            if self.inFlight { self.log("pollNow: coalesced (poll in flight)"); return }
            let (next, effects) = PollReducer.reduce(.pollNowRequested, state: self.state, now: Date())
            self.state = next
            self.interpret(effects)   // [] (refused) or [.pollImmediately] (accepted)
        }
    }

    /// The island expanded (true) or collapsed (false) — wired from `HUDPanelController`'s
    /// `onExpandChange` seam (WP-1c). Two jobs, both EVENT-DRIVEN off the real expand transition
    /// (no timer): (1) tell the reducer, so poll ticks re-render on a coarse-age-bucket flip only
    /// while the ages are actually VISIBLE (the collapsed pill shows none); (2) on expand, fire a
    /// debounced immediate poll — absorbed follow-up (a): a fresh summon deserves current data
    /// without waiting out the ~60s tick (the reducer still refuses during a rate-limit pause).
    func setExpanded(_ expanded: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.running else { return }
            let (next, effects) = PollReducer.reduce(.expandChanged(expanded), state: self.state, now: Date())
            self.state = next
            self.interpret(effects)          // [] — the expand's own render is the panel's (WP-3e)
            if expanded { self.pollNow() }   // panel-expand → debounced poll-now
        }
    }

    /// Seed the reducer's freshness baseline to what the glass ALREADY shows (WP-1c review,
    /// Blocker B). AppDelegate paints the persisted snapshot with a `.stale` banner and then
    /// passes the SAME value here, BEFORE `start()`. Without this seed the reducer's
    /// `lastFreshness` inits `.fresh`, so the first healthy poll computes `.fresh == .fresh`
    /// and the change guard suppresses the emit — leaving the launch banner + pill caution
    /// clock sitting over LIVE data for the whole session (a permanent false-stale: cry-wolf
    /// on the doctrine-reserved caution cue). Seeded, the first healthy poll computes
    /// `.fresh != seeded-stale` → emits → the banner clears.
    ///
    /// The lanes' persisted last-success dates are seeded TOO: without them a FAILED first
    /// poll would compute `.fresh` (the "no poll yet → don't accuse" rule sees a nil
    /// `lastSuccessAt`) and clear the banner over hours-old snapshot data — the opposite
    /// fabrication. Seeded, a failed first poll computes `.stale(realAge)` and the banner
    /// honestly STAYS until a poll actually succeeds. Main-confined, pre-start only.
    /// The SWEEP clock is seeded the same way (F-1): without the persisted sweep date the
    /// crossing detector would treat a snapshot-painted queue as never-swept and could miss
    /// the moment a seeded-fresh clock ages into stale (fresh chrome over an ageing count —
    /// the same F3 inversion). The baseline is computed FROM the seeded date so it matches
    /// what the glass shows at seed time; the first real crossing after launch then emits.
    func seedFreshness(_ freshness: Freshness, radarSuccess: Date?, pulseSuccess: Date?,
                       inboundSuccess: Date?) {
        dispatchPrecondition(condition: .onQueue(.main))
        assert(!running, "seedFreshness must be called before start() — seeding later would clobber live poll state")
        state.lastFreshness = freshness
        state.lastSuccessAt = radarSuccess
        state.lastPulseSuccessAt = pulseSuccess
        state.lastInboundSuccessAt = inboundSuccess
        state.lastSweepFreshness = FreshnessModel.sweepStatus(lastSweepSuccess: inboundSuccess, now: Date())
    }

    /// Persist the reducer's last-good rows + each lane's last-success time, so the next cold
    /// launch paints them INSTANTLY (marked honestly stale) instead of a blank pill. The
    /// `Snapshot` value copy is taken on MAIN (state is main-confined); the Codable encode +
    /// disk write hop OFF-main onto the poll queue (Minor 1) so a slow disk can never stutter
    /// the render burst this rides on — `Snapshot` is a Sendable value type, so the handoff is
    /// race-free by construction. Live path only; called from `poll()` ONLY on a content change.
    private func persistSnapshot() {
        let snapshot = Snapshot(radar: state.lastRenderedRadar ?? [],
                                pulse: state.lastRenderedPulse ?? [],
                                inbound: state.lastRenderedInbound,
                                lastRadarSuccessAt: state.lastSuccessAt,
                                lastPulseSuccessAt: state.lastPulseSuccessAt,
                                lastInboundSuccessAt: state.lastInboundSuccessAt,
                                lastReviewsSuccessAt: lastReviewsSuccessAt,
                                reviewsOwed: lastReviewsOwedItems.isEmpty ? nil : lastReviewsOwedItems)
        queue.async { SnapshotStore.save(snapshot) }
    }

    // Change-detection signatures live in GithudCore (RadarPresenter.changeKey /
    // PulsePresenter.changeKey) so they are pure + unit-tested — every display-affecting
    // field, excluding derived age. The reducer compares them to decide re-render.

    /// The user toggled which reasons surface — re-compute the radar from the cached
    /// threads (no network) and refresh the island immediately.
    func setPreferences(_ preferences: SurfacePreferences) {
        queue.async { [weak self] in
            guard let self else { return }
            self.source.preferences = preferences
            let radar = self.source.recomputeRadar()
            DispatchQueue.main.async {
                let (next, effects) = PollReducer.reduce(.preferencesRecomputed(radar),
                                                         state: self.state, now: Date())
                self.state = next
                self.interpret(effects)
            }
        }
    }

    private func poll() {
        guard running, !inFlight else { return }   // main-confined; never overlap a poll
        inFlight = true
        queue.async { [weak self] in
            guard let self else { return }
            let radarResult = self.source.refresh()
            // H2 pulse: fetched EVERY tick — even on a notifications-304, because PR state
            // (CI finishing, a review landing) changes without a notification. Separate
            // GraphQL rate bucket; the REST 304-discipline is untouched.
            let pulseResult = self.source.fetchPulse()
            // Inbound sweep: every tick too (its own search rate bucket, ~1/30 of it) —
            // an item leaves the standing queue when it merges/closes, which no
            // notification announces reliably. Reduced by its OWN event below.
            let inboundResult = self.source.fetchInbound()
            // Map the fuller pipeline result onto the reducer's narrow, Core-side view.
            let radar = radarResult.map { result in
                PollReducer.RadarRefresh(notModified: result.notModified,
                                         nextPollAfter: result.nextPollAfter,
                                         radar: result.radar)
            }
            // Self-login resolved on THIS tick and the tick carried no re-classification
            // (a 304, OR a failed fetch — the re-verify round's finding A: gating on 304
            // alone ate the one-shot flag when resolution landed on a failing tick):
            // ownership just became decidable (the inbound derivation), so re-project the
            // cached threads through the same off-network seam a preference toggle rides.
            // Only a fresh 200 classifies with the login itself — then the flag is
            // consumed and dropped. `consumeSelfResolution()` also declines when there is
            // no cache to re-project (first-poll failure), so a snapshot-painted radar is
            // never wiped by an empty re-projection on a failed tick.
            let selfResolvedReprojection: [RankedThread]? = {
                // ONE consolidated one-shot (WP 2026-07-17-001): self resolution and the
                // 304-path subject re-verify share a latch pair that clears atomically
                // per call — the old "consume both, never short-circuit" ordering rule
                // is structurally gone (`RadarReading.consumeResolutions`, tested).
                guard self.source.consumeResolutions() else { return nil }
                if case .success(let r) = radarResult, !r.notModified { return nil }
                return self.source.recomputeRadar()
            }()
            // Captured on the poll queue (where the pipeline writes it) so the main-side
            // read below never races a later tick's resolution.
            let resolvedSelfLogin = self.source.currentSelfLogin
            let reviewsOwedNow = self.source.currentReviewsOwed
            let clearedNow = self.source.currentClearedRows
            DispatchQueue.main.async {
                self.inFlight = false
                guard self.running else { return }
                self.lastReviewsOwedItems = reviewsOwedNow   // main-side mirror for persistSnapshot
                self.onCleared?(clearedNow)
                if let resolvedSelfLogin, resolvedSelfLogin != self.lastReportedSelfLogin {
                    self.lastReportedSelfLogin = resolvedSelfLogin
                    self.onSelfLogin?(resolvedSelfLogin)
                }
                let before = self.state
                let (next, effects) = PollReducer.reduce(.polled(radar: radar, pulse: pulseResult),
                                                         state: self.state, now: Date())
                self.state = next
                self.interpret(effects)
                // The inbound sweep rides its own reduce (Core-tested) right after the
                // tick's spine — so its render lands after radar/schedule/freshness/pulse,
                // and the `.polled` event + its test suite stay untouched.
                // Re-check `running` FIRST (review fix, arch finding 1): the `.polled`
                // reduce above can auth-stop the scheduler (a repo-scoped PAT 403s on
                // /notifications while /search still 200s) — the sweep must not render
                // or persist during a dead-token stop (the reducer's own auth-stop
                // invariant: the original state stays untouched).
                guard self.running else { return }
                let (swept, sweptEffects) = PollReducer.reduce(.sweptInbound(inboundResult),
                                                               state: self.state, now: Date())
                self.state = swept
                self.interpret(sweptEffects)
                if case .success(let reading) = inboundResult {
                    // Disclosure (review fix: no silent caps): the 50-cap and GitHub's own
                    // incompleteness are logged the tick they occur, never absorbed.
                    if reading.items.count < reading.totalCount {
                        self.log("inbound: truncated — showing oldest \(reading.items.count) of \(reading.totalCount)")
                    }
                    if reading.incomplete {
                        self.log("inbound: GitHub reported incomplete_results — reading kept, confirmation withheld")
                    } else {
                        self.onInboundConfirmed?()
                    }
                }
                // WP-4d seam — after interpret, so a success's rows land in the model BEFORE
                // the ledger checks its row (the completion morph then measures real data).
                // `attemptOutcome` (pure, tested) returns nil for auth-stops — they ride
                // onAuthFailure above.
                if let outcome = PollReducer.attemptOutcome(radar) {
                    // Radar-lane confirmation FIRST (WP-3d′ round 2): a `.success` here is
                    // the one live fact that means "the inbox was actually read" — fired
                    // whether or not this tick rendered (see onRadarConfirmed), and before
                    // the ledger event so a clearing card's morph measures confirmed state.
                    if outcome == .success { self.onRadarConfirmed?() }
                    self.onPollOutcome?(outcome)
                }
                // Reviews-owed confirmation (WP 2026-07-17-002): a COMPLETE sweep this
                // tick stamps provenance + fires the seam — the inbound-confirmation twin.
                if case .success(let r) = radarResult, r.reviewsComplete {
                    let firstThisRun = self.lastReviewsSuccessAt == nil
                    self.lastReviewsSuccessAt = Date()
                    self.onReviewsConfirmed?()
                    // The FIRST completion of a run must reach the snapshot even when no
                    // lane key moved (empty owed set, quiet inbox) — the cold-launch seed
                    // reads it, and without this write the next launch re-suppresses the
                    // affirmation a real sweep already earned (Codex P2, round 5). One
                    // extra write per process lifetime at most; every later stamp rides
                    // the content-change gate below, keeping the idle footprint intact.
                    if firstThisRun { self.persistSnapshot() }
                }
                // Persist last-known-good ONLY on a real content change (a lane key moved) —
                // never on age-flip re-renders, 304s, or failures. So the snapshot write
                // rides a data change, not every tick and not every render (idle-footprint).
                if swept.lastKey != before.lastKey || swept.lastPulseKey != before.lastPulseKey
                    || swept.lastInboundKey != before.lastInboundKey {
                    self.persistSnapshot()
                }
                // The 304-with-fresh-login re-projection (computed above, off-main): rides
                // the SAME reducer event a preference toggle does — an off-network
                // re-classification of cached threads. Runs after the polled reduce so the
                // tick's own schedule/freshness effects land first. `preferencesRecomputed`
                // renders unconditionally by design; when the re-projection changes nothing
                // that is one identical repaint — it does fire, its disruption is
                // neutralized rather than skipped (scroll + peeks stash-preserved), and it
                // happens at most once per process (the flag is one-shot). When it does
                // change something, the inbound rows appear NOW.
                if let radar = selfResolvedReprojection {
                    let (reprojected, reprojectionEffects) = PollReducer.reduce(
                        .preferencesRecomputed(radar), state: self.state, now: Date())
                    self.state = reprojected
                    self.interpret(reprojectionEffects)
                    self.log("radar: re-projected after self-login resolution (304 tick)")
                    // The reprojection lands AFTER the tick's persistence check above, so a
                    // 304-latched content change (a re-verified row resolving, an owed
                    // review departing) must persist HERE or a quit+relaunch resurrects the
                    // stale row from the old snapshot until the next live tick — offline,
                    // forever (Codex P2, WP-B round). Same rule as the tick's own gate:
                    // write only on a real radar-key move, never on the identical repaint.
                    if reprojected.lastKey != swept.lastKey {
                        self.persistSnapshot()
                    }
                }
            }
        }
    }

    /// Perform the reducer's effects, in order (the order IS the behavior: radar render →
    /// schedule → freshness → pulse render). Jitter and the Timer are added here, at the
    /// impure edge, keeping the reducer deterministic.
    private func interpret(_ effects: [PollReducer.Effect]) {
        for effect in effects {
            switch effect {
            case .renderRadar(let rows):
                onRadar(rows)
                log("radar: \(rows.count) rows (changed)")
            case .renderPulse(let rows):
                onPulse?(rows)
                log("pulse: \(rows.count) open PRs (changed)")
            case .renderInbound(let rows):
                onInbound?(rows)
                log("inbound: \(rows.count) at your door (changed)")
            case .emitFreshness(let freshness):
                onFreshness?(freshness)
                log("freshness → \(freshness)")
            case .emitSweepFreshness(let freshness):
                onSweepFreshness?(freshness)
                log("sweep freshness crossed → \(freshness)")
            case .scheduleNext(let seconds):
                log("next poll in \(seconds)s (+jitter)")
                scheduleNext(after: seconds)
            case .stopAndAuthFailure(let reason):
                // `reason` is an enum case (.invalidToken/.ssoOrScope), never the token — safe to log.
                log("auth failed (\(reason)) — token invalid/forbidden; stopping")
                stop()
                onAuthFailure?(reason)
            case .pollImmediately:
                log("pollNow: accepted — cancel pending timer, poll now")
                timer?.invalidate()
                timer = nil
                poll()
            }
        }
    }

    private func scheduleNext(after seconds: Int) {
        guard running else { return }
        let jitter = Int.random(in: 0...8)
        timer?.invalidate()
        // `.common` run-loop mode (NOT the `.default` that `Timer.scheduledTimer` uses):
        // an open NSMenu / menu-bar tracking session runs the loop in `.eventTracking`,
        // which would STALL a `.default`-mode timer until the menu closes. `.common`
        // includes the tracking modes, so the poll tick still fires while a menu is open.
        let poll = Timer(timeInterval: Double(seconds + jitter), repeats: false) { [weak self] _ in
            self?.poll()
        }
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    private func log(_ message: String) {
        if ProcessInfo.processInfo.environment["GITHUD_DEBUG"] != nil {
            FileHandle.standardError.write(Data("▸ live: \(message)\n".utf8))
        }
    }
}
