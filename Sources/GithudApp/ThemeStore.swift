import Foundation
import GithudCore

/// Persists the user's selected theme across launches (UserDefaults). Mirrors
/// `SurfaceStore`/`PulseStore`. An unknown/absent stored value → the default theme.
enum ThemeStore {
    private static let key = "githud.theme"

    static func load() -> ThemeID {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let id = ThemeID(rawValue: raw) else {
            return .default
        }
        return id
    }

    static func save(_ id: ThemeID) {
        UserDefaults.standard.set(id.rawValue, forKey: key)
    }
}
