import Foundation

/// Validators to send on the next conditional request.
public struct PollValidators: Sendable, Equatable {
    public let etag: String?
    public let lastModified: String?

    public init(etag: String? = nil, lastModified: String? = nil) {
        self.etag = etag
        self.lastModified = lastModified
    }

    public var isEmpty: Bool { etag == nil && lastModified == nil }

    /// Headers for a conditional GET. ETag (If-None-Match) is preferred;
    /// Last-Modified (If-Modified-Since) is the fallback.
    public var conditionalHeaders: [String: String] {
        var headers: [String: String] = [:]
        if let etag { headers["If-None-Match"] = etag }
        if let lastModified { headers["If-Modified-Since"] = lastModified }
        return headers
    }
}

/// The plan computed from a `/notifications` response: how to make the NEXT
/// request cheap, and when. GitHub's Notifications API returns `X-Poll-Interval`
/// (minimum seconds between polls) and supports conditional requests — a `304 Not
/// Modified` does NOT count against the primary rate limit. Honoring both is the
/// whole of RUBRIC #8 (polling discipline).
///
/// Pure + deterministic — jitter is the scheduler's job, not the plan's — so it is
/// unit-testable on recorded header fixtures with no network.
public struct PollPlan: Sendable, Equatable {
    /// 304 → reuse cached data, no rate-limit cost.
    public let notModified: Bool
    /// Send these on the next request to stay conditional.
    public let nextValidators: PollValidators
    /// Floor seconds until the next poll; the scheduler adds jitter on top.
    public let nextPollAfterSeconds: Int

    /// Minimum between polls when the server omits `X-Poll-Interval`.
    public static let defaultMinInterval = 60

    public static func from(
        status: Int,
        etag: String?,
        lastModified: String?,
        pollInterval: Int?,
        previousValidators: PollValidators = PollValidators(),
        minInterval: Int = defaultMinInterval
    ) -> PollPlan {
        let notModified = (status == 304)
        // On 304 the server may omit validators; keep the previous ones so the next
        // request stays conditional. On 200, adopt the fresh validators.
        let nextValidators: PollValidators
        if notModified {
            nextValidators = PollValidators(
                etag: etag ?? previousValidators.etag,
                lastModified: lastModified ?? previousValidators.lastModified
            )
        } else {
            nextValidators = PollValidators(etag: etag, lastModified: lastModified)
        }
        // X-Poll-Interval is a floor we must respect; never poll faster than minInterval.
        let interval = max(pollInterval ?? minInterval, minInterval)
        return PollPlan(notModified: notModified, nextValidators: nextValidators, nextPollAfterSeconds: interval)
    }
}
