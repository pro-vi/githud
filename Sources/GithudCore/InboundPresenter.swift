import Foundation

/// A display-ready inbound row (pure data — no AppKit), mirroring `PulseRow`/`RadarRow`.
/// `Codable` so the last-good lane survives a relaunch (SnapshotStore convention).
public struct InboundRow: Sendable, Equatable, Codable {
    /// STABLE row identity — "owner/repo#7" (the D-reveal amendment-2 convention shared
    /// with `PulseRow.id`): the peek stash and the key session both key on it.
    public let id: String
    public let repo: String         // "pro-vi/mcp-filter #1"
    public let title: String
    public let subtitle: String     // "@arun" (+ "draft") — the age is NOT baked in
    /// ISO8601 **createdAt** — deliberately the OPENED time, not last-touched: the lane
    /// is a triage queue and its one honest age is how long the contributor has been
    /// WAITING ("28w" on a December PR is the point, not a bug).
    public let timestamp: String
    public let symbolName: String   // shape says what: PR pull-arrow vs issue dot-circle
    public let url: String
    public let isPR: Bool
    /// Bot-opened or draft — held back from the live glance into a quiet caption
    /// (default-off, gear-revealed), same demotion doctrine as everywhere else.
    public let isHeldBack: Bool
    /// Same drop-open-peeks-on-real-change rule as the other rows — over DISPLAYED
    /// fields only. `updatedAt` is deliberately absent (fix round): nothing rendered
    /// reads it, so including it would silently collapse a user's open peek (and force
    /// invisible repaints) on upstream activity that changes no visible text.
    public let changeSignature: String
}

/// The inbound lane's user choice (mirrors `PulsePreferences`): reveal the held-back
/// (bot/draft) group, default off — the caption keeps the count honest either way.
public struct InboundPreferences: Sendable, Equatable {
    public var showHeldBack: Bool
    public init(showHeldBack: Bool = false) { self.showHeldBack = showHeldBack }
    public func togglingShowHeldBack() -> InboundPreferences {
        InboundPreferences(showHeldBack: !showHeldBack)
    }
}

/// The lane split: `active` (human, non-draft — the live glance) and `heldBack`
/// (bots + drafts — a quiet count line unless the user opts in).
public struct InboundSections: Sendable, Equatable {
    public let active: [InboundRow]
    public let heldBack: [InboundRow]
}

/// Turns inbound items into glanceable rows. Mirrors `PulsePresenter` (injected `now`,
/// age formatted at render, pure + fixture-testable). The lane answers "what is open at
/// my door?" — standing state, the complement of the radar's `inbound` EVENT rows.
public enum InboundPresenter {
    /// PR vs issue, in GitHub's own visual language (shape carries the kind; ink tint —
    /// nothing here is a color-doctrine emergency).
    public static func symbolName(isPR: Bool) -> String {
        isPR ? "arrow.triangle.pull" : "dot.circle"
    }

    /// Subtitle members WITHOUT the age (appended at render from `timestamp`, like every
    /// other lane): the opener, and "draft" when it is one. PR-vs-issue is NOT restated —
    /// the glyph already says it (one fact, one place).
    public static func subtitle(for item: InboundItem) -> String {
        var parts = ["@\(item.authorLogin)"]
        if item.isDraft { parts.append("draft") }
        return parts.joined(separator: " · ")
    }

    public static func row(for item: InboundItem) -> InboundRow {
        let subtitleText = subtitle(for: item)
        return InboundRow(
            id: "\(item.repo)#\(item.number)",
            repo: "\(item.repo) #\(item.number)",
            title: item.title,
            subtitle: subtitleText,
            timestamp: item.createdAt,
            symbolName: symbolName(isPR: item.isPR),
            url: item.url,
            isPR: item.isPR,
            isHeldBack: item.isBot || item.isDraft,
            changeSignature: [item.title, subtitleText, item.createdAt]
                .joined(separator: "\u{1f}"))
    }

    /// The full rendered line — "repo · @opener · age" — age formatted AT RENDER from the
    /// row's waiting-since timestamp (never baked; `RadarPresenter.age` shared buckets).
    public static func displaySubtitle(for row: InboundRow, now: Date) -> String {
        let age = RadarPresenter.age(fromISO8601: row.timestamp, now: now)
        return [row.repo, row.subtitle, age.isEmpty ? nil : age]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Coarse displayed-age buckets — the scheduler re-renders when one flips, never
    /// otherwise (the same redraw-on-change-only contract as the other lanes).
    public static func ageSignature(for rows: [InboundRow], now: Date) -> [String] {
        rows.map { RadarPresenter.age(fromISO8601: $0.timestamp, now: now) }
    }

    /// The lane split + ordering. `active` is **waiting-longest first** — a triage QUEUE,
    /// not a news feed: the contributor who has waited since December leads, and a new
    /// arrival enters at the bottom (its *arrival* salience belongs to the radar's event
    /// row, not to queue-jumping here). Held-back (bots + drafts) sorts the same way.
    public static func sections(for items: [InboundItem]) -> InboundSections {
        let rows = items.map { row(for: $0) }.sorted { $0.timestamp < $1.timestamp }
        return InboundSections(active: rows.filter { !$0.isHeldBack },
                               heldBack: rows.filter { $0.isHeldBack })
    }

    /// Regroup ALREADY-PRESENTED rows by the flag each carries (the `PulsePresenter.
    /// sections(for rows:)` convention) — flat `[InboundRow]` rides the poll/snapshot
    /// spine; the grouping fact never drifts from what was computed at presentation.
    public static func sections(for rows: [InboundRow]) -> InboundSections {
        InboundSections(active: rows.filter { !$0.isHeldBack },
                        heldBack: rows.filter { $0.isHeldBack })
    }

    /// Flat, fully-ordered rows: active queue, then held-back.
    public static func rows(for items: [InboundItem]) -> [InboundRow] {
        let s = sections(for: items)
        return s.active + s.heldBack
    }

    /// Change-detection signature over every PRESENTATION-affecting field (the
    /// `changeKey` convention: excludes the derived age — and excludes `updatedAt`
    /// entirely, fix round: no rendered field reads it, so a comment landing upstream
    /// must not repaint a visually identical lane. Arrival, departure, a title edit,
    /// a draft flip, or an opener change all still move the key).
    public static func changeKey(for items: [InboundItem]) -> [String] {
        items.map {
            ["\($0.repo)#\($0.number)", $0.title, $0.authorLogin, String($0.isPR),
             String($0.isDraft), $0.createdAt].joined(separator: "\u{1f}")
        }
    }
}
