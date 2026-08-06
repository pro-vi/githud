import Foundation

/// The settings card's pure descriptor (mark-and-settings seed 2026-07-12-002 option B,
/// ratified in dogfood 2026-07-14) — mirrors `LensChooser`: Core decides the words and
/// the item set; the App only inks it. ONE card holds what the system dropdown held —
/// theme chips, the H1 reason set, the reveal toggles, Launch at Login, and doors into
/// the Pill-style and Lens cards — so config lives on the glass, not in system chrome.
/// No key moment: no editable field.
public struct SettingsCard: Equatable, Sendable {
    public struct CheckItem: Equatable, Sendable {
        public let id: String        // reason raw / "drafts" / "stale" / "heldBack" / "launch"
        public let label: String
        public let tooltip: String?
        public let on: Bool
    }
    public struct ThemeChip: Equatable, Sendable {
        public let id: String        // ThemeID raw
        public let name: String
        public let selected: Bool
    }

    public let title: String
    public let themeHeader: String
    public let themes: [ThemeChip]
    public let surfaceHeader: String
    public let reasons: [CheckItem]
    public let pulseHeader: String
    public let pulseItems: [CheckItem]
    public let inboundHeader: String
    public let inboundItems: [CheckItem]
    public let launchAtLogin: CheckItem
    public let pillStyleDoor: String
    public let lensDoor: String
    /// Like its card siblings: no field, never takes key (focus-non-theft).
    public static let takesKeyMoment = false

    /// The receipts row's sentinel id. Named here so the card that emits it and the app
    /// that dispatches on it (AppDelegate.toggleReason) share ONE literal — a rename on
    /// one side alone would silently route the toggle into `SurfacePreferences.toggling`
    /// and write a junk reason key.
    public static let justClearedItemID = "justCleared"

    /// Built fresh at every render while the card is up (the lens-card rule): the checks
    /// can never disagree with the prefs behind them.
    public static func make(surface: SurfacePreferences, pulse: PulsePreferences,
                            inbound: InboundPreferences, themeID: ThemeID,
                            launchAtLogin: Bool,
                            showJustCleared: Bool = false) -> SettingsCard {
        SettingsCard(
            title: PlainWords.settingsCardTitle,
            themeHeader: PlainWords.settingsThemeHeader,
            themes: ThemeID.all.map {
                ThemeChip(id: $0.rawValue, name: $0.displayName, selected: $0 == themeID)
            },
            surfaceHeader: PlainWords.settingsSurfaceHeader,
            reasons: SurfacePreferences.allReasons.map {
                CheckItem(id: $0, label: RadarPresenter.reasonLabel($0), tooltip: nil,
                          on: surface.isEnabled($0))
            } + [
                // The receipts band rides the radar section (land-triage F5): not a
                // reason, but the same lane — dispatched by its sentinel id, which the
                // reason toggler branches on (never a SurfacePreferences key).
                CheckItem(id: SettingsCard.justClearedItemID, label: PlainWords.justClearedGearItem,
                          tooltip: PlainWords.justClearedGearTooltip, on: showJustCleared),
            ],
            pulseHeader: PlainWords.settingsPRHeader,
            pulseItems: [
                CheckItem(id: "drafts", label: PlainWords.draftsGearItem,
                          tooltip: PlainWords.draftsGearTooltip, on: pulse.showDrafts),
                CheckItem(id: "stale", label: PlainWords.staleGearItem,
                          tooltip: PlainWords.staleGearTooltip, on: pulse.showStale),
            ],
            inboundHeader: PlainWords.settingsInboundHeader,
            inboundItems: [
                CheckItem(id: "heldBack", label: PlainWords.heldBackGearItem,
                          tooltip: PlainWords.heldBackGearTooltip, on: inbound.showHeldBack),
            ],
            launchAtLogin: CheckItem(id: "launch", label: PlainWords.launchAtLoginItem,
                                     tooltip: nil, on: launchAtLogin),
            pillStyleDoor: PlainWords.pillStyleDoor,
            lensDoor: PlainWords.lensDoor)
    }
}
