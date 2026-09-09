import Foundation
import GithudCore

/// Test-only boundary for the living prototype's synthetic inputs. These are
/// display rows, not any of FixtureLoader's GitHub response formats.
struct PrototypeFixture: Decodable {
    let schemaVersion: Int
    let provenance: String
    let now: String
    let selfLogin: String
    let rowSets: [String: Rows]

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version", provenance, now
        case selfLogin = "self_login", rowSets = "row_sets"
    }

    struct Rows: Decodable {
        let radar: [RadarRow]
        let inbound: [InboundRow]
        let pulse: [PulseRow]
        var ids: [String] { radar.map(\.id) + inbound.map(\.id) + pulse.map(\.id) }
    }

    struct Metadata: Decodable {
        let schemaVersion: Int
        let id: String
        let fixture: String
        let scenarios: [Scenario]
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version", id, fixture, scenarios
        }
    }

    struct Scenario: Decodable {
        enum Session: String, Decodable { case keyboard, mouse }
        enum Reading: String, Decodable { case fresh, loading, offline }
        let id: String
        let label: String
        let rowSet: String
        let query: String
        let session: Session
        let freshness: Reading
        let preferences: Preferences
        let expected: Expected
        enum CodingKeys: String, CodingKey {
            case id, label, query, session, freshness, preferences, expected
            case rowSet = "row_set"
        }
    }

    struct Preferences: Decodable {
        let showDrafts: Bool
        let showStale: Bool
        let showHeldBack: Bool
        let foldedOwners: [String]
        let groupByOwner: Bool
        let ownerOrder: [String]
        var pulse: PulsePreferences {
            PulsePreferences(showDrafts: showDrafts, showStale: showStale)
        }
        var inbound: InboundPreferences { InboundPreferences(showHeldBack: showHeldBack) }
        var lens: LensPreferences {
            LensPreferences(groupByOwner: groupByOwner, foldedOwners: Set(foldedOwners),
                            ownerOrder: ownerOrder)
        }
    }

    struct Expected: Decodable {
        let matchedIDs: [String]
        let localIDs: [String]
        let count: String?
        let walk: [String]
        let selectedID: String?
        let destination: String?
        let openURL: String?
        let browseIDs: [String]
        enum CodingKeys: String, CodingKey {
            case count, walk, destination
            case matchedIDs = "matched_ids", localIDs = "local_ids"
            case selectedID = "selected_id", openURL = "open_url", browseIDs = "browse_ids"
        }
    }

    struct Loaded {
        let fixture: PrototypeFixture
        let metadata: Metadata
        let referenceTime: Date
    }

    static func load(repo: URL) throws -> Loaded {
        let root = repo.resolvingSymlinksInPath().standardizedFileURL
        let metadataURL = root.appendingPathComponent("docs/design/prototypes/quick-navigator.json")
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(Metadata.self, from: Data(contentsOf: metadataURL))
        let fixtureURL = metadataURL.deletingLastPathComponent()
            .appendingPathComponent(metadata.fixture).standardizedFileURL.resolvingSymlinksInPath()
        guard fixtureURL.path.hasPrefix(root.path + "/Tests/Fixtures/") else {
            throw invalid("fixture must remain inside Tests/Fixtures")
        }
        let fixture = try decoder.decode(PrototypeFixture.self, from: Data(contentsOf: fixtureURL))
        guard metadata.schemaVersion == 1, fixture.schemaVersion == 1,
              metadata.id == "quick-navigator", fixture.provenance == "synthetic",
              let now = ISO8601DateFormatter().date(from: fixture.now),
              !metadata.scenarios.isEmpty else { throw invalid("unsupported or incomplete prototype") }
        guard Set(metadata.scenarios.map(\.id)).count == metadata.scenarios.count else {
            throw invalid("duplicate scenario IDs")
        }
        for rows in fixture.rowSets.values {
            guard Set(rows.ids).count == rows.ids.count,
                  !rows.ids.contains(KeySession.destinationID) else {
                throw invalid("duplicate or reserved row ID")
            }
        }
        for scenario in metadata.scenarios {
            guard fixture.rowSets[scenario.rowSet] != nil else {
                throw invalid("unknown row set for \(scenario.id)")
            }
        }
        return Loaded(fixture: fixture, metadata: metadata, referenceTime: now)
    }

    private static func invalid(_ message: String) -> NSError {
        NSError(domain: "PrototypeFixture", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
