import Foundation

/// A GitHub notification *thread* — the unit the REST Notifications API returns
/// (`GET /notifications`). Threads, not granular events: one row per
/// subscribed-and-active subject (PR/Issue/…), with a `reason` telling you *why*
/// it reached you. This model decodes the real API schema (a subset) so the same
/// type consumes the recorded fixture today and live data the moment the
/// `github_classic_pat_ready` gate flips.
public struct NotificationThread: Decodable, Sendable, Equatable {
    public let id: String
    public let unread: Bool
    /// Why this thread reached you: review_requested / mention / assign /
    /// team_mention / author / comment / subscribed / ci_activity / state_change /
    /// security_alert / manual / … (raw string; mapped by `NotificationReason`).
    public let reason: String
    public let updatedAt: String
    public let lastReadAt: String?
    public let subject: Subject
    public let repository: Repository

    /// **Enrichment — NOT present in the base `/notifications` response.** The login
    /// of the author of the latest comment, fetched separately from
    /// `subject.latestCommentUrl`. `nil` when unenriched. Lets the classifier demote
    /// bot chatter (dependabot/renovate/CI) on threads you authored. The fixture
    /// supplies it via `latest_comment_author_login`; the live client fills it via
    /// the enrichment pass (so this is a `var`, decode-then-enrich).
    public var latestCommentAuthorLogin: String?

    /// Enrichment — a 1-line preview of the latest comment body (also not in the base
    /// response). Reduces the click→browser context switch. Defaulted; the live
    /// client fills it during enrichment.
    public var latestCommentExcerpt: String? = nil

    /// **Enrichment — NOT in the base `/notifications` response.** The subject PR/Issue's
    /// lifecycle state: `"open"` | `"closed"` | `"merged"`, fetched from `subject.url`.
    /// `nil` when unenriched (or not a PR/Issue). A GitHub notification stays UNREAD after
    /// its PR is merged/closed, so a stale "review requested" lingers on a long-done PR;
    /// this lets the radar demote a RESOLVED subject (→ suppressed, auditable — never a
    /// silent drop). `nil` (unknown) always still surfaces (never-miss). The fixture
    /// supplies it via `subject_state`; the live client fills it during enrichment.
    public var subjectState: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository
        case updatedAt = "updated_at"
        case lastReadAt = "last_read_at"
        case latestCommentAuthorLogin = "latest_comment_author_login"
        case latestCommentExcerpt = "latest_comment_excerpt"
        case subjectState = "subject_state"
    }

    public struct Subject: Decodable, Sendable, Equatable {
        public let title: String
        public let url: String?
        public let latestCommentUrl: String?
        /// "PullRequest" | "Issue" | "Commit" | "Release" | "Discussion" | …
        public let type: String

        enum CodingKeys: String, CodingKey {
            case title, url, type
            case latestCommentUrl = "latest_comment_url"
        }
    }

    public struct Repository: Decodable, Sendable, Equatable {
        public let fullName: String
        public let isPrivate: Bool
        public let owner: Owner

        enum CodingKeys: String, CodingKey {
            case fullName = "full_name"
            case isPrivate = "private"
            case owner
        }
    }

    public struct Owner: Decodable, Sendable, Equatable {
        public let login: String
        /// "User" | "Organization" | "Bot"
        public let type: String
    }
}

public extension NotificationThread {
    /// Decode a `GET /notifications` array (or the recorded fixture).
    static func list(from data: Data) throws -> [NotificationThread] {
        try JSONDecoder().decode([NotificationThread].self, from: data)
    }

    /// The reviews-owed sweep's SYNTHETIC thread (WP 2026-07-17-002): a standing "review
    /// requested from you on an open PR" fact, dressed as the thread the classification
    /// machinery already understands. Every populated field is a real fact from the
    /// search item — title, repo, author-independent api-form subject url (rebuilt from
    /// repo+number so `RadarPresenter.htmlURL` round-trips to the item's html url),
    /// updatedAt. Two modeled conventions, both disclosed: `unread: true` means
    /// "standing = unhandled" (the search's `is:open` + `review-requested:` IS the
    /// unhandled test — the row leaves when the review lands or the PR closes), and
    /// `owner.type: "Organization"` is a placeholder no review_requested code path
    /// consults (deliberate routing is never bot-demoted; inbound derivation requires
    /// reason `subscribed`). The `review-owed:` id prefix keeps this id space
    /// structurally disjoint from real thread ids, inbound ids, and pulse ids.
    static func reviewOwed(from item: InboundItem) -> NotificationThread {
        NotificationThread(
            id: "review-owed:\(item.repo)#\(item.number)",
            unread: true,
            reason: "review_requested",
            updatedAt: item.updatedAt,
            lastReadAt: nil,
            subject: Subject(title: item.title,
                             url: "https://api.github.com/repos/\(item.repo)/pulls/\(item.number)",
                             latestCommentUrl: nil,
                             type: "PullRequest"),
            repository: Repository(fullName: item.repo,
                                   isPrivate: false,
                                   owner: Owner(login: String(item.repo.split(separator: "/").first ?? ""),
                                                type: "Organization")))
    }

    /// Reasons whose action-class hinges on *who* last commented — so knowing the
    /// latest-comment author lets us demote bot/CI chatter. RAW reasons only: the derived
    /// inbound case (`subscribed` on an owned repo) is folded in one level up, by
    /// `SignalClassifier.needsCommentAuthor` (ownership-gated, so the foreign firehose
    /// never enriches).
    static let enrichableReasons: Set<String> = ["author", "comment", "mention", "team_mention"]

    /// Activity on a PR you AUTHORED (`reason == "author"`, PR subject). The "Your PRs"
    /// lane (H2) is the dedicated home for your open PRs' state, so these are REDUNDANT in
    /// "Needs you" (H1) — filtered there. (An ISSUE you authored has no dedicated lane, so
    /// it stays.) Filtering them also frees the enrichment budget for the threads that DO
    /// surface, so their latest-comment author actually shows in the subtitle.
    var isOwnAuthoredPR: Bool { reason == "author" && subject.type == "PullRequest" }

    /// Worth one extra `GET subject.latest_comment_url` to fill the bot-detecting
    /// author? Only when the reason is comment-driven, a comment URL exists, and we
    /// don't already have the author. Skipped for own-authored PRs (filtered from the
    /// radar → enriching them would waste the budget the surfacing threads need).
    var needsEnrichment: Bool {
        latestCommentAuthorLogin == nil
            && subject.latestCommentUrl != nil
            && Self.enrichableReasons.contains(reason)
            && !isOwnAuthoredPR
    }

    /// Reasons that warrant the extra `GET subject.url` to learn merged/closed state. These
    /// are the action-required-FROM-OTHERS signals that sit at the TOP of the radar and are
    /// LOW-VOLUME (a handful per refresh), so a stale merged/closed one is both the most
    /// visible offender and cheap to resolve. `author` is deliberately EXCLUDED: activity on
    /// your OWN PRs is high-volume (often dozens), so per-thread fetching would blow the rate
    /// budget and the enrichment deadline — its merged PRs are better suppressed for free by
    /// cross-referencing the open-PR pulse (the H2 lane already knows which of yours are open;
    /// follow-up). `security_alert`/`invitation` subjects aren't PRs/Issues, so excluded too.
    /// RAW reasons only — the derived inbound case rides `SignalClassifier.needsSubjectState`.
    static let subjectStateReasons: Set<String> = ["review_requested", "mention", "assign", "team_mention"]

    /// Worth one extra `GET subject.url` to learn if the PR/Issue is already merged/closed?
    /// Only for an action-required PR/Issue subject we haven't resolved yet — so the cost is
    /// proportional to what would otherwise wrongly sit in "Needs you".
    var needsSubjectState: Bool {
        subjectState == nil
            && subject.url != nil
            && (subject.type == "PullRequest" || subject.type == "Issue")
            && Self.subjectStateReasons.contains(reason)
    }
}
