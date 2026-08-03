import Foundation
import GithudCore

/// Loads the committed labeled fixture (`Tests/Fixtures/notifications.json`) and
/// turns it into radar rows — so `githud --fixture <path>` renders a POPULATED
/// island deterministically, with no PAT and no network. The fixture is the same
/// ground-truth set the classifier is tested against.
enum FixtureLoader {
    private struct Entry: Decodable { let thread: NotificationThread }

    static func rows(path: String, now: Date) -> [RadarRow] {
        guard let data = FileManager.default.contents(atPath: path),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else {
            return []
        }
        let radar = SignalClassifier.radar(entries.map { $0.thread })
        return RadarPresenter.rows(for: radar, now: now)
    }

    /// Loads the committed search fixture (`Tests/Fixtures/inbound-search.json`, cut from
    /// the user's REAL response) → inbound rows, so `githud --fixture-inbound <path>`
    /// renders the standing "Inbound" lane with no PAT and no network — closing the
    /// visual-proof gap the notifications-based fixtures have (they carry no selfLogin).
    static func inboundRows(path: String) -> [InboundRow] {
        guard let data = FileManager.default.contents(atPath: path),
              let reading = try? InboundItem.reading(fromSearchData: data) else {
            return []
        }
        return InboundPresenter.rows(for: reading.items)
    }

    /// Loads the committed GraphQL pulse fixture (`Tests/Fixtures/pulls.json`) → pulse
    /// rows, so `githud --fixture-pulse <path>` renders the H2 "Your PRs" lane with no
    /// PAT and no network. Same response shape the live GraphQL client decodes.
    static func pulseRows(path: String, now: Date) -> [PulseRow] {
        guard let data = FileManager.default.contents(atPath: path),
              let pulses = try? PullRequestPulse.list(fromGraphQLData: data) else {
            return []
        }
        return PulsePresenter.rows(for: pulses, now: now)
    }
}
