import Foundation

public struct RateLimit: Sendable, Equatable {
    public let limit: Int?
    public let remaining: Int?
    public let used: Int?
    public let reset: Int?      // X-RateLimit-Reset (epoch seconds) — when the window refills
}

public struct NotificationsResponse: Sendable {
    public let status: Int
    public let notModified: Bool
    public let threads: [NotificationThread]   // empty on 304
    public let pollPlan: PollPlan
    public let rateLimit: RateLimit?
    public let oauthScopes: String?
    public let pollInterval: Int?
}

public enum GitHubClientError: Error, CustomStringConvertible {
    case http(Int, String)        // unexpected status + a short body excerpt (never the token)
    case transport(String)
    case decode(String)
    case rateLimited(retryAfter: Int?)   // 403/429 primary or secondary limit; seconds to pause (nil = unknown)

    public var description: String {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body)"
        case .transport(let m): return "transport: \(m)"
        case .decode(let m): return "decode: \(m)"
        case .rateLimited(let s): return "rate limited (retry after \(s.map(String.init) ?? "?")s)"
        }
    }
}

/// Minimal GitHub REST client for the Notifications spine. Authenticates with the
/// **classic** PAT (Bearer), sends conditional validators, and honors the response
/// headers (X-Poll-Interval / ETag / Last-Modified) via `PollPlan`. The token is
/// only ever placed in the Authorization header — never logged, never in errors.
public final class GitHubClient {
    private let token: String
    private let session: URLSession
    private let baseURL: URL

    /// Shared rate-limit backoff (WP-1b). A 429 / 403-with-`X-RateLimit-Reset` on ANY of
    /// the five endpoints SETS this window; EVERY endpoint RESPECTS it by failing fast with
    /// `.rateLimited` instead of firing a request — so a single limit on one path no longer
    /// lets the other four keep hammering GitHub past the reset. Guarded by a lock because
    /// the endpoints' completions land on the URLSession's background queue(s).
    private let pauseLock = NSLock()
    private var _pauseUntil: Date?

    public init(token: String,
                session: URLSession? = nil,
                baseURL: URL = URL(string: "https://api.github.com")!) {
        self.token = token
        // Default to a NO-CACHE session: we manage conditional polling explicitly
        // (our own ETag/Last-Modified validators). URLSession.shared's URLCache
        // transparently revalidates and serves a cached 200, swallowing the 304 —
        // which would defeat RUBRIC #8 (we'd never see "not modified"). An ephemeral
        // session with urlCache=nil surfaces the raw 304 to us.
        self.session = session ?? URLSession(configuration: Self.ephemeralNoCacheConfiguration())
        self.baseURL = baseURL
    }

    /// The ephemeral, cache-free configuration the default session is built from (PRESSURE
    /// `conditional-polling-no-cache`). Exposed so a test can assert the 304-discipline is
    /// preserved (`urlCache == nil`, `reloadIgnoringLocalCacheData`) without live network.
    public static func ephemeralNoCacheConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        // Cap any single request so a stalled connection self-cancels instead of
        // being abandoned at the app-level semaphore timeout (review): bounds the
        // hang to ~15s (each pagination/enrichment GET is independent) rather than
        // URLSession's 60s default.
        config.timeoutIntervalForRequest = 15
        return config
    }

    /// Seconds remaining on an active shared rate-limit pause, or `nil` if none (an expired
    /// window self-clears). Every endpoint calls this before firing to fail fast.
    private func activePauseSeconds() -> Int? {
        pauseLock.lock(); defer { pauseLock.unlock() }
        guard let until = _pauseUntil else { return nil }
        let remaining = Int(until.timeIntervalSinceNow.rounded(.up))
        if remaining <= 0 { _pauseUntil = nil; return nil }
        return remaining
    }

    /// Open (or widen) the shared pause to `seconds` from now — never SHORTEN an existing,
    /// longer pause (the most conservative reset wins).
    private func openPause(seconds: Int) {
        pauseLock.lock(); defer { pauseLock.unlock() }
        let until = Date().addingTimeInterval(TimeInterval(max(0, seconds)))
        if let existing = _pauseUntil, existing >= until { return }
        _pauseUntil = until
    }

    /// Page-1 metadata (poll plan / rate / scopes) — carried across continuation pages
    /// so the final combined response keeps the resource-level headers from page 1.
    private struct PageMeta {
        let plan: PollPlan
        let rate: RateLimit
        let scopes: String?
        let pollInterval: Int?
    }

    /// Max notification pages to follow per refresh — a runaway guard. 20 × 50 = 1000
    /// unread, far beyond any realistic action-required count; if hit, we log + use what
    /// we have (still strictly more complete than the old page-1-only behavior).
    private static let maxNotificationPages = 20

    /// A `GET` request carrying the standard auth + API headers (+ optional conditional
    /// validators). The token is only ever placed here — never logged, never in errors.
    private func authedRequest(url: URL, conditional validators: PollValidators? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        if let validators {
            for (key, value) in validators.conditionalHeaders { req.setValue(value, forHTTPHeaderField: key) }
        }
        return req
    }

    /// Extract the `rel="next"` URL from an RFC-5988 `Link` header (GitHub paginates
    /// `/notifications`; default + max `per_page` is 50). Pure + testable. Returns nil
    /// when there is no next page.
    public static func parseNextLink(_ header: String?) -> String? {
        guard let header else { return nil }
        for part in header.split(separator: ",") {
            let segs = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard let urlSeg = segs.first, urlSeg.hasPrefix("<"), urlSeg.hasSuffix(">") else { continue }
            if segs.dropFirst().contains(where: { $0.replacingOccurrences(of: " ", with: "") == "rel=\"next\"" }) {
                return String(urlSeg.dropFirst().dropLast())
            }
        }
        return nil
    }

    /// If `http` indicates a rate limit (Retry-After, or a 403/429 with remaining==0),
    /// return the seconds to pause; else nil. Honors GitHub's guidance to wait for
    /// `Retry-After` / `X-RateLimit-Reset` rather than hammering a limited endpoint.
    private static func rateLimitPause(_ http: HTTPURLResponse) -> Int? {
        if let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap({ Int($0) }) {
            return max(0, retry)
        }
        let status = http.statusCode
        let remaining = http.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap { Int($0) }
        guard (status == 403 || status == 429), remaining == 0,
              let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap({ Int($0) }) else {
            return nil
        }
        return max(0, reset - Int(Date().timeIntervalSince1970))
    }

    /// `GET /notifications`, following `Link: rel="next"` to fetch ALL pages so an
    /// action-required item on page 2+ is never silently dropped (the never-miss moat).
    /// Conditional validators ride only on page 1 (the resource ETag); a 304 returns
    /// immediately with no pages. Completion runs on a URLSession background queue.
    public func fetchNotifications(
        validators: PollValidators = PollValidators(),
        includeRead: Bool = false,
        completion: @escaping (Result<NotificationsResponse, GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var comps = URLComponents(url: baseURL.appendingPathComponent("notifications"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "all", value: includeRead ? "true" : "false"),
            URLQueryItem(name: "per_page", value: "50"),
        ]
        let task = session.dataTask(with: authedRequest(url: comps.url!, conditional: validators)) { data, response, error in
            self.handleFirstPage(data: data, response: response, error: error,
                                 validators: validators, completion: completion)
        }
        task.resume()
    }

    private func handleFirstPage(
        data: Data?, response: URLResponse?, error: Error?,
        validators: PollValidators,
        completion: @escaping (Result<NotificationsResponse, GitHubClientError>) -> Void
    ) {
        if let error { completion(.failure(.transport(error.localizedDescription))); return }
        guard let http = response as? HTTPURLResponse else {
            completion(.failure(.transport("no HTTPURLResponse"))); return
        }
        func header(_ name: String) -> String? { http.value(forHTTPHeaderField: name) }

        let status = http.statusCode
        let pollInterval = header("X-Poll-Interval").flatMap { Int($0) }
        let plan = PollPlan.from(status: status, etag: header("ETag"), lastModified: header("Last-Modified"),
                                 pollInterval: pollInterval, previousValidators: validators)
        let rate = RateLimit(
            limit: header("X-RateLimit-Limit").flatMap { Int($0) },
            remaining: header("X-RateLimit-Remaining").flatMap { Int($0) },
            used: header("X-RateLimit-Used").flatMap { Int($0) },
            reset: header("X-RateLimit-Reset").flatMap { Int($0) }
        )
        let meta = PageMeta(plan: plan, rate: rate, scopes: header("X-OAuth-Scopes"), pollInterval: pollInterval)

        if status == 304 {
            completion(.success(NotificationsResponse(
                status: 304, notModified: true, threads: [],
                pollPlan: plan, rateLimit: rate, oauthScopes: meta.scopes, pollInterval: pollInterval)))
            return
        }
        if let pause = Self.rateLimitPause(http) {
            openPause(seconds: pause)
            completion(.failure(.rateLimited(retryAfter: pause)))
            return
        }
        guard status == 200 else {
            completion(.failure(.http(status, data.map { String(decoding: $0.prefix(180), as: UTF8.self) } ?? "")))
            return
        }
        guard let data else { completion(.failure(.decode("no body"))); return }
        do {
            let threads = try NotificationThread.list(from: data)
            if let next = Self.parseNextLink(header("Link")) {
                fetchRemainingPages(next, accumulated: threads, page: 1, meta: meta, completion: completion)
            } else {
                finishNotifications(meta: meta, threads: threads, completion: completion)
            }
        } catch {
            completion(.failure(.decode("\(error)")))
        }
    }

    /// Follow `rel="next"` continuation pages (plain GETs — no conditional headers),
    /// accumulating threads. A failed/garbled continuation page returns what we have so
    /// far (page 1 is newest-first, so partial ≥ the old page-1-only behavior); the next
    /// poll retries the whole set. Bounded by `maxNotificationPages`.
    private func fetchRemainingPages(
        _ urlString: String, accumulated: [NotificationThread], page: Int, meta: PageMeta,
        completion: @escaping (Result<NotificationsResponse, GitHubClientError>) -> Void
    ) {
        guard page < Self.maxNotificationPages, let url = URL(string: urlString) else {
            finishNotifications(meta: meta, threads: accumulated, completion: completion)
            return
        }
        let task = session.dataTask(with: authedRequest(url: url)) { data, response, error in
            guard error == nil, let http = response as? HTTPURLResponse, http.statusCode == 200,
                  let data, let more = try? NotificationThread.list(from: data) else {
                // continuation failed — return page-1..n we already have (never lose them)
                self.finishNotifications(meta: meta, threads: accumulated, completion: completion)
                return
            }
            let combined = accumulated + more
            if let next = Self.parseNextLink(http.value(forHTTPHeaderField: "Link")) {
                self.fetchRemainingPages(next, accumulated: combined, page: page + 1, meta: meta, completion: completion)
            } else {
                self.finishNotifications(meta: meta, threads: combined, completion: completion)
            }
        }
        task.resume()
    }

    private func finishNotifications(
        meta: PageMeta, threads: [NotificationThread],
        completion: @escaping (Result<NotificationsResponse, GitHubClientError>) -> Void
    ) {
        completion(.success(NotificationsResponse(
            status: 200, notModified: false, threads: threads,
            pollPlan: meta.plan, rateLimit: meta.rate, oauthScopes: meta.scopes, pollInterval: meta.pollInterval)))
    }

    /// Enrichment: fetch the latest comment's author (for bot/self demotion) AND its
    /// body (for the in-island preview — reduces the click→browser context switch).
    /// One GET against `subject.latest_comment_url`.
    public func fetchLatestCommentAuthor(
        urlString: String,
        completion: @escaping (Result<(login: String, type: String, body: String?), GitHubClientError>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(.transport("bad latest_comment_url")))
            return
        }
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            do {
                let comment = try JSONDecoder().decode(LatestComment.self, from: data)
                completion(.success((comment.user.login, comment.user.type, comment.body)))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `GET subject.url` — the subject PR/Issue's lifecycle state, so the radar can demote
    /// a notification whose PR is already MERGED/CLOSED (a stale "review requested" lingers
    /// unread for weeks otherwise). Returns a normalized `"open" | "closed" | "merged"`.
    /// A PR carries `merged`/`merged_at`; an issue only `state` (→ never "merged").
    public func fetchSubjectState(
        urlString: String,
        completion: @escaping (Result<String, GitHubClientError>) -> Void
    ) {
        guard let url = URL(string: urlString) else {
            completion(.failure(.transport("bad subject url")))
            return
        }
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            do {
                let s = try JSONDecoder().decode(SubjectStateDTO.self, from: data)
                let normalized = (s.merged == true || s.mergedAt != nil) ? "merged"
                               : (s.state.lowercased() == "closed") ? "closed" : "open"
                completion(.success(normalized))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `GET /notifications/threads/{id}` → the thread's CURRENT unread flag. The
    /// 304-path read-transition check (dogfood 2026-07-18, the lexical Release mention):
    /// marking a thread read does NOT bump the notifications feed's Last-Modified, so
    /// the feed 304s across read transitions and a read row lingers until an unrelated
    /// notification arrives. Rides the `notifications` scope alone — private repos
    /// included, no `repo` scope needed.
    public func fetchThreadUnread(
        threadID: String,
        completion: @escaping (Result<Bool, GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("notifications/threads/\(threadID)"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            struct ThreadDTO: Decodable { let unread: Bool }
            do {
                completion(.success(try JSONDecoder().decode(ThreadDTO.self, from: data).unread))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `GET /user` — the authenticated user's login, so self-activity (your own
    /// latest comment) can be demoted off the radar. Fetched once and cached.
    public func fetchAuthenticatedUserLogin(
        completion: @escaping (Result<String, GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("user"))
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            do {
                completion(.success(try JSONDecoder().decode(AuthUser.self, from: data).login))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `GET /search/issues` — the standing inbound sweep: every OPEN issue/PR others
    /// opened on repos the user owns, in ONE request. Search lives in its OWN rate
    /// bucket (30 req/min authenticated), so the REST notifications 304-discipline and
    /// the GraphQL pulse budget are both untouched; one sweep per ~60s tick spends
    /// ~1/30 of it. Search has no reliable conditional requests → a full GET each tick;
    /// `incomplete_results` rides the decoded reading (the adopt rule upstream decides
    /// what an incomplete reading may do). Sorted OLDEST-first deliberately: results cap
    /// at `per_page`, so if a user ever exceeds 50 standing inbound items the NEWEST
    /// fall off — the queue's head (the long-waiting debt) is never the truncated end,
    /// and a new arrival's announcement belongs to the radar's event row anyway.
    public func fetchInboundSearch(
        login: String,
        completion: @escaping (Result<InboundReading, GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var comps = URLComponents(url: baseURL.appendingPathComponent("search/issues"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            // `-author:{login}` is LOAD-BEARING beyond scope (review note): it is what
            // keeps inbound row ids ("owner/repo#n") structurally disjoint from the pulse
            // lane's identically-formatted ids (pulse = authored-by-viewer) — the island's
            // keyRows map and the peek stash key on that disjointness. Dropping this
            // clause would silently collide the two lanes' ids.
            URLQueryItem(name: "q", value: "user:\(login) is:open -author:\(login)"),
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "per_page", value: "50"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            do {
                completion(.success(try InboundItem.reading(fromSearchData: data)))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `GET /search/issues` — the REVIEWS-OWED standing sweep (WP 2026-07-17-002): every
    /// OPEN PR whose review is formally requested from the viewer. This is the fact the
    /// notification inbox structurally cannot carry — a glanced-at (read) notification
    /// leaves `GET /notifications` forever while the review stays owed (dogfood
    /// 2026-07-17: two live teammate PRs invisible for four days). Same search bucket
    /// economics as the inbound sweep (~2/30 per tick with both). Deliberately NO
    /// `-author:` clause — the REQUESTER may be anyone, including bots via CODEOWNERS
    /// (deliberate-routing doctrine: a review request is never bot-suppressed); the id
    /// disjointness the inbound sweep gets from its query is provided downstream by the
    /// synthetic `review-owed:` id prefix instead. Oldest-first for the same cap logic:
    /// the longest-owed review must never be the truncated end.
    public func fetchReviewRequestedSearch(
        login: String,
        completion: @escaping (Result<InboundReading, GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var comps = URLComponents(url: baseURL.appendingPathComponent("search/issues"),
                                  resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            URLQueryItem(name: "q", value: "is:open is:pr review-requested:\(login)"),
            URLQueryItem(name: "sort", value: "created"),
            URLQueryItem(name: "order", value: "asc"),
            URLQueryItem(name: "per_page", value: "50"),
        ]
        var req = URLRequest(url: comps.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                completion(.failure(.http(http.statusCode, ""))); return
            }
            do {
                completion(.success(try InboundItem.reading(fromSearchData: data)))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }

    /// `POST /graphql` — the H2 pulse: every open PR's CI rollup + review decision +
    /// mergeability in ONE query. GraphQL has no conditional 304 and lives in a
    /// SEPARATE 5000-point/hr bucket from the REST notifications spine (so the #8
    /// 304-discipline is untouched); a call costs ~1 point. A `401` surfaces as
    /// `.http(401, …)` (the notifications lane owns the auth-stop); a GraphQL
    /// `errors[]` body surfaces as `.decode` via the model decoder. Completion runs
    /// on a URLSession background queue.
    public func fetchOpenPullRequests(
        completion: @escaping (Result<[PullRequestPulse], GitHubClientError>) -> Void
    ) {
        if let pause = activePauseSeconds() { completion(.failure(.rateLimited(retryAfter: pause))); return }
        var req = URLRequest(url: baseURL.appendingPathComponent("graphql"))
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("githud/0.0.1", forHTTPHeaderField: "User-Agent")
        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: ["query": PullRequestPulse.openPRsQuery])
        } catch {
            completion(.failure(.transport("failed to encode graphql query")))
            return
        }
        let task = session.dataTask(with: req) { data, response, error in
            if let error { completion(.failure(.transport(error.localizedDescription))); return }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.transport("no HTTPURLResponse"))); return
            }
            // GraphQL's PRIMARY budget is a separate 5000-pt bucket, but a SECONDARY/abuse
            // limit (403/429 + Retry-After / X-RateLimit-Reset) is account-wide → honor the
            // shared pause so a limit here also backs off the REST spine (conservative).
            if let pause = Self.rateLimitPause(http) {
                self.openPause(seconds: pause)
                completion(.failure(.rateLimited(retryAfter: pause))); return
            }
            guard http.statusCode == 200, let data else {
                let body = data.map { String(decoding: $0.prefix(180), as: UTF8.self) } ?? ""
                completion(.failure(.http(http.statusCode, body))); return
            }
            do {
                completion(.success(try PullRequestPulse.list(fromGraphQLData: data)))
            } catch {
                completion(.failure(.decode("\(error)")))
            }
        }
        task.resume()
    }
}

/// The subset of a GitHub comment payload we need for enrichment — who wrote it
/// (bot/self demotion) and what it says (the preview).
struct LatestComment: Decodable {
    struct User: Decodable { let login: String; let type: String }
    let user: User
    let body: String?
}

/// The subset of `GET /user` we need — the authenticated login.
struct AuthUser: Decodable { let login: String }

/// The subset of a PR/Issue payload we need to tell merged/closed from open. `merged`/
/// `merged_at` are PR-only (absent for issues → nil → never "merged").
struct SubjectStateDTO: Decodable {
    let state: String
    let merged: Bool?
    let mergedAt: String?
    enum CodingKeys: String, CodingKey { case state, merged; case mergedAt = "merged_at" }
}
