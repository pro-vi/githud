import Foundation

/// One OPEN issue/PR someone ELSE opened on a repo the user owns — the standing
/// "at your door" fact the notifications channel structurally cannot carry (events
/// expire when read; pre-watch history never notified at all — the Dec-29 PR that sat
/// invisible for six months is this type's founding story). Decoded from ONE
/// authenticated search: `GET /search/issues?q=user:{login}+is:open+-author:{login}`.
public struct InboundItem: Sendable, Equatable, Codable {
    public let repo: String        // "pro-vi/mcp-filter" (from repository_url's tail)
    public let number: Int
    public let title: String
    public let url: String         // html_url — Open-on-GitHub (the action ceiling)
    public let authorLogin: String
    public let authorType: String  // "User" | "Bot" | "Organization"
    public let isPR: Bool          // search marks PRs with a `pull_request` key
    public let isDraft: Bool       // PRs only; absent on issues → false
    public let createdAt: String   // ISO8601 — the WAITING-SINCE fact (the queue age)
    public let updatedAt: String

    public init(repo: String, number: Int, title: String, url: String, authorLogin: String,
                authorType: String, isPR: Bool, isDraft: Bool, createdAt: String, updatedAt: String) {
        self.repo = repo; self.number = number; self.title = title; self.url = url
        self.authorLogin = authorLogin; self.authorType = authorType
        self.isPR = isPR; self.isDraft = isDraft
        self.createdAt = createdAt; self.updatedAt = updatedAt
    }

    /// Opened by automation? Same policy home as everywhere else (`SignalClassifier.
    /// isBotLogin`) plus the search result's own type field — no enrichment pass needed:
    /// unlike a notification thread, a search item carries its author directly.
    public var isBot: Bool {
        authorType == "Bot" || SignalClassifier.isBotLogin(authorLogin)
    }

    // MARK: - decode (REST search JSON)

    private struct SearchResponse: Decodable {
        let totalCount: Int
        let incompleteResults: Bool
        let items: [Item]
        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case incompleteResults = "incomplete_results"
            case items
        }
    }

    private struct Item: Decodable {
        struct User: Decodable { let login: String; let type: String }
        struct PullRef: Decodable {}
        let number: Int
        let title: String
        let htmlUrl: String
        let repositoryUrl: String
        let createdAt: String
        let updatedAt: String
        let draft: Bool?
        let user: User
        let pullRequest: PullRef?
        enum CodingKeys: String, CodingKey {
            case number, title, draft, user
            case htmlUrl = "html_url"
            case repositoryUrl = "repository_url"
            case createdAt = "created_at"
            case updatedAt = "updated_at"
            case pullRequest = "pull_request"
        }
    }

    /// Decode a search response (or the committed fixture — cut from the user's REAL
    /// response, so the decoder is tested against production shape).
    public static func reading(fromSearchData data: Data) throws -> InboundReading {
        let resp = try JSONDecoder().decode(SearchResponse.self, from: data)
        let items = resp.items.map { i in
            InboundItem(
                repo: i.repositoryUrl.components(separatedBy: "/repos/").last ?? i.repositoryUrl,
                number: i.number,
                title: i.title,
                url: i.htmlUrl,
                authorLogin: i.user.login,
                authorType: i.user.type,
                isPR: i.pullRequest != nil,
                isDraft: i.draft ?? false,
                createdAt: i.createdAt,
                updatedAt: i.updatedAt)
        }
        return InboundReading(items: items, incomplete: resp.incompleteResults,
                              totalCount: resp.totalCount)
    }
}

/// One sweep's result. `incomplete` is GitHub's own admission that the search timed out
/// server-side (`incomplete_results`) — the reading may be MISSING open items.
public struct InboundReading: Sendable, Equatable {
    public let items: [InboundItem]
    public let incomplete: Bool
    public let totalCount: Int

    public init(items: [InboundItem], incomplete: Bool, totalCount: Int) {
        self.items = items
        self.incomplete = incomplete
        self.totalCount = totalCount
    }

    /// The pulse-honesty rule applied to the sweep: an item LEAVES the lane only when a
    /// COMPLETE reading no longer contains it (closed/merged — genuinely handled). An
    /// incomplete reading must never remove items: its missing entries are the search's
    /// fault, and dropping a row on it would fabricate "handled" — the exact false-green
    /// the pulse mappers ban. So: incomplete + a previous reading → keep the previous
    /// reading whole; incomplete + NOTHING prior → adopt what came (each item is still a
    /// true open fact; partial beats blank — the `incomplete` flag rides along for any
    /// future degraded-reading cue).
    public static func adopt(previous: InboundReading?, new: InboundReading) -> InboundReading {
        if new.incomplete, let previous { return previous }
        return new
    }
}
