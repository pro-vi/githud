import Foundation
import GithudCore

/// Persists the user's H2 pulse-lane choices across launches (UserDefaults).
/// Mirrors `SurfaceStore`. Today: `showDrafts` + `showStale` (both default off).
enum PulseStore {
    private static let showDraftsKey = "githud.pulse.showDrafts"
    private static let showStaleKey = "githud.pulse.showStale"

    static func load() -> PulsePreferences {
        // Absent key → default (subsection hidden). Read via `object(forKey:)` so a missing
        // key is distinguishable from an explicit `false` (both yield hidden here, but the
        // contract stays clear if defaults change).
        let showDrafts = UserDefaults.standard.object(forKey: showDraftsKey) as? Bool ?? false
        let showStale = UserDefaults.standard.object(forKey: showStaleKey) as? Bool ?? false
        return PulsePreferences(showDrafts: showDrafts, showStale: showStale)
    }

    static func save(_ preferences: PulsePreferences) {
        UserDefaults.standard.set(preferences.showDrafts, forKey: showDraftsKey)
        UserDefaults.standard.set(preferences.showStale, forKey: showStaleKey)
    }
}
