import AppKit
import GithudCore

/// How a theme draws the island surface.
enum ThemeSurface {
    case vibrant(NSVisualEffectView.Material)   // translucent — picks up the desktop (Color)
    case solid(NSColor)                          // exact brand color (Geist/GitHub/Dracula/Nord)
}

/// A theme = a bundle of presentation tokens, one active at a time (held by `AppModel`
/// as `themeID`, applied via `model.setThemeID`). Pure presentation — it never touches the
/// classifier or pulse logic. `radarGlyphColor` carries the color DOCTRINE (consult 008) for
/// the H1 radar — ink by default, color only on a changed next-move. (H2 PR status is NOT
/// themed: it uses GitHub's canonical icons — see `GitHubStatus` — theme-independent.)
/// Mirrors `SurfacePreferences`' value + factory shape.
struct Theme: Equatable {
    let id: ThemeID
    let surface: ThemeSurface
    let border: NSColor
    // text tiers
    let inkPrimary: NSColor
    let inkSecondary: NSColor
    let inkTertiary: NSColor
    // accent (count badge)
    let accent: NSColor
    let badgeInk: NSColor
    // state palette. Post color-doctrine (consult 008) color marks only a CHANGED
    // next-move: `danger` (intervene/contain) + `success` (action unlocked). The other
    // three are kept as palette vocabulary, not a mandate to use every word.
    let danger: NSColor     // blocked · CI failing · the ONE reserved H1 critical (security_alert)
    let warn: NSColor       // RESERVED — no consumer (was the urgency heat 70–90 tier)
    let caution: NSColor    // RESERVED — for DEGRADED READING confidence (stale/poll-fail/freshness); no UI yet
    let success: NSColor    // ready — a positive action (merge) just became available
    let neutral: NSColor    // RESERVED — calm gray (draft now uses inkTertiary; ordinary radar glyph uses inkSecondary)
    // glyph treatment
    let monochrome: Bool    // Geist: state via fill/outline + ink tiers, not hue
    let hoverFill: NSColor
    let grainOpacity: CGFloat

    static func == (lhs: Theme, rhs: Theme) -> Bool { lhs.id == rhs.id }

    /// Surface coerced to solid when Reduce Transparency is on (a11y). Affects only the
    /// rendered material — never the user's stored `ThemeID`. Only the Color theme uses a
    /// `.vibrant` surface, and it draws DYNAMIC system text (`.labelColor`, dark in Light
    /// mode) — so the opaque fallback must be APPEARANCE-AWARE (`windowBackgroundColor`),
    /// not a fixed dark fill, or Light-mode + Reduce-Transparency would be dark-on-dark.
    func effectiveSurface(reduceTransparency: Bool) -> ThemeSurface {
        if reduceTransparency, case .vibrant = surface {
            return .solid(.windowBackgroundColor)
        }
        return surface
    }

    /// Increase-Contrast (a11y) coercion — same shape as `effectiveSurface`: a RENDERING-ONLY
    /// adjusted copy (never mutates the stored theme/`ThemeID`). Three moves, all additive
    /// (no new color introduced, no semantic repurposed — the color-doctrine vocabulary is
    /// untouched): (1) the border goes fully opaque (its softness is the whole reason it needs
    /// help — a translucent hairline is the first thing Increase Contrast users lose); (2) the
    /// hover fill's alpha is strengthened, so "this is clickable" reads unmistakably; (3) the
    /// tertiary ink tier is promoted to secondary, so the dimmest text (captions, "N stale…"
    /// counts, the loading dot) no longer sits at a contrast level a low-vision user can't read.
    func effectiveTheme(increaseContrast: Bool) -> Theme {
        guard increaseContrast else { return self }
        return Theme(
            id: id, surface: surface, border: border.withAlphaComponent(1.0),
            inkPrimary: inkPrimary, inkSecondary: inkSecondary, inkTertiary: inkSecondary,
            accent: accent, badgeInk: badgeInk,
            danger: danger, warn: warn, caution: caution, success: success, neutral: neutral,
            monochrome: monochrome,
            hoverFill: hoverFill.withAlphaComponent(min(1.0, hoverFill.alphaComponent * 2.2)),
            grainOpacity: grainOpacity)
    }

    /// Border thickness — 0.5px (a crisp hairline) by default; Increase Contrast (a11y)
    /// promotes it to a full opaque 1px (paired with `effectiveTheme`'s border-alpha bump).
    static func borderWidth(increaseContrast: Bool) -> CGFloat { increaseContrast ? 1.0 : 0.5 }

    /// Radar reason-glyph tint (color doctrine, consult 008). INK BY DEFAULT — the glyph
    /// SHAPE carries the kind and the SORT carries urgency, so color is NOT a redundant
    /// urgency heat scale (the old 4-band red/orange/yellow/gray is gone). The ONE reserved
    /// exception: a categorical emergency (`SignalClassifier.criticalReasons`, i.e.
    /// security_alert) gets `danger` so it still pops pre-attentively — and it sorts
    /// critical-first, so the red glyph is never stranded below a calm row. Monochrome
    /// themes pop it via `danger` too (which equals their bright ink) plus the shield shape.
    func radarGlyphColor(critical: Bool) -> NSColor {
        critical ? danger : inkSecondary
    }

    // MARK: - registry

    static func named(_ id: ThemeID) -> Theme {
        switch id {
        case .color:
            return Theme(
                id: .color, surface: .vibrant(.popover),
                border: NSColor.white.withAlphaComponent(0.12),
                inkPrimary: .labelColor, inkSecondary: .secondaryLabelColor, inkTertiary: .tertiaryLabelColor,
                accent: .controlAccentColor, badgeInk: .white,
                danger: .systemRed, warn: .systemOrange, caution: .systemYellow,
                success: .systemGreen, neutral: .systemGray,
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.07), grainOpacity: 0)
        case .geistMono:
            return Theme(
                id: .geistMono, surface: .solid(hex(0x16161A)),
                border: NSColor.white.withAlphaComponent(0.10),
                inkPrimary: white(0.95), inkSecondary: white(0.50), inkTertiary: white(0.28),
                accent: white(0.92), badgeInk: hex(0x16161A),
                danger: white(0.95), warn: white(0.55), caution: white(0.55),
                success: white(0.55), neutral: white(0.40),
                monochrome: true, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0.055)
        case .github:
            return Theme(
                id: .github, surface: .solid(hex(0x0D1117)),
                border: hex(0x30363D),
                inkPrimary: hex(0xE6EDF3), inkSecondary: hex(0x7D8590), inkTertiary: hex(0x484F58),
                accent: hex(0x2F81F7), badgeInk: .white,
                danger: hex(0xF85149), warn: hex(0xD29922), caution: hex(0xD29922),
                success: hex(0x3FB950), neutral: hex(0x484F58),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .dracula:
            // ink tiers use Dracula's OWN family — foreground + the signature comment
            // purple (#6272A4) for dim text — so subtitles read distinctly "Dracula",
            // not a generic gray dark theme.
            return Theme(
                id: .dracula, surface: .solid(hex(0x282A36)),
                border: hex(0x44475A),
                inkPrimary: hex(0xF8F8F2), inkSecondary: hex(0x6272A4), inkTertiary: hex(0x565F89),
                accent: hex(0xBD93F9), badgeInk: hex(0x282A36),
                danger: hex(0xFF5555), warn: hex(0xFFB86C), caution: hex(0xF1FA8C),
                success: hex(0x50FA7B), neutral: hex(0x6272A4),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .nord:
            return Theme(
                id: .nord, surface: .solid(hex(0x2E3440)),
                border: hex(0x434C5E),
                inkPrimary: hex(0xECEFF4), inkSecondary: hex(0x9AA6BD), inkTertiary: hex(0x4C566A),
                accent: hex(0x88C0D0), badgeInk: hex(0x2E3440),
                danger: hex(0xBF616A), warn: hex(0xD08770), caution: hex(0xEBCB8B),
                success: hex(0xA3BE8C), neutral: hex(0x4C566A),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .tokyoNight:
            return Theme(
                id: .tokyoNight, surface: .solid(hex(0x1A1B26)),
                border: hex(0x2F3549),
                inkPrimary: hex(0xC0CAF5), inkSecondary: hex(0x787C99), inkTertiary: hex(0x414868),
                accent: hex(0x7AA2F7), badgeInk: hex(0x1A1B26),
                danger: hex(0xF7768E), warn: hex(0xFF9E64), caution: hex(0xE0AF68),
                success: hex(0x9ECE6A), neutral: hex(0x565F89),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .catppuccin:
            return Theme(
                id: .catppuccin, surface: .solid(hex(0x1E1E2E)),
                border: hex(0x313244),
                inkPrimary: hex(0xCDD6F4), inkSecondary: hex(0xA6ADC8), inkTertiary: hex(0x6C7086),
                accent: hex(0xCBA6F7), badgeInk: hex(0x1E1E2E),
                danger: hex(0xF38BA8), warn: hex(0xFAB387), caution: hex(0xF9E2AF),
                success: hex(0xA6E3A1), neutral: hex(0x6C7086),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .solarizedDark:
            // The dark counterpart to Solarized Light — base03 ground, base0/base1 ink.
            return Theme(
                id: .solarizedDark, surface: .solid(hex(0x002B36)),
                border: NSColor.white.withAlphaComponent(0.08),
                inkPrimary: hex(0x93A1A1), inkSecondary: hex(0x839496), inkTertiary: hex(0x586E75),
                accent: hex(0x268BD2), badgeInk: hex(0xFDF6E3),
                danger: hex(0xDC322F), warn: hex(0xCB4B16), caution: hex(0xB58900),
                success: hex(0x859900), neutral: hex(0x586E75),
                monochrome: false, hoverFill: NSColor.white.withAlphaComponent(0.06), grainOpacity: 0)
        case .solarizedLight:
            // The lone LIGHT theme: dark ink on warm cream. hoverFill flips to BLACK-alpha
            // (a white hover would be invisible on a light surface).
            return Theme(
                id: .solarizedLight, surface: .solid(hex(0xFDF6E3)),
                border: NSColor.black.withAlphaComponent(0.12),
                inkPrimary: hex(0x586E75), inkSecondary: hex(0x657B83), inkTertiary: hex(0x93A1A1),
                accent: hex(0x268BD2), badgeInk: hex(0xFDF6E3),
                danger: hex(0xDC322F), warn: hex(0xCB4B16), caution: hex(0xB58900),
                success: hex(0x859900), neutral: hex(0x93A1A1),
                monochrome: false, hoverFill: NSColor.black.withAlphaComponent(0.05), grainOpacity: 0)
        }
    }

    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                green: CGFloat((v >> 8) & 0xFF) / 255.0,
                blue: CGFloat(v & 0xFF) / 255.0, alpha: 1.0)
    }
    private static func white(_ alpha: CGFloat) -> NSColor { NSColor(white: 1.0, alpha: alpha) }
}
