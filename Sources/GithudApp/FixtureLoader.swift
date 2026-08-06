import Foundation
import GithudCore

/// Loads the committed labeled fixture (`Tests/Fixtures/notifications.json`) and
/// turns it into radar rows — so `githud --fixture <path>` renders a POPULATED
/// island deterministically, with no PAT and no network. The fixture is the same
/// ground-truth set the classifier is tested against.
enum FixtureLoader {
    private struct Entry: Decodable { let thread: NotificationThread }

    /// A failed load still renders an empty lane (unchanged), but it SAYS SO on stderr.
    /// Silence made a schema-drifted fixture indistinguishable from one with no
    /// qualifying rows — the exact confusion a visual-proof run has to notice.
    private static func complain(_ message: String) {
        FileHandle.standardError.write(Data("githud: \(message)\n".utf8))
    }

    /// Reads the file, or reports why it could not.
    private static func fixtureData(path: String) -> Data? {
        guard let data = FileManager.default.contents(atPath: path) else {
            complain("fixture not readable at \(path)")
            return nil
        }
        return data
    }

    static func rows(path: String, now: Date) -> [RadarRow] {
        guard let data = fixtureData(path: path) else { return [] }
        let entries: [Entry]
        do { entries = try JSONDecoder().decode([Entry].self, from: data) }
        catch {
            complain("fixture decode failed (\(path)): \(error)")
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
        guard let data = fixtureData(path: path) else { return [] }
        let reading: InboundReading
        do { reading = try InboundItem.reading(fromSearchData: data) }
        catch {
            complain("inbound fixture decode failed (\(path)): \(error)")
            return []
        }
        return InboundPresenter.rows(for: reading.items)
    }

    /// Loads the committed GraphQL pulse fixture (`Tests/Fixtures/pulls.json`) → pulse
    /// rows, so `githud --fixture-pulse <path>` renders the H2 "Your PRs" lane with no
    /// PAT and no network. Same response shape the live GraphQL client decodes.
    static func pulseRows(path: String, now: Date) -> [PulseRow] {
        guard let data = fixtureData(path: path) else { return [] }
        let pulses: [PullRequestPulse]
        do { pulses = try PullRequestPulse.list(fromGraphQLData: data) }
        catch {
            complain("pulse fixture decode failed (\(path)): \(error)")
            return []
        }
        return PulsePresenter.rows(for: pulses, now: now)
    }
}
