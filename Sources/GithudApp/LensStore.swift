import Foundation
import GithudCore

/// Persists the owner lens across launches (WP 2026-07-14-001). UserDefaults — per-machine
/// by nature, which IS the two-desk story: the work laptop and the personal laptop each
/// hold their own lens with zero sync machinery. Mirrors `PulseStore`/`SurfaceStore`.
/// The folded set persists as a DENYLIST array (see `LensPreferences`): an owner the file
/// has never seen leads by default, so new work never starts hidden.
enum LensStore {
    private static let groupByOwnerKey = "githud.lens.groupByOwner"
    private static let foldedOwnersKey = "githud.lens.foldedOwners"
    private static let ownerOrderKey = "githud.lens.ownerOrder"
    /// Lowercased owner → epoch seconds of the last time THIS machine opened (unfolded)
    /// the owner's group — the ledger line's "N new" clock. Rides UserDefaults beside the
    /// prefs it serves (same per-machine semantics; no Snapshot schema change needed).
    private static let lastOpenedKey = "githud.lens.lastOpened"

    static func load() -> LensPreferences {
        let grouped = UserDefaults.standard.object(forKey: groupByOwnerKey) as? Bool ?? false
        let folded = UserDefaults.standard.stringArray(forKey: foldedOwnersKey) ?? []
        let order = UserDefaults.standard.stringArray(forKey: ownerOrderKey) ?? []
        return LensPreferences(groupByOwner: grouped, foldedOwners: Set(folded), ownerOrder: order)
    }

    static func save(_ preferences: LensPreferences) {
        UserDefaults.standard.set(preferences.groupByOwner, forKey: groupByOwnerKey)
        UserDefaults.standard.set(Array(preferences.foldedOwners).sorted(), forKey: foldedOwnersKey)
        UserDefaults.standard.set(preferences.ownerOrder, forKey: ownerOrderKey)
    }

    static func loadLastOpened() -> [String: Date] {
        let raw = UserDefaults.standard.dictionary(forKey: lastOpenedKey) ?? [:]
        return raw.reduce(into: [:]) { acc, entry in
            if let seconds = entry.value as? Double {
                acc[entry.key] = Date(timeIntervalSince1970: seconds)
            }
        }
    }

    static func saveLastOpened(_ map: [String: Date]) {
        UserDefaults.standard.set(map.mapValues { $0.timeIntervalSince1970 }, forKey: lastOpenedKey)
    }
}
