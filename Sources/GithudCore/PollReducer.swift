import Foundation

/// The pure decision core of the live poll loop — the trust-critical state machine that
/// was, until now, tangled inside `PollScheduler` (the only stateful object in the spine,
/// with zero tests). Extracted here so the zero-dep GithudCore runner can exercise EVERY
/// branch: 401/403 auth-stop, rate-limit pause, transient retry, 200/304 freshness, radar
/// change-detection, pulse change-detection, and reading-freshness transitions.
///
/// It is a pure function `(event, state, now) → (nextState, effects)`:
///   • no timers, no queues, no network, no AppKit — the SHELL (PollScheduler) owns those;
///   • the clock is INJECTED (`now`), so freshness transitions are deterministic in tests;
///   • JITTER stays at the shell edge (the shell adds 0…8s to a `.scheduleNext`), keeping
///     the reducer deterministic — the one intentional non-determinism lives outside it.
///
/// The shell feeds outcomes in, gets a list of `PollEffect`s back, and interprets them
/// (render radar / render pulse / emit freshness / schedule the next poll / stop+auth-fail).
/// Why the poll loop stopped authenticating — plumbed end-to-end (WP-4e) so the shell can
/// route each cause to its OWN calm, specific guidance instead of one generic "auth error".
/// The reducer produces `.invalidToken`/`.ssoOrScope` from the API status; `.wrongShape` is
/// produced at INTAKE/launch (a non-classic token never reaches the API — the WALL catches it
/// first, `notifications-classic-pat`). Carries no token or secret material — safe to log.
public enum AuthFailureReason: Equatable, Sendable {
    /// HTTP 401 — the token is invalid or expired (GitHub rejected the credential).
    case invalidToken
    /// A non-rate HTTP 403 — the token is forbidden: the org likely requires SSO
    /// authorization, or the token lacks the `notifications` scope.
    case ssoOrScope
    /// The token isn't a classic `ghp_` PAT — caught at intake/launch by `looksLikeClassicPAT`
    /// BEFORE any network call or Keychain write (the classic-PAT WALL), never from the API.
    case wrongShape
}

/// WP-4d seam vocabulary — ONE completed poll attempt's outcome, as the handshake-ledger
/// card needs it (fix round: the Bool seam couldn't tell a rate-limit from a network
/// failure, so the card called an ANSWERED request "no answer yet"). Auth-stops are not
/// an attempt outcome — they ride `onAuthFailure` (and stop the loop), so
/// `PollReducer.attemptOutcome` returns nil for them.
public enum PollAttemptOutcome: Equatable, Sendable {
    /// 200 or 304 — GitHub answered for the token.
    case success
    /// Transport/decode/unexpected — genuinely no answer; the loop retries in ~60s.
    case transientFailure
    /// GitHub answered "slow down" — an authenticated verdict, not silence. Carries the
    /// SAME pause the reducer schedules (`rateLimitPause`), so the card's copy and the
    /// actual retry can never disagree.
    case rateLimited(pauseSeconds: Int)
}

public enum PollReducer {

    // MARK: - State

    /// The mutable state threaded across poll ticks. Behavior-preserving copy of the
    /// fields that lived on `PollScheduler`; the shell keeps timer/running separately.
    public struct PollState: Equatable, Sendable {
        /// `nil` = no poll delivered yet, so the FIRST successful poll always renders even
        /// when the radar is empty (an empty radar's key `[]` still differs from `nil`,
        /// so the pill leaves "loading" and U6's caught-up gauge can appear).
        public var lastKey: [String]?
        public var lastPulseKey: [String]?
        /// Last time a poll SUCCEEDED (200 OR 304 — both confirm the data is current).
        public var lastSuccessAt: Date?
        /// Back-to-back failures since the last success (drives `.failing`). Rate-limit
        /// pauses do NOT count (the server is reachable — the data merely ages to `.stale`).
        public var consecutiveFailures: Int
        /// Last emitted reading-freshness — so freshness is emitted on CHANGE only.
        public var lastFreshness: Freshness
        /// H2-pulse mirror of `lastSuccessAt`/`consecutiveFailures` (WP-1b). The pulse is an
        /// INDEPENDENT lane (GraphQL, no 304) so it carries its own freshness signal, folded
        /// worst-of-both into the ONE caution cue. `lastPulseSuccessAt == nil` means the pulse
        /// has never produced last-good data → it renders nothing → there is no stale reading
        /// to distrust, so it contributes `.fresh` (the same "don't accuse before the first
        /// success" rule the radar's stale-age path applies). A pulse rate-limit, like the
        /// radar's, does NOT bump the streak (it ages toward `.stale` instead).
        public var lastPulseSuccessAt: Date?
        public var pulseConsecutiveFailures: Int
        /// When the most recent poll tick was reduced — the debounce base for `pollNow`
        /// (a request that just landed coalesces a fresh `pollNow` to nothing).
        public var lastPollAt: Date?
        /// End of an active rate-limit pause window, mirrored from the radar's scheduled
        /// pause. `pollNow` REFUSES while `now < pauseUntil` — honoring GitHub's reset
        /// outranks immediacy (the HARD requirement). `nil` on every non-rate outcome.
        public var pauseUntil: Date?

        /// Whether the island is currently EXPANDED (WP-1c). Live ages are only visible in the
        /// expanded list — the collapsed pill shows no per-row age — so a coarse-age-bucket flip
        /// re-render is emitted ONLY while expanded (a collapsed flip would rebuild an identical
        /// pill: invisible churn). Updated by `.expandChanged`.
        public var expanded: Bool
        /// The rows last handed to the view for each lane, retained so an age-bucket flip on a
        /// 304 tick (which carries NO fresh radar data) can re-emit the SAME structs — the view
        /// re-formats their age from `timestamp` at render, correcting a long-lived stale age
        /// with no content change. Replaced whenever fresh content renders.
        public var lastRenderedRadar: [RadarRow]?
        public var lastRenderedPulse: [PulseRow]?
        /// The displayed-age signature of those rows AT their last render — the flip baseline.
        /// A later tick recomputes the signature at its own `now`; a difference is a bucket flip.
        public var lastRadarAgeSig: [String]?
        public var lastPulseAgeSig: [String]?
        /// The inbound sweep lane (WP 2026-07-09-001) — same trio as the other lanes:
        /// change key, last-rendered rows, age-flip baseline. Reduced by its OWN event
        /// (`.sweptInbound`), so the `.polled` spine and its tests are untouched.
        public var lastInboundKey: [String]?
        public var lastRenderedInbound: [InboundRow]?
        public var lastInboundAgeSig: [String]?
        /// When a COMPLETE sweep last succeeded — the lane's confirmation fact (persisted
        /// to the snapshot like the other lanes' success times; an incomplete reading
        /// keeps the lane's rows but never stamps this).
        public var lastInboundSuccessAt: Date?
        /// The SWEEP clock's last computed freshness (D1, WP 2026-07-10-001 fix round F-1) —
        /// the change gate for `.emitSweepFreshness`. The pill's inbound tier reads the sweep
        /// clock, whose fresh↔stale crossing was otherwise render-silent: /notifications can
        /// 304 forever (poll clock fresh), sweeps can fail with an unchanged key, and a
        /// collapsed pill gets no age-flip renders — so a chronic "N waiting" would sit under
        /// fresh chrome indefinitely (the exact F3 fabrication D1 exists to close). Emission
        /// gates on the DEGRADED boolean crossing (never the ageing seconds — the pill's
        /// prefix is boolean), so it fires exactly once per crossing, in both directions.
        /// Defaults to the never-swept truth (`sweepStatus(nil)` = degraded): a session's
        /// first tick emits no fabricated "crossing" — never-swept was already the launch truth.
        public var lastSweepFreshness: Freshness

        public init(lastKey: [String]? = nil, lastPulseKey: [String]? = nil,
                    lastSuccessAt: Date? = nil, consecutiveFailures: Int = 0,
                    lastFreshness: Freshness = .fresh,
                    lastPulseSuccessAt: Date? = nil, pulseConsecutiveFailures: Int = 0,
                    lastPollAt: Date? = nil, pauseUntil: Date? = nil,
                    expanded: Bool = false,
                    lastRenderedRadar: [RadarRow]? = nil, lastRenderedPulse: [PulseRow]? = nil,
                    lastRadarAgeSig: [String]? = nil, lastPulseAgeSig: [String]? = nil,
                    lastInboundKey: [String]? = nil, lastRenderedInbound: [InboundRow]? = nil,
                    lastInboundAgeSig: [String]? = nil, lastInboundSuccessAt: Date? = nil,
                    lastSweepFreshness: Freshness = .stale(ageSeconds: 0)) {
            self.lastKey = lastKey
            self.lastPulseKey = lastPulseKey
            self.lastSuccessAt = lastSuccessAt
            self.consecutiveFailures = consecutiveFailures
            self.lastFreshness = lastFreshness
            self.lastPulseSuccessAt = lastPulseSuccessAt
            self.pulseConsecutiveFailures = pulseConsecutiveFailures
            self.lastPollAt = lastPollAt
            self.pauseUntil = pauseUntil
            self.expanded = expanded
            self.lastRenderedRadar = lastRenderedRadar
            self.lastRenderedPulse = lastRenderedPulse
            self.lastRadarAgeSig = lastRadarAgeSig
            self.lastPulseAgeSig = lastPulseAgeSig
            self.lastInboundKey = lastInboundKey
            self.lastRenderedInbound = lastRenderedInbound
            self.lastInboundAgeSig = lastInboundAgeSig
            self.lastInboundSuccessAt = lastInboundSuccessAt
            self.lastSweepFreshness = lastSweepFreshness
        }
    }

    // MARK: - Input

    /// A narrow, Core-side view of one notifications refresh — exactly the fields the
    /// polling decisions read. The shell maps the fuller `RadarPipeline.Result` (which
    /// carries probe/debug fields + AppKit-adjacent context) onto this, so the reducer
    /// stays AppKit-free and the protocol/snapshot split keeps GithudCore pure.
    public struct RadarRefresh: Equatable, Sendable {
        public let notModified: Bool     // true = 304 (no rate cost, data unchanged)
        public let nextPollAfter: Int    // seconds the shell should wait (before jitter)
        public let radar: [RankedThread] // the action-required set (already classified/ranked)

        public init(notModified: Bool, nextPollAfter: Int, radar: [RankedThread]) {
            self.notModified = notModified
            self.nextPollAfter = nextPollAfter
            self.radar = radar
        }
    }

    /// What just happened that the reducer must interpret.
    public enum Event {
        /// One poll tick: the notifications refresh AND the (independent, non-fatal) pulse
        /// fetch. Bundled so a single reduce produces the tick's full effect set in order.
        case polled(radar: Result<RadarRefresh, GitHubClientError>,
                    pulse: Result<[PullRequestPulse], GitHubClientError>)
        /// The user toggled which reasons surface; the shell already recomputed the radar
        /// from the cached threads OFF-network. Re-render immediately + adopt the new key
        /// (unconditional — never gated on change).
        case preferencesRecomputed([RankedThread])
        /// A real external event (wake-from-sleep, a network path change, a panel expand)
        /// asks for an immediate poll. The reducer DECIDES accept/refuse (debounce + the
        /// rate-limit-pause guard) so both facts are unit-tested; the shell owns only the
        /// in-flight guard + the actual timer cancel/fire. No state is mutated here.
        case pollNowRequested
        /// The island expanded (true) or collapsed (false). Records `expanded` so poll ticks
        /// know whether an age-bucket flip is VISIBLE (only the expanded list shows per-row
        /// ages). Emits NO effects — the expand's own render is the panel's (WP-3e), and on
        /// expand it re-baselines the age signatures to `now` so the next tick measures flips
        /// from the expand moment (the panel already painted fresh ages).
        case expandChanged(Bool)
        /// One inbound sweep landed (WP 2026-07-09-001): the ADOPTED reading (the pipeline
        /// already applied `InboundReading.adopt` — an incomplete search never removed
        /// anything). A failure keeps the last-good lane, exactly like the pulse; the
        /// sweep deliberately does NOT feed the freshness cue (recorded lane decision:
        /// week-scale queue ages don't turn misleading on the pulse/radar's timescale,
        /// and the shared client pause already degrades the spine's own freshness).
        /// Carrying the READING (not just items) lets the reducer stamp
        /// `lastInboundSuccessAt` only for COMPLETE sweeps — the inbound-confirmation
        /// fact the affirmation gates on (fix round: an incomplete first sweep must
        /// never let an empty-looking queue read as confirmed-empty).
        case sweptInbound(Result<InboundReading, GitHubClientError>)
    }

    /// A poll that landed within this window coalesces a fresh `pollNow` to nothing — one
    /// wake + one path-change firing back-to-back does not double-poll. Lives in the pure
    /// reducer so the debounce is a tested fact, not shell trivia.
    public static let pollNowDebounce: TimeInterval = 5

    // MARK: - Output

    /// One side effect for the shell to perform, in list order. Keeping these as data
    /// (not direct calls) is what makes the decisions unit-testable. Order matters and is
    /// preserved exactly: radar render → schedule → freshness → pulse render (the same
    /// callback order the pre-refactor `PollScheduler` produced).
    public enum Effect: Equatable, Sendable {
        case renderRadar([RadarRow])
        case renderPulse([PulseRow])
        case renderInbound([InboundRow])
        case emitFreshness(Freshness)
        /// The SWEEP clock crossed fresh↔stale (D1, F-1): the pill's inbound tier must
        /// repaint its stale prefix NOW — no other effect is guaranteed to fire (a 304-ing
        /// poll clock + an unchanged lane key + a collapsed pill are all render-silent).
        /// Emitted exactly once per boolean crossing, both directions (the stale→fresh
        /// direction un-sticks a stuck prefix after a recovering sweep with an unchanged
        /// key). Rides the existing tick — no timer.
        case emitSweepFreshness(Freshness)
        /// Base seconds until the next poll. The SHELL adds 0…8s jitter (randomness stays
        /// outside the pure reducer) and owns the actual Timer.
        case scheduleNext(afterSeconds: Int)
        /// A dead/forbidden token (401, or a non-rate 403 = scope/SSO): stop polling and
        /// fire `onAuthFailure` once, carrying WHY (WP-4e) so the shell shows reason-specific
        /// guidance. Terminal — the reading isn't "stale", it's unauthenticated, so NO
        /// freshness cue and the pulse is NOT applied.
        case stopAndAuthFailure(AuthFailureReason)
        /// `pollNow` was accepted: the shell cancels the pending timer and polls at once
        /// (the normal `.scheduleNext` from that poll resumes the cadence). Emitted ONLY
        /// when not paused and not debounced — so it never bypasses a rate-limit pause.
        case pollImmediately
    }

    // MARK: - Reduce

    public static func reduce(_ event: Event, state: PollState, now: Date,
                              staleAfter: TimeInterval = FreshnessModel.defaultStaleAfter,
                              failureThreshold: Int = FreshnessModel.defaultFailureThreshold)
        -> (PollState, [Effect]) {
        switch event {
        case .preferencesRecomputed(let radar):
            // Off-network re-render: adopt the recomputed key and render UNCONDITIONALLY
            // (the user just changed the filter — they must see the effect immediately).
            var s = state
            s.lastKey = RadarPresenter.changeKey(for: radar)
            let rows = RadarPresenter.rows(for: radar, now: now)
            // The RETAINED rows must follow the user's filter (WP-1c review, Blocker A): the
            // age-flip path re-emits `lastRenderedRadar`, so leaving the PRE-filter set here
            // would let a later bucket flip resurface rows the user just filtered out —
            // silently reverting a user action. Adopt rows + age baseline exactly like a
            // fresh content render does.
            s.lastRenderedRadar = rows
            s.lastRadarAgeSig = RadarPresenter.ageSignature(for: rows, now: now)
            return (s, [.renderRadar(rows)])

        case .polled(let radarResult, let pulseResult):
            return reducePoll(radarResult, pulseResult, state: state, now: now,
                              staleAfter: staleAfter, failureThreshold: failureThreshold)

        case .pollNowRequested:
            return reducePollNow(state: state, now: now)

        case .expandChanged(let value):
            var s = state
            s.expanded = value
            // On expand, re-baseline the age-flip signatures to `now`: the panel just painted
            // fresh ages (WP-3e), so the next tick should compare against THIS moment, not a
            // stale pre-collapse baseline (which would fire one redundant re-render). No effects.
            if value {
                if let rows = s.lastRenderedRadar { s.lastRadarAgeSig = RadarPresenter.ageSignature(for: rows, now: now) }
                if let rows = s.lastRenderedPulse { s.lastPulseAgeSig = PulsePresenter.ageSignature(for: rows, now: now) }
                if let rows = s.lastRenderedInbound { s.lastInboundAgeSig = InboundPresenter.ageSignature(for: rows, now: now) }
            }
            return (s, [])

        case .sweptInbound(let result):
            var s = state
            // Failure keeps the last-good lane whole (no flicker-to-empty, no fabricated
            // "nothing at your door" — the pulse's own failure rule).
            guard case .success(let reading) = result else { return (s, []) }
            // The confirmation fact: only a COMPLETE sweep counts as having READ the
            // queue (an incomplete one shows its true items but confirms nothing).
            if !reading.incomplete { s.lastInboundSuccessAt = now }
            let items = reading.items
            let key = InboundPresenter.changeKey(for: items)
            if key != s.lastInboundKey {
                s.lastInboundKey = key
                let rows = InboundPresenter.rows(for: items)
                s.lastRenderedInbound = rows
                s.lastInboundAgeSig = InboundPresenter.ageSignature(for: rows, now: now)
                return (s, [.renderInbound(rows)])
            }
            // Same facts — re-render ONLY on a visible coarse-age-bucket flip (the WP-1c
            // contract the other lanes follow; collapsed flips are invisible churn).
            if s.expanded, let rows = s.lastRenderedInbound {
                let sig = InboundPresenter.ageSignature(for: rows, now: now)
                if sig != s.lastInboundAgeSig {
                    s.lastInboundAgeSig = sig
                    return (s, [.renderInbound(rows)])
                }
            }
            return (s, [])
        }
    }

    /// Accept/refuse an immediate-poll request. Two refusals, HARD guard first:
    ///   1. an active rate-limit pause (`now < pauseUntil`) — honoring GitHub's reset
    ///      OUTRANKS immediacy, so a wake/path-change during a pause is refused outright;
    ///   2. a poll that landed within `pollNowDebounce` — coalesce (no double-poll).
    /// Otherwise `.pollImmediately`. State is never mutated (the accepted poll's own
    /// `.polled` reduction stamps `lastPollAt`); the shell's in-flight guard is the third,
    /// shell-owned refusal (the reducer can't see an in-flight request).
    private static func reducePollNow(state: PollState, now: Date) -> (PollState, [Effect]) {
        if let pauseUntil = state.pauseUntil, now < pauseUntil {
            return (state, [])
        }
        if let last = state.lastPollAt, now.timeIntervalSince(last) < pollNowDebounce {
            return (state, [])
        }
        return (state, [.pollImmediately])
    }

    private static func reducePoll(_ radarResult: Result<RadarRefresh, GitHubClientError>,
                                   _ pulseResult: Result<[PullRequestPulse], GitHubClientError>,
                                   state: PollState, now: Date,
                                   staleAfter: TimeInterval, failureThreshold: Int)
        -> (PollState, [Effect]) {
        var s = state
        // The four effect slots, assembled at the end in the documented order:
        // radar-render → schedule → freshness → pulse-render.
        var radarRender: Effect?
        var scheduleEffect: Effect?

        switch radarResult {
        case .failure(let error):
            switch classify(error) {
            case .authStop(let reason):
                // 401 or non-rate 403 → terminal. Return the ORIGINAL state untouched
                // (no freshness, no pulse, no failure count, no lastPollAt): the token is
                // dead, not late — polling stops, so debounce/pause bookkeeping is moot.
                // The reason (401→.invalidToken, 403→.ssoOrScope) rides the effect (WP-4e).
                return (state, [.stopAndAuthFailure(reason)])
            case .rateLimited(let retryAfter):
                // Honor GitHub's reset. NOT counted as a freshness failure (server is
                // reachable) — the data just ages into `.stale` if the pause runs long.
                // Record the pause window so `pollNow` refuses to bypass it (HARD req).
                let pause = rateLimitPause(retryAfter: retryAfter)
                s.pauseUntil = now.addingTimeInterval(TimeInterval(pause))
                scheduleEffect = .scheduleNext(afterSeconds: pause)
            case .transient:
                // Genuine transport/decode/unexpected failure → the reading ages.
                s.consecutiveFailures += 1
                s.pauseUntil = nil          // not a rate-limit: pollNow may retry (debounced)
                scheduleEffect = .scheduleNext(afterSeconds: 60)
            }

        case .success(let refresh):
            // 200 OR 304 both CONFIRM the data is current → the reading is fresh.
            s.lastSuccessAt = now
            s.consecutiveFailures = 0
            s.pauseUntil = nil              // a poll just landed: no active pause
            if !refresh.notModified {
                // A 200: re-render only when the display-affecting key actually changes.
                // First poll: `lastKey` is nil, so any key (even `[]`) renders → the pill
                // leaves "loading" even for an empty radar.
                let key = RadarPresenter.changeKey(for: refresh.radar)
                if key != s.lastKey {
                    s.lastKey = key
                    let rows = RadarPresenter.rows(for: refresh.radar, now: now)
                    s.lastRenderedRadar = rows
                    s.lastRadarAgeSig = RadarPresenter.ageSignature(for: rows, now: now)
                    radarRender = .renderRadar(rows)
                }
            }
            scheduleEffect = .scheduleNext(afterSeconds: refresh.nextPollAfter)
        }

        // Every tick that reached here (not auth-stop) is a completed poll → debounce base.
        s.lastPollAt = now

        // Pulse: independent + non-fatal. Folded into state BEFORE freshness (so the
        // worst-of-both cue sees it), but its RENDER effect is deferred to keep the
        // callback order radar-render → schedule → freshness → pulse-render (WP-1b).
        var pulseRender: Effect?
        switch pulseResult {
        case .success(let pulses):
            s.lastPulseSuccessAt = now
            s.pulseConsecutiveFailures = 0
            let key = PulsePresenter.changeKey(for: pulses)
            if key != s.lastPulseKey {
                s.lastPulseKey = key
                let rows = PulsePresenter.rows(for: pulses, now: now)
                s.lastRenderedPulse = rows
                s.lastPulseAgeSig = PulsePresenter.ageSignature(for: rows, now: now)
                pulseRender = .renderPulse(rows)
            }
        case .failure(let error):
            // Keep the last good pulse (no flicker-to-empty). A rate-limit does NOT bump
            // the streak (symmetry with the radar: the server is reachable, the pulse just
            // ages toward `.stale`); any other failure means the pulse couldn't refresh →
            // it counts, and after `failureThreshold` the reading degrades to `.failing`.
            // (A pulse-only rate-limit needs no `pauseUntil` here: it set the CLIENT-level
            // shared pause, so the next radar refresh fail-fasts and pauses the spine — the
            // real anti-hammer guard. `pauseUntil` mirrors the radar's scheduled pause.)
            if case .rateLimited = error {
                break
            } else {
                s.pulseConsecutiveFailures += 1
            }
        }

        // LIVE AGES — coarse-age-bucket flip re-render (WP-1c). When a lane did NOT freshly
        // render this tick (a 304, or an unchanged 200/failure) AND the island is EXPANDED (the
        // only state that shows per-row ages), re-emit the SAME rows if their displayed-age
        // bucket flipped since the last render — the view re-formats age at render, so re-emitting
        // the identical structs corrects a long-lived stale age. Rides the EXISTING poll tick (NO
        // new timer); gated on `expanded` so the collapsed pill (ageless) never rebuilds on an
        // invisible flip; gated on `radarRender == nil` so a fresh render (already carrying the
        // right age) is never duplicated. Between-tick staleness is bounded by one poll interval.
        if radarRender == nil, s.expanded, let rows = s.lastRenderedRadar {
            let sig = RadarPresenter.ageSignature(for: rows, now: now)
            if sig != s.lastRadarAgeSig {
                s.lastRadarAgeSig = sig
                radarRender = .renderRadar(rows)
            }
        }
        if pulseRender == nil, s.expanded, let rows = s.lastRenderedPulse {
            let sig = PulsePresenter.ageSignature(for: rows, now: now)
            if sig != s.lastPulseAgeSig {
                s.lastPulseAgeSig = sig
                pulseRender = .renderPulse(rows)
            }
        }

        // WORST-OF-BOTH reading freshness (WP-1b): fold the notifications lane and the
        // pulse lane through the SAME thresholds, then surface the more-degraded of the
        // two through the ONE existing caution cue. Symmetry: a single transient pulse
        // blip (1 failure) no more degrades the reading than a single radar blip does.
        // The pulse contributes degradation ONLY once it has last-good data on screen
        // (`lastPulseSuccessAt != nil`) — before its first success there is nothing shown
        // to distrust. Emitted on CHANGE only (a steady `.fresh` adds no chrome).
        let radarFreshness = FreshnessModel.status(lastSuccess: s.lastSuccessAt, now: now,
                                                   consecutiveFailures: s.consecutiveFailures,
                                                   staleAfter: staleAfter, failureThreshold: failureThreshold)
        let pulseFreshness: Freshness = s.lastPulseSuccessAt == nil ? .fresh
            : FreshnessModel.status(lastSuccess: s.lastPulseSuccessAt, now: now,
                                    consecutiveFailures: s.pulseConsecutiveFailures,
                                    staleAfter: staleAfter, failureThreshold: failureThreshold)
        let freshness = FreshnessModel.worst(radarFreshness, pulseFreshness)
        var freshnessEffect: Effect?
        if freshness != s.lastFreshness {
            s.lastFreshness = freshness
            freshnessEffect = .emitFreshness(freshness)
        }

        // D1 SWEEP-CLOCK crossing (WP 2026-07-10-001 fix round F-1) — the sweep clock's own
        // emission, mirroring the poll clock's block above but gated on the DEGRADED boolean:
        // the pill's stale prefix is boolean, so only the fresh↔stale crossing repaints —
        // never the ageing seconds (steady-degraded ticks emit nothing; idle-footprint). Rides
        // this existing tick with the injected `now` (no timer). Both directions matter: the
        // fresh→stale crossing surfaces a chronic count's dead clock under an otherwise-fresh
        // spine (304s keep landing, no key moves, collapsed = no age-flip renders — the exact
        // F3 fabrication); the stale→fresh crossing un-sticks the prefix after a recovering
        // sweep with an unchanged key (which renders nothing of its own). The .sweptInbound
        // reduce stamps `lastInboundSuccessAt` after this event within a tick, so a recovery's
        // clearing crossing lands on the NEXT tick — bounded by one poll interval.
        let sweepFreshness = FreshnessModel.sweepStatus(lastSweepSuccess: s.lastInboundSuccessAt,
                                                        now: now, staleAfter: staleAfter)
        var sweepEffect: Effect?
        if sweepFreshness.isDegraded != s.lastSweepFreshness.isDegraded {
            sweepEffect = .emitSweepFreshness(sweepFreshness)
        }
        s.lastSweepFreshness = sweepFreshness

        // Assemble in the historical order: radar render → schedule → freshness → pulse
        // render — the new sweep crossing appends last (existing consumers see their order
        // byte-identical).
        let effects = [radarRender, scheduleEffect, freshnessEffect, pulseRender, sweepEffect].compactMap { $0 }
        return (s, effects)
    }

    // MARK: - WP-4d attempt-outcome seam (pure, tested — the shell just forwards)

    /// The ONE home of the rate-limit pause formula — `reducePoll` schedules with it and
    /// `attemptOutcome` reports with it, so the card's "retrying in ~Xm" can never claim
    /// a different wait than the reducer actually takes.
    public static func rateLimitPause(retryAfter: Int?) -> Int { max(60, retryAfter ?? 60) }

    /// Map one radar refresh result onto the ledger seam's vocabulary. `nil` = an
    /// auth-stop (401 / non-rate 403) — not an attempt outcome; it rides `onAuthFailure`.
    /// Uses the SAME `classify` the reducer's own decisions use, so the seam can never
    /// disagree with the poll loop about what just happened.
    public static func attemptOutcome<T>(_ result: Result<T, GitHubClientError>) -> PollAttemptOutcome? {
        switch result {
        case .success:
            return .success
        case .failure(let error):
            switch classify(error) {
            case .authStop:
                return nil
            case .rateLimited(let retryAfter):
                return .rateLimited(pauseSeconds: rateLimitPause(retryAfter: retryAfter))
            case .transient:
                return .transientFailure
            }
        }
    }

    // MARK: - Error taxonomy

    private enum RadarErrorKind {
        case authStop(AuthFailureReason)    // 401 (invalid), or a non-rate 403 (scope/SSO)
        case rateLimited(retryAfter: Int?)  // primary/secondary limit → pause + reschedule
        case transient                      // transport/decode/unexpected → retry in 60s
    }

    /// Behavior-preserving mapping of the pre-refactor `poll()` cascade. Real rate limits
    /// arrive as `.rateLimited` (converted upstream in GitHubClient), so a bare `.http(403,_)`
    /// reaching here is genuinely scope/SSO → auth-stop, never a limit to wait out. WP-4e
    /// distinguishes the two auth statuses so the shell routes 401 vs 403 to distinct copy.
    private static func classify(_ error: GitHubClientError) -> RadarErrorKind {
        switch error {
        case .http(401, _):                     return .authStop(.invalidToken)
        case .http(403, _):                     return .authStop(.ssoOrScope)
        case .rateLimited(let retryAfter):      return .rateLimited(retryAfter: retryAfter)
        default:                                return .transient
        }
    }
}
