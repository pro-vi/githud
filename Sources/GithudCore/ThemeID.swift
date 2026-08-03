import Foundation

/// Which visual theme the island renders in — the user-selectable BRAND-theme axis,
/// orthogonal to system light/dark (which stays on `NSAppearance`). Pure id + registry;
/// the AppKit token mapping lives in GithudApp's `Theme` (NSColor/Material/SF-Symbols
/// can't live in this zero-dep, headless-testable module).
public enum ThemeID: String, CaseIterable, Sendable, Equatable {
    case geistMono = "geist-mono"
    case github
    case color
    case dracula
    case nord
    case tokyoNight = "tokyo-night"
    case catppuccin
    case solarizedDark = "solarized-dark"
    case solarizedLight = "solarized-light"

    /// The default — reproduces githud's original look exactly (backward-compat).
    public static let `default`: ThemeID = .color

    /// Display order for the picker (default first; the Solarized pair last, dark then light).
    public static let all: [ThemeID] = [
        .color, .geistMono, .github, .dracula, .nord, .tokyoNight, .catppuccin, .solarizedDark, .solarizedLight,
    ]

    public var displayName: String {
        switch self {
        case .geistMono:       return "Geist Mono"
        case .github:          return "GitHub"
        case .color:           return "Color"
        case .dracula:         return "Dracula"
        case .nord:            return "Nord"
        case .tokyoNight:      return "Tokyo Night"
        case .catppuccin:      return "Catppuccin"
        case .solarizedDark:   return "Solarized Dark"
        case .solarizedLight:  return "Solarized Light"
        }
    }
}
