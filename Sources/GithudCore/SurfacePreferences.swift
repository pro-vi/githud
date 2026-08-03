import Foundation

/// Which notification reason-types the user wants surfaced on the radar. The
/// classifier still applies bot + self-activity demotion *within* the enabled set —
/// this just lets the user choose the CATEGORIES they care about. "Start off auto",
/// then toggle. (Original intent: "the user can choose what they care about.")
public struct SurfacePreferences: Sendable, Equatable {
    public var enabledReasons: Set<String>

    /// The reasons that surface by default — the auto classifier's action-required set.
    /// Includes the derived `inbound` (opened on a repo you own — user call 2026-07-09:
    /// default ON).
    public static let autoReasons: Set<String> = [
        "review_requested", "mention", "team_mention", "assign", "security_alert", "author", "invitation",
        SignalClassifier.inboundReason,
    ]
    public static let auto = SurfacePreferences(enabledReasons: autoReasons)

    /// The auto set exactly as it shipped BEFORE the derived `inbound` reason existed.
    /// A persisted set equal to it is an auto-defaults user from that era, not a
    /// deliberate custom pick — `fromStored` follows auto forward for them, so the new
    /// default-on reason isn't silently withheld by a stale snapshot of the old default.
    public static let legacyAutoReasonsV1: Set<String> = [
        "review_requested", "mention", "team_mention", "assign", "security_alert", "author", "invitation",
    ]

    /// Rehydrate persisted preferences (SurfaceStore hands the raw stored set here so
    /// the migration rule is Core-owned + tested). Any OTHER stored set is a real user
    /// choice and is honored verbatim — the new toggle just appears unchecked.
    public static func fromStored(_ stored: Set<String>) -> SurfacePreferences {
        stored == legacyAutoReasonsV1 ? .auto : SurfacePreferences(enabledReasons: stored)
    }

    /// Every reason a user can toggle, in display order (for the menu). Mirrors
    /// `SignalClassifier.knownReasons` (the full GitHub enumeration) plus the one
    /// githud-derived pseudo-reason (`inbound`, after the action block). `your_activity`
    /// is present (toggleable) but NOT in `autoReasons` (default-off).
    public static let allReasons: [String] = [
        "review_requested", "mention", "team_mention", "assign", "security_alert", "invitation",
        SignalClassifier.inboundReason,
        "author", "comment", "ci_activity", "state_change", "your_activity", "subscribed", "manual",
    ]

    public init(enabledReasons: Set<String>) { self.enabledReasons = enabledReasons }

    public func isEnabled(_ reason: String) -> Bool { enabledReasons.contains(reason) }

    public func toggling(_ reason: String) -> SurfacePreferences {
        var next = enabledReasons
        if next.contains(reason) { next.remove(reason) } else { next.insert(reason) }
        return SurfacePreferences(enabledReasons: next)
    }

    public var isAuto: Bool { enabledReasons == Self.autoReasons }

    /// Should this unread thread surface? Surface if the reason is enabled OR is a
    /// NOVEL reason we don't know about (GitHub can add reasons — never silently drop
    /// one that might need action; the user can disable it later). Then bot/self
    /// demotion always applies.
    public func surfaces(_ thread: NotificationThread, selfLogin: String?) -> Bool {
        // Activity on a PR you authored lives in the "Your PRs" lane (H2) — redundant in
        // "Needs you" (H1), so filter it here (→ suppressed, auditable). Issues you authored
        // have no dedicated lane and still surface.
        if thread.isOwnAuthoredPR { return false }
        // A merged/closed PR (or closed issue) discharges the asks that DIE with it —
        // a leftover unread "review requested" on it is not action-required (→ the
        // auditable suppressed set). But a READ-me ask (comment/mention/author) survives
        // resolution: a human's post-merge correction is as real after the merge as
        // before it (dogfood 2026-07-18 — the row flashed once, then the
        // merged verdict ate it). Unknown subject state never suppresses.
        if SignalClassifier.asksDieWithSubject.contains(thread.reason),
           SignalClassifier.isSubjectResolved(thread) { return false }
        // Novelty is judged against GitHub's OWN enumeration, never the toggle list —
        // the toggle list now carries the derived `inbound`, and a hypothetical future
        // GitHub reason with the same spelling must still walk through the novel door
        // (surfaced for triage), not hide behind a user's inbound toggle.
        let known = SignalClassifier.knownReasons.contains(thread.reason)
        // The gate keys off the EFFECTIVE reason (the inbound derivation), with the raw
        // reason as a fallback door: a user who enabled the raw `subscribed` firehose
        // keeps seeing inbound threads even with the inbound toggle off — the derived
        // reason only ever ADDS surface, it never subtracts from a broader choice.
        let effective = SignalClassifier.effectiveReason(thread, selfLogin: selfLogin)
        guard enabledReasons.contains(effective) || enabledReasons.contains(thread.reason) || !known else {
            return false
        }
        // DELIBERATE ROUTING (review_requested/assign/invitation/security_alert, and a
        // direct @you mention — even from automation) always surfaces: someone pointed
        // at YOU, and the bot heuristic keys on the latest COMMENTER — CI speaking last
        // on a PR says nothing about whether the review is still owed (dogfood
        // 2026-07-17: two live review requests demoted because a bot commented last —
        // the fatal-miss class). Only the AMBIENT reasons stay bot-suppressed
        // (team_mention/author/comment/subscribed/etc), matching classify()'s own
        // bot handling — the two layers must agree.
        if !SignalClassifier.deliberatelyRoutedReasons.contains(thread.reason),
           SignalClassifier.isLikelyAutomated(thread) { return false }
        // "Ball in others' court": your own latest comment discharges author/comment
        // activity AND an @mention you've answered (dogfood 2026-07-17 — an answered
        // mention sat at urgency 90 with no reply owed to YOU). A reply from anyone
        // re-notifies (fresh unread), so this can never hide a follow-up. It does NOT
        // apply to review_requested/assign — a comment discharges neither a formal
        // review request nor an assignment.
        if thread.reason == "author" || thread.reason == "comment" || thread.reason == "mention",
           SignalClassifier.isOwnLatestComment(thread, selfLogin: selfLogin) {
            return false
        }
        return true
    }
}
