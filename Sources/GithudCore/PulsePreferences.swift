import Foundation

/// Which parts of the H2 pulse lane the user surfaces. Two default-off subsections keep
/// the live "Your PRs" glance clean:
///   • `showDrafts` — draft PRs ("ignore me, WIP"), grouped by the `isDraft` fact.
///   • `showStale`  — rotting PRs (untouched 14d+), grouped by the `isStale` fact, so a
///     4-month-old conflicted PR never dominates the glance (it stays one toggle away —
///     a quiet count still shows when collapsed, so the backlog is honest, not hidden).
/// Both group by a PR *fact*, not by `PulseState`, so a stale/draft PR with failing CI
/// never bubbles into the main lane or the calm pill gauge. Mirrors `SurfacePreferences`.
public struct PulsePreferences: Sendable, Equatable {
    /// Show draft PRs as a separate grouped subsection. Default `false`.
    public var showDrafts: Bool
    /// Expand the rotting-PR backlog (untouched 14d+) inline. Default `false` (a count
    /// caption still shows, so you know it exists without it crowding the live lane).
    public var showStale: Bool

    public static let `default` = PulsePreferences(showDrafts: false, showStale: false)

    public init(showDrafts: Bool, showStale: Bool = false) {
        self.showDrafts = showDrafts
        self.showStale = showStale
    }

    public func togglingShowDrafts() -> PulsePreferences {
        PulsePreferences(showDrafts: !showDrafts, showStale: showStale)
    }

    public func togglingShowStale() -> PulsePreferences {
        PulsePreferences(showDrafts: showDrafts, showStale: !showStale)
    }
}
