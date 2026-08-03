import Foundation

/// What the radar should do with a thread.
public enum ActionClass: String, Sendable, Equatable {
    case actionRequired   // needs you to act — surface it
    case fyi              // informational — you might glance, no action
    case noise            // firehose / bot chatter — suppress from the radar
}

public struct Classification: Sendable, Equatable {
    public let actionClass: ActionClass
    public let urgency: Int          // 0…100, higher = more urgent (ranks the radar)
    public let rationale: String
}

public struct RankedThread: Sendable, Equatable {
    public let thread: NotificationThread
    public let classification: Classification
    /// The reason DISPLAY + surfacing key off: GitHub's raw reason, unless githud derived
    /// a more specific one (the `inbound` pseudo-reason for opened-on-your-repo threads).
    /// Derived where `selfLogin` lives (radar()/suppressed()) so the pure render path
    /// downstream (PollReducer → RadarPresenter.row) never needs the login re-plumbed.
    public let effectiveReason: String

    public init(thread: NotificationThread, classification: Classification,
                effectiveReason: String? = nil) {
        self.thread = thread
        self.classification = classification
        self.effectiveReason = effectiveReason ?? thread.reason
    }
}

/// The signal/trust model — the reframed *moat* (INTENT H1: "do I need to act?").
/// Maps a notification thread's `reason` (+ bot-awareness) to an action class and
/// urgency. Pure and deterministic, so it is fixture-testable headlessly and runs
/// unchanged on live data once the PAT gate flips.
///
/// Design bias: **misses are fatal, false alarms are budgeted** (RUBRIC #11,
/// pressure `signal-trust-budget`). When uncertain, we never silently drop a
/// plausibly-action-required thread, and we demote known automation hard.
public enum SignalClassifier {
    /// Known automation logins (in addition to any login ending in "[bot]").
    static let knownBots: Set<String> = [
        "dependabot", "dependabot[bot]", "renovate", "renovate[bot]",
        "github-actions[bot]", "codecov[bot]", "sonarcloud[bot]",
        "vercel[bot]", "netlify[bot]", "mergify[bot]", "allcontributors[bot]",
    ]

    public static func isBotLogin(_ login: String?) -> Bool {
        guard let l = login?.lowercased() else { return false }
        return l.hasSuffix("[bot]") || knownBots.contains(l)
    }

    /// The full set of GitHub notification `reason` values we are AWARE of
    /// (enumeration-awareness principle, iter 26). Every one has an explicit
    /// `classify` case; a value NOT in this set is genuinely novel → it is surfaced
    /// at a *visible* urgency for triage (see the `default` case), never silently
    /// buried. We don't custom-tune every reason now — the conservative ones
    /// (ci_activity/state_change/manual/your_activity) refine via dogfooding.
    public static let knownReasons: Set<String> = [
        "assign", "author", "comment", "ci_activity", "invitation", "manual",
        "mention", "review_requested", "security_alert", "state_change",
        "subscribed", "team_mention", "your_activity",
    ]

    /// Reasons that are a categorically DIFFERENT KIND of urgent — a live emergency
    /// (act-now-or-contain), not merely a higher urgency number. The color doctrine
    /// (consult 008) spends its two scarce attention resources here: the ONE reserved
    /// radar color (`danger`) AND a **critical-first sort dimension**. Keeping this
    /// orthogonal to `urgency` is load-bearing — `urgency` only ranks *within* a tier,
    /// so a real emergency can never sort below an ordinary high-urgency item
    /// (review_requested=95 would otherwise strand security_alert=92 below it, leaving
    /// the lone red glyph below a calm row — incoherent). A one-element policy: empty it
    /// for full monochrome; add a reason to promote it. (Reviewer/blocking-review is
    /// "needs you" but can sequence — NOT an emergency.)
    public static let criticalReasons: Set<String> = ["security_alert"]

    /// Whether a thread is a categorical emergency (see `criticalReasons`) — the single
    /// source of truth reused by the critical-first sort, the reserved-red glyph, and the
    /// collapsed-pill override.
    public static func isCritical(_ t: NotificationThread) -> Bool {
        criticalReasons.contains(t.reason)
    }

    /// Is the thread's subject already RESOLVED — its PR merged/closed or its issue closed?
    /// A GitHub notification stays unread after the PR merges, so a "review requested" can
    /// linger for weeks on a long-merged PR. Resolved ⇒ that CLASS of ask is over ⇒ off the
    /// radar (to the auditable suppressed set) — but only for reasons whose ask dies with
    /// the subject (`asksDieWithSubject`). Only true once the subject state is ENRICHED —
    /// an unknown (`nil`) state never suppresses (never-miss on missing data).
    public static func isSubjectResolved(_ t: NotificationThread) -> Bool {
        t.subjectState == "merged" || t.subjectState == "closed"
    }

    /// Reasons whose ASK dies with the subject: a review request, an assignment, watched
    /// activity, a state change, or CI noise on a merged/closed item needs nothing more
    /// (the founding case; `subscribed` also covers the derived inbound —
    /// without it your repos' merge history would accumulate as fake "at your door"
    /// rows). Everything ELSE asks to be READ, and reading survives resolution: a
    /// human's post-merge correction comment (dogfood 2026-07-18 — surfaced
    /// for one tick, then the merged verdict ate it) is exactly as real after the merge
    /// as before it. `comment`/`mention`/`team_mention`/`author` and any NOVEL reason
    /// stay surfaced over a resolved subject; the answered (own-latest-comment) and bot
    /// discharges still govern their noise.
    public static let asksDieWithSubject: Set<String> =
        ["review_requested", "assign", "subscribed", "state_change", "ci_activity"]

    /// Reasons that are DELIBERATE ROUTING — a human (or a system acting on a human's
    /// config) pointed at YOU specifically: review requests, assignments, invitations,
    /// direct @mentions, security alerts. These are NEVER bot-suppressed in `surfaces()`.
    /// The bot heuristic keys on the LATEST COMMENTER — and on work PRs CI speaks last
    /// on nearly every PR, so it says NOTHING about whether the ask is real. That
    /// asymmetry demoted two LIVE review requests off the radar (dogfood 2026-07-17 —
    /// the fatal-miss class: misses kill trust, false alarms are budgeted). Mirrors
    /// `classify()`, whose branches for these reasons never consult `bot` — the two
    /// layers must agree, or surfaces() silently wins and the radar lies by omission.
    /// (Cost disclosed: a dependabot PR that CODEOWNERS routes to you now surfaces —
    /// a real review request either way; the probe's policy-b line tracks this class.)
    public static let deliberatelyRoutedReasons: Set<String> =
        ["review_requested", "mention", "assign", "invitation", "security_alert"]

    /// Conservative automation heuristic — fires only on clear signals so a human
    /// asking for you is never mistaken for a bot.
    public static func isLikelyAutomated(_ t: NotificationThread) -> Bool {
        if t.repository.owner.type == "Bot" { return true }
        if isBotLogin(t.latestCommentAuthorLogin) { return true }
        let title = t.subject.title.lowercased()
        if title.hasPrefix("bump ") && title.contains(" from ") && title.contains(" to ") {
            return true   // dependabot / renovate version-bump
        }
        return false
    }

    /// Is the latest commenter you yourself? (Needs an enriched thread + the
    /// authenticated user's login.) Your own latest comment means the ball is in
    /// others' court — not action-required.
    public static func isOwnLatestComment(_ t: NotificationThread, selfLogin: String?) -> Bool {
        guard let login = t.latestCommentAuthorLogin, let selfLogin else { return false }
        return login.lowercased() == selfLogin.lowercased()
    }

    /// githud's one DERIVED reason (not a GitHub value): "inbound" — someone opened a
    /// PR/issue on a repo YOU own. GitHub files these under the `subscribed` firehose
    /// (owners auto-watch their repos), which the classifier otherwise buries at noise —
    /// so inbound contributions were sitting in the suppressed set (user call 2026-07-09:
    /// surface them, own-repos scope, default on). Kept a *derived* reason so the raw
    /// taxonomy stays GitHub's: `knownReasons`/novelty checks run on the raw value.
    public static let inboundReason = "inbound"

    /// The inbound predicate — deliberately narrow (repos the user personally OWNS;
    /// org/maintainer scope is a future config decision): a `subscribed` thread whose
    /// subject is a PR or issue on a repo whose owner login IS the authenticated user.
    /// Releases/discussions on your repos stay firehose. Without a resolved `selfLogin`
    /// this is always false — ownership is never guessed (never fabricate a state).
    public static func isInboundOnOwnRepo(_ t: NotificationThread, selfLogin: String?) -> Bool {
        guard let selfLogin, t.reason == "subscribed" else { return false }
        guard t.subject.type == "PullRequest" || t.subject.type == "Issue" else { return false }
        return t.repository.owner.login.lowercased() == selfLogin.lowercased()
    }

    /// The reason a thread surfaces/displays under: raw, unless the inbound derivation
    /// upgrades it. The single home `radar()`/`suppressed()` (RankedThread), the change
    /// key, and `SurfacePreferences.surfaces` all consult, so surfacing, display, and
    /// re-render detection can never disagree.
    public static func effectiveReason(_ t: NotificationThread, selfLogin: String?) -> String {
        isInboundOnOwnRepo(t, selfLogin: selfLogin) ? inboundReason : t.reason
    }

    /// Enrichment gates, inbound-aware (review round 1, trust MAJOR): a thread promoted
    /// into the action-required tier needs the SAME two honesty passes every other
    /// action-required reason gets — subject state (a merged/closed inbound PR must drop
    /// off the radar, or your repos' merge history accumulates as fake "new PR" rows) and
    /// latest-comment author (bot demotion beyond the title heuristic — renovate-class
    /// bots don't title PRs "Bump X from Y to Z"). OWNERSHIP-gated, so the foreign
    /// `subscribed` firehose never spends the enrichment budget — the very cost that
    /// keeps `subscribed` out of `NotificationThread`'s raw reason sets.
    public static func needsSubjectState(_ t: NotificationThread, selfLogin: String?) -> Bool {
        t.needsSubjectState
            || (isInboundOnOwnRepo(t, selfLogin: selfLogin)
                && t.subjectState == nil && t.subject.url != nil)
    }

    public static func needsCommentAuthor(_ t: NotificationThread, selfLogin: String?) -> Bool {
        t.needsEnrichment
            || (isInboundOnOwnRepo(t, selfLogin: selfLogin)
                && t.latestCommentAuthorLogin == nil && t.subject.latestCommentUrl != nil)
    }

    public static func classify(_ t: NotificationThread, selfLogin: String? = nil) -> Classification {
        let bot = isLikelyAutomated(t)
        let ownLatest = isOwnLatestComment(t, selfLogin: selfLogin)

        switch t.reason {
        case "review_requested":
            return .init(actionClass: .actionRequired, urgency: 95,
                         rationale: "review requested — you're blocking a PR")
        case "mention":
            // A DIRECT @you is deliberate even from automation (PagerDuty/Sentry/Vercel
            // alerts route to you by name) — NEVER bot-demoted. Misses are fatal; a bot
            // @-mentioning you personally is signal, not noise (unlike team_mention).
            // But an ANSWERED mention is discharged (dogfood 2026-07-17): your own
            // latest comment means the ball is in others' court — same rule as `author`.
            // A reply re-notifies (new unread thread), so it resurfaces on its own.
            // (A comment does NOT discharge `review_requested` — only a review does.)
            if ownLatest {
                return .init(actionClass: .fyi, urgency: 30,
                             rationale: "you answered the @mention — ball is in others' court")
            }
            return .init(actionClass: .actionRequired, urgency: 90, rationale: "you were @mentioned")
        case "invitation":
            return .init(actionClass: .actionRequired, urgency: 85, rationale: "repo/org invitation — accept or decline")
        case "assign":
            return .init(actionClass: .actionRequired, urgency: 85, rationale: "assigned to you")
        case "security_alert":
            // Above assign/mention: a security alert (secret leak, CVE) can be
            // drop-everything, and misses are fatal.
            return .init(actionClass: .actionRequired, urgency: 92, rationale: "security alert")
        case "team_mention":
            return bot
                ? .init(actionClass: .noise, urgency: 0, rationale: "team @mention by automation")
                : .init(actionClass: .actionRequired, urgency: 70, rationale: "your team was @mentioned")
        case "author":
            if bot { return .init(actionClass: .noise, urgency: 0, rationale: "automation activity on your thread") }
            if ownLatest { return .init(actionClass: .fyi, urgency: 30, rationale: "your own latest comment — ball is in others' court") }
            let pr = t.subject.type == "PullRequest"
            return .init(actionClass: .actionRequired, urgency: pr ? 65 : 55,
                         rationale: pr ? "new activity on your PR" : "new activity on your issue")
        case "comment":
            if bot { return .init(actionClass: .noise, urgency: 0, rationale: "automation comment") }
            return .init(actionClass: .fyi, urgency: 40, rationale: "comment in a thread you're in")
        case "ci_activity":
            return .init(actionClass: .fyi, urgency: 20, rationale: "CI activity")
        case "state_change":
            return .init(actionClass: .fyi, urgency: 15, rationale: "state change")
        case "manual":
            return .init(actionClass: .fyi, urgency: 10, rationale: "manually subscribed")
        case "your_activity":
            return .init(actionClass: .fyi, urgency: 10, rationale: "a result of your own activity")
        case "subscribed":
            if isInboundOnOwnRepo(t, selfLogin: selfLogin) {
                // Inbound contribution — someone opened a PR/issue on a repo you own:
                // triage IS a needs-you fact. Slots just under `author` (65/55): activity
                // on a thread that's already yours edges out a fresh arrival at your door.
                // Automation is demoted via the comment-author enrichment (inbound rides
                // `needsCommentAuthor`) — when a fresh thread carries no comment URL the
                // title heuristic is the only bot signal (disclosed; the critical cases
                // ride `security_alert` separately).
                if bot { return .init(actionClass: .noise, urgency: 0, rationale: "automation opened this on your repo") }
                let pr = t.subject.type == "PullRequest"
                return .init(actionClass: .actionRequired, urgency: pr ? 62 : 52,
                             rationale: pr ? "new PR opened on your repo" : "new issue opened on your repo")
            }
            return .init(actionClass: .noise, urgency: 0, rationale: "watching the repo (firehose)")
        default:
            // NOVEL reason (not in knownReasons): GitHub added a reason we don't model.
            // Surface it at a VISIBLE urgency for triage — not buried at the bottom —
            // but keep it `.fyi` (we don't KNOW it's action-required). Never-miss > tidy:
            // better seen and dismissed than silently dropped. (surfaces() already lets
            // novel reasons through; this makes them actually visible.)
            return .init(actionClass: .fyi, urgency: 60,
                         rationale: "unrecognized reason '\(t.reason)' — surfaced for triage")
        }
    }

    /// The other side of the radar: unread threads that were **suppressed** (fyi /
    /// noise / self-demoted). Surfacing these — a "reveal suppressed" affordance — is
    /// how a user catches a MISS (a false negative). Misses, not compression, are the
    /// existential risk to trust (consult 004). Ordered most-likely-miss first.
    public static func suppressed(_ threads: [NotificationThread], selfLogin: String? = nil,
                                  preferences: SurfacePreferences = .auto) -> [RankedThread] {
        threads
            .filter { $0.unread }
            .filter { !preferences.surfaces($0, selfLogin: selfLogin) }
            .map { RankedThread(thread: $0, classification: classify($0, selfLogin: selfLogin),
                                effectiveReason: effectiveReason($0, selfLogin: selfLogin)) }
            .sorted { $0.classification.urgency > $1.classification.urgency }
    }

    /// The radar: **unread** threads whose reason the user surfaces (default auto),
    /// minus bot/self-activity, ranked by urgency desc then recency. This is what the
    /// island shows.
    public static func radar(_ threads: [NotificationThread], selfLogin: String? = nil,
                             preferences: SurfacePreferences = .auto) -> [RankedThread] {
        threads
            .filter { $0.unread }
            .filter { preferences.surfaces($0, selfLogin: selfLogin) }
            .map { RankedThread(thread: $0, classification: classify($0, selfLogin: selfLogin),
                                effectiveReason: effectiveReason($0, selfLogin: selfLogin)) }
            .sorted { lhs, rhs in
                // Critical-FIRST (color doctrine, consult 008): a categorical emergency
                // floats above all ordinary items regardless of urgency number, so the
                // one reserved red glyph is never stranded below a calm row. Within a
                // salience tier: urgency desc, then recency.
                let lc = isCritical(lhs.thread), rc = isCritical(rhs.thread)
                if lc != rc { return lc }
                if lhs.classification.urgency != rhs.classification.urgency {
                    return lhs.classification.urgency > rhs.classification.urgency
                }
                return lhs.thread.updatedAt > rhs.thread.updatedAt   // ISO8601 sorts lexically
            }
    }
}
