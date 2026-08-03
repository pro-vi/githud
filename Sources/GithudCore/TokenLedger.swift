import Foundation

/// WP-4d — the handshake-ledger card's pure state machine (the ratified D-card pick,
/// `handshake-ledger`). The numbered setup steps ARE a live ledger of real system events —
/// Token / Keychain / GitHub — each row checked only when its underlying call actually
/// returned, errors landing on the exact row that failed, and the success morph gated on
/// GitHub genuinely answering (the first successful poll), never on a mere Keychain store.
///
/// This is the same never-fabricate contract `pulse-honesty` enforces, on the app's single
/// highest-leverage trust surface: **the card can never claim a state the system can't
/// back.** Concretely:
/// - "connected" requires GitHub's actual answer (the first-poll-outcome seam);
/// - a wrong-shape token fails row 1 and leaves rows 2–3 PENDING (progress is never
///   fabricated);
/// - a Keychain write failure fails row 2 (row 1 keeps its true receipt — the shape gate
///   really did pass);
/// - a runtime 401/403 re-presents the SAME card with rows 1–2 pre-checked (true facts — a
///   token exists in the Keychain) and row 3 failed: the error family is one species, the
///   failing row;
/// - a first poll that fails WITHOUT an auth failure must not sit on "verifying…"
///   unbounded — it becomes a static caution line (the sanctioned degraded-reading
///   treatment; NO spinner, ever), updated only by real attempt outcomes: "no answer
///   yet — retrying" for genuine silence, "rate limited — retrying in ~Xm" for GitHub's
///   own slow-down verdict (an answered request may never read as silence — fix round);
/// - a valid re-submit restarts the handshake instantly (a restart is not progress — the
///   view renders it with no animation); a REJECTED paste fails row 1 only, leaving the
///   active token's receipts (rows 2–3) truthful, and outcome events are
///   generation-stamped so a stale session can never touch a handshake it doesn't own;
/// - an env-sourced token (`GITHUD_PAT`) never fabricates a "stored" receipt — row 2
///   states "from environment" with a pending slot.
///
/// Pure data, no AppKit — events map 1:1 to the real callbacks in `AppDelegate`
/// (`submitToken`'s gates, `startLiveSession`, the poll-outcome seam, `onAuthFailure`);
/// the AppKit card (`LedgerCardView`) only renders the `Card` descriptor. House style:
/// tested like `PulsePresenter`/`StatusGlyphPresenter`.
///
/// Every string here is the ratified D-copy voice (`voice-plainspoken` AS AMENDED):
/// second person, sentence case, GitHub's own nouns; the 401 line keeps "invalid or
/// expired" (a never-valid token also 401s — the record-wide binding rule); no string
/// claims more than the system event it binds to.
public enum TokenLedger {

    /// The one external URL every card state offers (the action ceiling: Open-on-GitHub).
    public static let settingsURL = "https://github.com/settings/tokens"

    // MARK: - State (one phase per ledger row)

    /// Row 1 — "Token": did a classic-shaped token pass the intake WALL?
    public enum TokenPhase: Equatable, Sendable {
        case pending
        /// The shape gate passed; `redacted` is the REAL `KeychainPAT.redacted` form
        /// ("ghp_•(40)") — the only form of the secret that ever renders anywhere.
        case done(redacted: String)
        /// `looksLikeClassicPAT` rejected it (fine-grained / App token / truncated paste).
        case failedShape
    }

    /// Row 2 — "Keychain": did `KeychainPAT.store` return success?
    public enum KeychainPhase: Equatable, Sendable {
        case pending, done, failed
        /// The active token came from the `GITHUD_PAT` environment, NOT from a Keychain
        /// store (fix round: a receipt may never claim a store that didn't happen). The
        /// slot stays the pending circle; the detail states the true provenance.
        case environment
    }

    /// Row 3 — "GitHub": has GitHub actually answered for the token?
    public enum GitHubPhase: Equatable, Sendable {
        case pending
        /// `startLiveSession` began — STATIC text, deliberately no spinner (honest
        /// stillness; the words state the fact, motion would fabricate activity).
        case verifying
        /// A poll attempt genuinely got no answer (transport/decode) — the bounded
        /// caution exit off "verifying…". The scheduler really is retrying in ~60s.
        case retrying
        /// GitHub answered "slow down" (fix round: an authenticated rate-limit verdict is
        /// an ANSWER, not silence — it may never render as "no answer yet"). Carries the
        /// reducer's real pause so the copy states the actual wait.
        case rateLimited(pauseSeconds: Int)
        /// The first successful poll landed — GitHub answered for the token.
        case connected
        /// 401 (invalid/expired) or non-rate 403 (SSO/scope) — the reason picks the glyph.
        case failed(AuthFailureReason)
    }

    public struct State: Equatable, Sendable {
        public var token: TokenPhase
        public var keychain: KeychainPhase
        public var github: GitHubPhase
        /// The live session this handshake is bound to (fix round, finding 10): outcome
        /// events carry the generation of the session that produced them, and `reduce`
        /// drops any outcome whose generation doesn't match — a stale session's answer
        /// can never check (or fail) a handshake it doesn't belong to.
        public var sessionGeneration: Int

        public init(token: TokenPhase = .pending,
                    keychain: KeychainPhase = .pending,
                    github: GitHubPhase = .pending,
                    sessionGeneration: Int = 0) {
            self.token = token
            self.keychain = keychain
            self.github = github
            self.sessionGeneration = sessionGeneration
        }
    }

    /// First-run: no token found — three pending receipts, nothing claimed.
    public static func welcome() -> State { State() }

    /// A runtime auth failure with NO card up re-presents this same card, pre-filled with
    /// only TRUE facts: a 401/403 means an active classic-shaped token was used, so row 1
    /// shows done (`redacted` should be the real stashed form; the "ghp_…" fallback claims
    /// only the shape every live token provably passed) and row 3 carries the failure.
    /// Row 2 is done ONLY when the token really lives in the Keychain — an env-sourced
    /// `GITHUD_PAT` token renders `.environment` instead (fix round: a receipt may never
    /// claim a store that didn't happen). A wrong-shape token (caught at launch,
    /// pre-network) failed row 1 — rows 2–3 pending.
    public static func runtimeFailure(reason: AuthFailureReason, redacted: String?,
                                      storedInKeychain: Bool = true) -> State {
        switch reason {
        case .wrongShape:
            return State(token: .failedShape)
        case .invalidToken, .ssoOrScope:
            return State(token: .done(redacted: redacted ?? "ghp_…"),
                         keychain: storedInKeychain ? .done : .environment,
                         github: .failed(reason))
        }
    }

    // MARK: - Events (each maps 1:1 to a real callback — never a timer, never a guess)

    public enum Event: Equatable, Sendable {
        /// A full reset: every row back to pending, instantly (a reset is not progress).
        case reset
        /// `looksLikeClassicPAT` rejected the paste BEFORE any write (the WALL). Fails
        /// row 1 ONLY — rows 2–3 keep describing the ACTIVE token truthfully (fix round,
        /// finding 10: a moot paste must not wipe a live handshake's real receipts).
        case shapeRejected
        /// The shape gate passed AND `KeychainPAT.store` returned success — two events that
        /// truly happened, in that order (the view staggers their checks 0/150ms on exactly
        /// that order). A new store restarts the whole handshake.
        case stored(redacted: String)
        /// The shape gate passed but the Keychain write failed.
        case keychainWriteFailed(redacted: String)
        /// `startLiveSession` began for session `generation` — row 3 flips to "verifying…"
        /// and the handshake binds to that generation.
        case sessionStarted(generation: Int)
        /// A poll attempt SUCCEEDED (200/304 — GitHub answered for the token).
        case pollSucceeded(generation: Int)
        /// A poll attempt genuinely got no answer (transport/decode) — the loop retries.
        case pollFailed(generation: Int)
        /// GitHub answered "slow down" — rate-limited for the reducer's real pause.
        case pollRateLimited(pauseSeconds: Int, generation: Int)
        /// The reason-routed auth failure (`onAuthFailure`).
        case authFailed(AuthFailureReason)
    }

    /// Map the poll seam's vocabulary (`PollReducer.attemptOutcome`) onto a ledger event,
    /// stamped with the session generation the outcome came from. Pure + tested — the
    /// shell (AppDelegate) forwards, it never re-derives.
    public static func event(for outcome: PollAttemptOutcome, generation: Int) -> Event {
        switch outcome {
        case .success:
            return .pollSucceeded(generation: generation)
        case .transientFailure:
            return .pollFailed(generation: generation)
        case .rateLimited(let pauseSeconds):
            return .pollRateLimited(pauseSeconds: pauseSeconds, generation: generation)
        }
    }

    public static func reduce(_ state: State, _ event: Event) -> State {
        switch event {
        case .reset:
            return State()

        case .shapeRejected:
            // The WALL fired before any write: row 1 fails; rows 2–3 are UNTOUCHED —
            // they are receipts about the active token (pending on first run, live
            // verifying/connected/failed receipts when a session already runs), and a
            // rejected paste changes none of those facts. Progress is never fabricated
            // AND truth is never wiped.
            var s = state
            s.token = .failedShape
            return s

        case .stored(let redacted):
            // A fresh store CHANGES the active token → the handshake restarts; row 3
            // waits for its own real events (rendered instantly, no animation — a
            // restart is not progress).
            return State(token: .done(redacted: redacted), keychain: .done)

        case .keychainWriteFailed(let redacted):
            return State(token: .done(redacted: redacted), keychain: .failed)

        case .sessionStarted(let generation):
            // A live session can only follow a real store (or a pre-existing stored token,
            // whose runtime card is constructed with keychain == .done). Anything else is a
            // stray event — ignored, never fabricated into progress.
            guard state.keychain == .done, state.github != .connected else { return state }
            var s = state
            s.github = .verifying
            s.sessionGeneration = generation
            return s

        case .pollSucceeded(let generation):
            // "connected" ONLY off a real answer, from THIS handshake's own session,
            // while it is actually awaiting one.
            guard generation == state.sessionGeneration, isAwaitingAnswer(state.github) else { return state }
            var s = state
            s.github = .connected
            return s

        case .pollFailed(let generation):
            // The bounded exit off "verifying…" — and it stays put across repeated failed
            // attempts (identical state → the model's equality guard emits no render).
            guard generation == state.sessionGeneration, isAwaitingAnswer(state.github) else { return state }
            var s = state
            s.github = .retrying
            return s

        case .pollRateLimited(let pauseSeconds, let generation):
            guard generation == state.sessionGeneration, isAwaitingAnswer(state.github) else { return state }
            var s = state
            s.github = .rateLimited(pauseSeconds: pauseSeconds)
            return s

        case .authFailed(let reason):
            switch reason {
            case .wrongShape:
                // Intake-shaped failure routed defensively: same landing as `.shapeRejected`.
                var s = state
                s.token = .failedShape
                return s
            case .invalidToken, .ssoOrScope:
                // An API auth verdict implies an active token was used; it lands on row 3 —
                // even a just-"connected" card yields (GitHub's newest answer outranks a
                // stale celebration; the completion hold re-checks and stands down). Not
                // generation-stamped: the failing scheduler stops itself, and a rejection
                // is never staler than a celebration.
                guard state.keychain == .done || state.keychain == .environment else { return state }
                var s = state
                s.github = .failed(reason)
                return s
            }
        }
    }

    /// Row 3 is awaiting GitHub's answer (the only phases a poll outcome may move).
    private static func isAwaitingAnswer(_ phase: GitHubPhase) -> Bool {
        switch phase {
        case .verifying, .retrying, .rateLimited: return true
        case .pending, .connected, .failed: return false
        }
    }

    /// All three receipts checked — the caller holds ~700ms, then the card morphs into
    /// the live pill (the morph is the celebration; no interstitial claim).
    public static func isComplete(_ state: State) -> Bool {
        guard case .done = state.token else { return false }
        guard state.keychain == .done else { return false }
        return state.github == .connected
    }

    // MARK: - Descriptor (what the AppKit card renders — strings + slot states, no logic)

    /// One row's state slot. Failed carries the per-reason SF Symbol NAME so shape (not
    /// hue alone) disambiguates the reason — the gray-swap law.
    public enum SlotState: Equatable, Sendable {
        case pending                    // empty circle, 1.5px border
        case done                       // ink check, 120ms fade fired ONLY by the real callback
        case failed(symbol: String)     // per-reason glyph in danger (triangle / key-slash / lock-shield)
    }

    /// How the detail text is inked. `caution` is the ONE sanctioned degraded-reading
    /// treatment (the network-failure exit); everything else is ordinary ink.
    public enum DetailStyle: Equatable, Sendable {
        case placeholder    // tertiary ink (e.g. "paste a classic token below")
        case plain          // secondary ink (facts: "stored", "verifying…", "connected")
        case mono           // secondary ink, monospaced — the redacted token receipt
        case caution        // theme.caution — "no answer yet — retrying"
    }

    public struct Row: Equatable, Sendable {
        public let label: String
        public let slot: SlotState
        public let detail: String
        public let detailStyle: DetailStyle
        /// The plainspoken remedy sentence under a failed row (nil otherwise). The view
        /// appends the `settingsLinkTitle` link after it.
        public let remedy: String?
    }

    public struct Card: Equatable, Sendable {
        public let title: String
        public let promise: String
        public let rows: [Row]          // always Token / Keychain / GitHub, in that order
        public let fieldPlaceholder: String
        public let submitTitle: String
        public let footerCaption: String
        public let createLinkTitle: String
        public let settingsLinkTitle: String
        public let settingsURL: String
        /// All three receipts checked — the caller's morph gate.
        public let isComplete: Bool
    }

    // Per-reason glyphs (SF Symbol names — shape disambiguates on gray-swap).
    static let wrongShapeSymbol = "exclamationmark.triangle.fill"
    static let invalidTokenSymbol = "key.slash"
    static let ssoOrScopeSymbol = "lock.shield.fill"
    static let keychainFailSymbol = "exclamationmark.triangle.fill"

    public static func card(for state: State) -> Card {
        let tokenRow: Row
        switch state.token {
        case .pending:
            tokenRow = Row(label: "Token", slot: .pending,
                           detail: "paste a classic token below", detailStyle: .placeholder,
                           remedy: nil)
        case .done(let redacted):
            tokenRow = Row(label: "Token", slot: .done,
                           detail: redacted, detailStyle: .mono, remedy: nil)
        case .failedShape:
            tokenRow = Row(label: "Token", slot: .failed(symbol: wrongShapeSymbol),
                           detail: "paste a classic token below", detailStyle: .placeholder,
                           remedy: "That's not a classic token — it should start with ghp_. "
                                 + "Fine-grained and App tokens can't read notifications. "
                                 + "Create a classic token (notifications scope) instead.")
        }

        let keychainRow: Row
        switch state.keychain {
        case .pending:
            keychainRow = Row(label: "Keychain", slot: .pending,
                              detail: "—", detailStyle: .placeholder, remedy: nil)
        case .done:
            keychainRow = Row(label: "Keychain", slot: .done,
                              detail: "stored", detailStyle: .plain, remedy: nil)
        case .failed:
            keychainRow = Row(label: "Keychain", slot: .failed(symbol: keychainFailSymbol),
                              detail: "write failed", detailStyle: .plain,
                              remedy: "Couldn't save to your Keychain — nothing was stored. Try again.")
        case .environment:
            // No store happened — the slot stays a pending circle; the detail states the
            // true provenance (an env token is real, just never a Keychain receipt).
            keychainRow = Row(label: "Keychain", slot: .pending,
                              detail: "from environment", detailStyle: .plain, remedy: nil)
        }

        let githubRow: Row
        switch state.github {
        case .pending:
            githubRow = Row(label: "GitHub", slot: .pending,
                            detail: "—", detailStyle: .placeholder, remedy: nil)
        case .verifying:
            // STATIC text, deliberately no spinner — honest stillness; the words state the fact.
            githubRow = Row(label: "GitHub", slot: .pending,
                            detail: "verifying…", detailStyle: .plain, remedy: nil)
        case .retrying:
            // The bounded network-failure exit (binding review note): caution ink, NO motion,
            // updated only by real attempt outcomes.
            githubRow = Row(label: "GitHub", slot: .pending,
                            detail: "no answer yet — retrying", detailStyle: .caution, remedy: nil)
        case .rateLimited(let pauseSeconds):
            // GitHub ANSWERED — "slow down". Honest copy names both facts: the verdict and
            // the reducer's real pause (same formula, one home — PollReducer.rateLimitPause).
            let minutes = max(1, (pauseSeconds + 59) / 60)
            githubRow = Row(label: "GitHub", slot: .pending,
                            detail: "rate limited — retrying in ~\(minutes)m",
                            detailStyle: .caution, remedy: nil)
        case .connected:
            githubRow = Row(label: "GitHub", slot: .done,
                            detail: "connected", detailStyle: .plain, remedy: nil)
        case .failed(let reason):
            switch reason {
            case .invalidToken:
                githubRow = Row(label: "GitHub", slot: .failed(symbol: invalidTokenSymbol),
                                detail: "rejected (401)", detailStyle: .plain,
                                remedy: "GitHub rejected the token (401) — it's invalid or expired. "
                                      + "Create a fresh classic token (notifications scope) and paste it again.")
            case .ssoOrScope:
                githubRow = Row(label: "GitHub", slot: .failed(symbol: ssoOrScopeSymbol),
                                detail: "refused (403)", detailStyle: .plain,
                                remedy: "GitHub refused the token (403). If your org uses SSO, authorize "
                                      + "the token for it — or add the notifications scope. Then paste it again.")
            case .wrongShape:
                // Unreachable by construction (wrongShape lands on row 1), kept total so the
                // descriptor can never crash on a stray state.
                githubRow = Row(label: "GitHub", slot: .failed(symbol: wrongShapeSymbol),
                                detail: "—", detailStyle: .placeholder, remedy: nil)
            }
        }

        return Card(
            title: "Connect GitHub",
            promise: "githud reads your GitHub notifications — it never writes.",
            rows: [tokenRow, keychainRow, githubRow],
            fieldPlaceholder: "ghp_…",
            submitTitle: "Connect ⏎",
            footerCaption: "read-only · stays in your Keychain, nowhere else",
            createLinkTitle: "Create token ↗",
            settingsLinkTitle: "GitHub settings ↗",
            settingsURL: settingsURL,
            isComplete: isComplete(state))
    }
}
