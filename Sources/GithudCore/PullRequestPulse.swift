import Foundation

/// CI rollup for a PR's latest commit. `.none` means **no checks configured**
/// (`statusCheckRollup` was null) — it is NEVER conflated with `.passing`. That
/// distinction is load-bearing: claiming green when there are no checks is the
/// faked-liveness trap that erodes the same trust a missed mention does.
public enum CIState: String, Sendable, Equatable {
    case passing, failing, pending, none
}

/// The PR's review decision. `.none` = no review required / none requested
/// (GitHub returned null) — not "approved".
public enum ReviewState: String, Sendable, Equatable {
    case approved, changesRequested, reviewRequired, none
}

/// Mergeability. `.unknown` = GitHub hasn't computed it yet (or returned null) —
/// it is NEVER treated as "ready". UNKNOWN usually resolves within seconds, but
/// until it does we don't claim a state we don't have.
public enum MergeState: String, Sendable, Equatable, Codable {
    case mergeable, conflicting, unknown
}

/// The derived rollup verdict over (CI × review × merge × draft) — the priority
/// lattice. Worst-first. This is the single glanceable state for a PR's pulse.
public enum PulseState: String, Sendable, Equatable, Codable {
    case blocked   // your move — CI failing / merge conflicting / changes requested
    case ready     // green — mergeable AND (approved|none) AND (passing|none): merge it
    case waiting   // in flight — review required / CI pending / merge unknown
    case draft     // not ready, by design

    /// Sort weight for glanceability: blocked first (fix me), then ready (merge me),
    /// then waiting, then draft.
    public var sortWeight: Int {
        switch self {
        case .blocked: return 3
        case .ready:   return 2
        case .waiting: return 1
        case .draft:   return 0
        }
    }
}

/// A single open pull request's "pulse" — the state of *your* work, composed from
/// three independent GitHub signals (CI rollup × review decision × mergeability)
/// plus draft status. The H2 ambient lane: "how's my work doing?" — distinct from
/// the H1 notification radar's "does GitHub need me?". Pure value type (no AppKit),
/// so it is fixture-testable headlessly and decodes the live GraphQL response
/// unchanged. (Mirrors `NotificationThread`'s decode-and-model shape.)
public struct PullRequestPulse: Sendable, Equatable {
    public let repo: String        // "owner/repo"
    public let number: Int
    public let title: String
    public let url: String         // the PR's html_url (Open-on-GitHub)
    public let isDraft: Bool
    public let createdAt: String   // ISO8601 — when the PR was OPENED (drives the "just-raised" boost)
    public let updatedAt: String   // ISO8601 (relative age + sort tiebreak + the staleness cut)
    public let ci: CIState
    public let review: ReviewState
    public let merge: MergeState

    public init(repo: String, number: Int, title: String, url: String, isDraft: Bool,
                createdAt: String, updatedAt: String, ci: CIState, review: ReviewState, merge: MergeState) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.ci = ci
        self.review = review
        self.merge = merge
    }

    /// The priority lattice (worst-first). Honest about unknowns: an UNKNOWN merge
    /// or `.none` CI never yields a `.ready` verdict it can't back up.
    ///
    /// ```
    /// blocked : CI==failing OR merge==conflicting OR review==changesRequested
    /// draft   : isDraft  (and not blocked)
    /// waiting : review==reviewRequired OR CI==pending OR merge==unknown  (and not ↑)
    /// ready   : else → CI∈{passing,none} ∧ review∈{approved,none} ∧ merge==mergeable
    /// ```
    public var state: PulseState {
        if ci == .failing || merge == .conflicting || review == .changesRequested {
            return .blocked
        }
        if isDraft { return .draft }
        if review == .reviewRequired || ci == .pending || merge == .unknown {
            return .waiting
        }
        return .ready
    }

    // MARK: - Honest enum mappers (null / unrecognized → the conservative member)

    /// `statusCheckRollup.state` — a GraphQL `StatusState`: EXPECTED / ERROR / FAILURE /
    /// PENDING / SUCCESS, or null when the rollup object itself is absent (no checks).
    ///
    /// HONESTY: a `nil` rollup means **genuinely no checks** → `.none` (ready-eligible).
    /// A non-null but UNRECOGNIZED state (GitHub adds a value, or a check-run conclusion
    /// like NEUTRAL/SKIPPED surfaces here) must NOT be read as "no checks" — that would
    /// let API drift falsely certify a PR green. It fails safe to `.pending` (blocks
    /// `ready`, sorts into `waiting`).
    public static func ciState(fromRollup state: String?) -> CIState {
        guard let state = state?.uppercased() else { return .none }   // null rollup → no checks
        switch state {
        case "SUCCESS":             return .passing
        case "FAILURE", "ERROR":    return .failing
        case "PENDING", "EXPECTED": return .pending
        default:                    return .pending   // unrecognized non-null → fail safe (never green)
        }
    }

    /// `reviewDecision`: APPROVED / CHANGES_REQUESTED / REVIEW_REQUIRED / null.
    ///
    /// HONESTY (same contract as `ciState`): a `nil` decision means **genuinely no review
    /// required** → `.none` (ready-eligible). A non-null but UNRECOGNIZED value (GitHub
    /// adds a `reviewDecision` member) must NOT be read as "no review" — that would let
    /// API drift false-certify a PR as ready. It fails safe to `.reviewRequired` (blocks
    /// `.ready`, sorts into `waiting`).
    public static func reviewState(fromDecision decision: String?) -> ReviewState {
        guard let decision = decision?.uppercased() else { return .none }   // null → no review required (NOT approved)
        switch decision {
        case "APPROVED":          return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED":   return .reviewRequired
        default:                  return .reviewRequired   // unrecognized non-null → fail safe (never false-green)
        }
    }

    /// `mergeable`: MERGEABLE / CONFLICTING / UNKNOWN / null.
    public static func mergeState(fromMergeable mergeable: String?) -> MergeState {
        switch mergeable?.uppercased() {
        case "MERGEABLE":   return .mergeable
        case "CONFLICTING": return .conflicting
        default:            return .unknown       // UNKNOWN / null → unknown (NEVER ready)
        }
    }
}

// MARK: - GraphQL query + decode

public enum PulseDecodeError: Error, CustomStringConvertible, Equatable {
    case graphql(String)   // a GraphQL `errors[]` body (HTTP 200, no usable data)
    case empty             // neither data nor errors — malformed
    public var description: String {
        switch self {
        case .graphql(let m): return "graphql error: \(m)"
        case .empty:          return "graphql: empty/malformed response"
        }
    }
}

public extension PullRequestPulse {
    /// One GraphQL query → every open PR with its CI rollup + review decision +
    /// mergeability, newest first. Classic PAT + `repo` scope reaches private PRs.
    /// `first: 100` (the GraphQL connection max) is a generous margin over a realistic
    /// open-PR count (the live account has ~20) — newest-first, so the most relevant are
    /// never the ones cut. Beyond 100 the lane is silently capped (acceptable for an
    /// ambient SECONDARY lane; full `pageInfo` pagination deferred — see review).
    static let openPRsQuery = "{ viewer { pullRequests(first: 100, states: OPEN, "
        + "orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { number title url "
        + "isDraft createdAt updatedAt reviewDecision mergeable repository { nameWithOwner } "
        + "commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } } }"

    /// Decode a GraphQL `viewer.pullRequests` response body into pulses.
    ///
    /// HONESTY: GitHub can return BOTH partial `data` AND a top-level `errors[]` array
    /// (HTTP 200). Rendering the partial set as authoritative would lie about your PR
    /// state — so ANY top-level error degrades the whole pulse (thrown here → the
    /// scheduler keeps the last-good pulse), checked BEFORE the data path. A
    /// `{"errors":[…]}`-only body (no data) likewise throws rather than yielding zero PRs.
    static func list(fromGraphQLData data: Data) throws -> [PullRequestPulse] {
        let envelope = try JSONDecoder().decode(GraphQLEnvelope.self, from: data)
        if let message = envelope.errors?.first?.message {
            throw PulseDecodeError.graphql(message)   // errors win over partial data (no false-truth)
        }
        if let nodes = envelope.data?.viewer?.pullRequests.nodes {
            return nodes.map { $0.toPulse() }
        }
        throw PulseDecodeError.empty
    }
}

/// The nested GraphQL response DTO — kept private; mapped to the flat public model.
private struct GraphQLEnvelope: Decodable {
    let data: DataField?
    let errors: [GQLError]?

    struct GQLError: Decodable { let message: String }
    struct DataField: Decodable { let viewer: Viewer? }
    struct Viewer: Decodable { let pullRequests: PRConnection }
    struct PRConnection: Decodable { let nodes: [PRNode] }

    struct PRNode: Decodable {
        let number: Int
        let title: String
        let url: String
        let isDraft: Bool
        let createdAt: String?   // optional-defensive: GitHub always sends it, but a null
        let updatedAt: String    // never invents freshness — it falls back to updatedAt below
        let reviewDecision: String?
        let mergeable: String?
        let repository: Repo
        let commits: CommitConnection

        struct Repo: Decodable { let nameWithOwner: String }
        struct CommitConnection: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String? }

        func toPulse() -> PullRequestPulse {
            PullRequestPulse(
                repo: repository.nameWithOwner,
                number: number,
                title: title,
                url: url,
                isDraft: isDraft,
                createdAt: createdAt ?? updatedAt,   // null createdAt → can't prove "just-raised"; use updatedAt (created ≤ updated)
                updatedAt: updatedAt,
                ci: PullRequestPulse.ciState(fromRollup: commits.nodes.first?.commit.statusCheckRollup?.state),
                review: PullRequestPulse.reviewState(fromDecision: reviewDecision),
                merge: PullRequestPulse.mergeState(fromMergeable: mergeable)
            )
        }
    }
}
