import Foundation
import GithudCore

/// Persists the inbound-lane choice across launches (UserDefaults). Mirrors `PulseStore`.
enum InboundStore {
    private static let showHeldBackKey = "githud.inbound.showHeldBack"

    static func load() -> InboundPreferences {
        let showHeldBack = UserDefaults.standard.object(forKey: showHeldBackKey) as? Bool ?? false
        return InboundPreferences(showHeldBack: showHeldBack)
    }

    static func save(_ preferences: InboundPreferences) {
        UserDefaults.standard.set(preferences.showHeldBack, forKey: showHeldBackKey)
    }
}
