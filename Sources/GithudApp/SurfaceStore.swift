import Foundation
import GithudCore

/// Persists the user's surface-reason choices across launches (UserDefaults).
enum SurfaceStore {
    private static let key = "githud.surface.enabledReasons"
    /// Write-era stamp: 2 = written by a build that knows the derived `inbound` reason.
    /// Gates the legacy migration below so it can only ever touch a PRE-inbound write —
    /// without it, a user who deliberately toggles inbound OFF persists exactly the
    /// legacy auto set and the next launch would silently re-enable it.
    private static let eraKey = "githud.surface.era"

    static func load() -> SurfacePreferences {
        guard let saved = UserDefaults.standard.array(forKey: key) as? [String] else {
            return .auto                                   // first run: start off auto
        }
        if UserDefaults.standard.integer(forKey: eraKey) < 2 {
            // Un-stamped = persisted before `inbound` existed. Core-owned rehydration:
            // a set equal to THAT release's auto set is an auto user, and follows auto
            // forward (tested in Core); any other un-stamped set was a real choice.
            return SurfacePreferences.fromStored(Set(saved))
        }
        return SurfacePreferences(enabledReasons: Set(saved))   // stamped write: verbatim
    }

    static func save(_ preferences: SurfacePreferences) {
        UserDefaults.standard.set(Array(preferences.enabledReasons), forKey: key)
        UserDefaults.standard.set(2, forKey: eraKey)
    }
}
