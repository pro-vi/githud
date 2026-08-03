import Foundation

/// Persists the "Just cleared" reveal choice across launches (plan 2026-07-21-001).
/// Mirrors `InboundStore` — the buffer itself is session-scoped and never persisted;
/// only the user's show/hide preference survives a relaunch.
enum ClearedStore {
    private static let showKey = "githud.cleared.show"

    static func load() -> Bool {
        UserDefaults.standard.object(forKey: showKey) as? Bool ?? false
    }

    static func save(_ show: Bool) {
        UserDefaults.standard.set(show, forKey: showKey)
    }
}
