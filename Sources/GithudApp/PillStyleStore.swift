import Foundation
import GithudCore

/// Persists the collapsed-pill vocabulary across launches (UserDefaults). Mirrors
/// `PulseStore`/`InboundStore`. Stored RAW (the enum's `rawValue`); an absent or
/// unrecognized key → the default (`.queueLeads`). No migration needed — a brand-new pref.
enum PillStyleStore {
    private static let key = "githud.pill.style"

    static func load() -> PillStyle {
        guard let raw = UserDefaults.standard.string(forKey: key),
              let style = PillStyle(rawValue: raw) else {
            return .queueLeads   // absent key / a value from a future build → the default
        }
        return style
    }

    static func save(_ style: PillStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: key)
    }
}
