import Foundation

/// A display-ready radar row (pure data — no AppKit), so the island's content can
/// be unit-tested headlessly and the view layer stays dumb. `Codable` so the last-good
/// set survives a relaunch (see `SnapshotStore`).
public struct RadarRow: Sendable, Equatable, Codable {
    /// STABLE row identity — the notification thread's own id (D-reveal amendment 2,
    /// WP-3d′): the peek stash keys on this, NEVER on `url` (optional, and two threads in
    /// one repo collide on the repo-page fallback). Constant for a thread's whole life.
    public let id: String
    public let repo: String        // "owner/repo"
    public let title: String
    public let subtitle: String    // "@alice · review requested" — the age is NOT baked in
    public let timestamp: String   // ISO8601 updatedAt — the age is formatted AT RENDER from this,
                                   // never a stale "· 2h" string (an age that reads wrong is a fabricated state)
    public let urgency: Int
    public let symbolName: String  // SF Symbol for the reason (leading row icon)
    public let isCritical: Bool    // a categorical emergency (security_alert) — earns the
                                   // ONE reserved glyph color + critical-first sort (consult 008)
    public let url: String?        // where clicking opens (Open-on-GitHub)
    public let excerpt: String?    // 1-line preview of the latest comment (enriched)
    /// Per-row change signature over the row's DISPLAY TEXTS + their age source (D-reveal
    /// amendment 2): same id + changed signature ⇒ the content is new (a fresh comment, an
    /// enrichment landing, a retitle) — an open peek keyed on the old signature drops and
    /// the row re-truncates honestly. See `RadarPresenter.changeSignature`.
    public let changeSignature: String
}

/// Turns classified threads into glanceable rows. Relative age is computed against
/// an injected `now` so it is deterministic in tests.
public enum RadarPresenter {
    private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Compact relative age: "now" · "5m" · "2h" · "3d" · "2w".
    public static func age(fromISO8601 string: String, now: Date) -> String {
        guard let date = iso.date(from: string) else { return "" }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(Int(seconds / 60))m"
        case ..<86_400: return "\(Int(seconds / 3600))h"
        case ..<604_800: return "\(Int(seconds / 86_400))d"
        default: return "\(Int(seconds / 604_800))w"
        }
    }

    /// SF Symbol that conveys the *kind* of attention a row needs (the shape carries
    /// the type; urgency carries the tint). Resolves the blind-read "ambiguous dots".
    public static func symbolName(for reason: String) -> String {
        switch reason {
        case "review_requested": return "arrow.triangle.pull"
        case "mention": return "at"
        case "team_mention": return "person.2.fill"
        case "assign": return "person.crop.circle.badge.checkmark"
        case "author": return "bubble.left.fill"
        case "comment": return "bubble.left"
        case "security_alert": return "exclamationmark.shield.fill"
        case "invitation": return "envelope.fill"
        case "your_activity": return "person.crop.circle"
        case "inbound": return "tray.and.arrow.down.fill"   // arriving at your door (derived reason)
        default: return "bell.fill"
        }
    }

    /// Human label for a notification reason.
    public static func reasonLabel(_ reason: String) -> String {
        switch reason {
        case "review_requested": return "review requested"
        case "mention": return "mentioned you"
        case "team_mention": return "team mentioned"
        case "assign": return "assigned to you"
        case "author": return "new activity"
        case "comment": return "commented"
        case "security_alert": return "security alert"
        case "invitation": return "invitation"
        case "your_activity": return "your activity"
        case "inbound": return "opened on your repo"   // derived reason — one label for menu + row
        default: return reason
        }
    }

    /// The GitHub html target for a thread (Open-on-GitHub — the H3 guardrail: we
    /// open the thread, we don't act on it from the HUD). Maps the API URL to the
    /// web URL, falling back to the repo page.
    public static func htmlURL(for thread: NotificationThread) -> String? {
        if let api = thread.subject.url, api.contains("api.github.com/repos/") {
            return api
                .replacingOccurrences(of: "https://api.github.com/repos/", with: "https://github.com/")
                .replacingOccurrences(of: "/pulls/", with: "/pull/")
                .replacingOccurrences(of: "/commits/", with: "/commit/")   // Commit subject → web /commit/SHA
        }
        // Non-api.github.com (GHE) + Release/Discussion subjects without a clean web map
        // fall back to the repo page — a valid link, not a 404. (Per-host/GHE mapping deferred.)
        return "https://github.com/\(thread.repository.fullName)"
    }

    /// A 1-line preview of a comment body: newlines/whitespace collapsed, truncated.
    public static func excerpt(from body: String?, maxLength: Int = 100) -> String? {
        guard let body else { return nil }
        let oneLine = body
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
        guard !oneLine.isEmpty else { return nil }
        if oneLine.count <= maxLength { return oneLine }
        return String(oneLine.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The per-row change signature (see `RadarRow.changeSignature`): the three display
    /// texts + the timestamp their rendered age derives from. Computed from the SAME
    /// values the row carries, so it cannot drift from what is actually on screen.
    /// (Field separator: US, 0x1F — never in the data; same convention as `changeKey`.)
    public static func changeSignature(title: String, subtitle: String,
                                       timestamp: String, excerpt: String?) -> String {
        [title, subtitle, timestamp, excerpt ?? ""].joined(separator: "\u{1f}")
    }

    public static func row(for item: RankedThread, now: Date) -> RadarRow {
        let thread = item.thread
        let actor = thread.latestCommentAuthorLogin.map { "@\($0)" }
        // The age is deliberately NOT baked into `subtitle` — it is formatted at render from
        // `timestamp` (see `displaySubtitle`), so a long-lived row can never show a stale age.
        // Label + glyph key off the item's EFFECTIVE reason (raw, unless the inbound
        // derivation upgraded it in radar()/suppressed() where selfLogin lives) — so an
        // opened-on-your-repo row reads "opened on your repo", never "subscribed".
        let subtitle = [actor, reasonLabel(item.effectiveReason)]
            .compactMap { $0 }
            .joined(separator: " · ")
        return RadarRow(
            id: thread.id,
            repo: thread.repository.fullName,
            title: thread.subject.title,
            subtitle: subtitle,
            timestamp: thread.updatedAt,
            urgency: item.classification.urgency,
            symbolName: symbolName(for: item.effectiveReason),
            isCritical: SignalClassifier.isCritical(thread),
            url: htmlURL(for: thread),
            excerpt: thread.latestCommentExcerpt,
            changeSignature: changeSignature(title: thread.subject.title, subtitle: subtitle,
                                             timestamp: thread.updatedAt,
                                             excerpt: thread.latestCommentExcerpt)
        )
    }

    public static func rows(for items: [RankedThread], now: Date) -> [RadarRow] {
        items.map { row(for: $0, now: now) }
    }

    /// The full subtitle line the island renders — "repo · <subtitle> · age" — with the age
    /// formatted AT RENDER from the row's `timestamp` (never a baked string). The view calls
    /// this with `Date()`; tests call it with an injected `now`, so the EXACT string shown is a
    /// pure, testable function and no stale baked age can exist (expand-after-hours → correct age).
    public static func displaySubtitle(for row: RadarRow, now: Date) -> String {
        let age = age(fromISO8601: row.timestamp, now: now)
        return [row.repo, row.subtitle, age.isEmpty ? nil : age]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// The coarse displayed-age bucket per row (the vocabulary string "now"/"5m"/"2h"/…). The
    /// live scheduler compares this across poll ticks: when a bucket flips, a row's rendered age
    /// would change, so it re-renders — but ONLY on a real flip (an identical signature adds no
    /// redraw, preserving the redraw-on-change-only idle-footprint contract; between-tick
    /// staleness is bounded by one poll interval, which is honest). Pure + unit-tested.
    public static func ageSignature(for rows: [RadarRow], now: Date) -> [String] {
        rows.map { age(fromISO8601: $0.timestamp, now: now) }
    }

    /// Change-detection signature for a radar set: a per-thread string over every
    /// *display-affecting* field — id, updatedAt, title, EFFECTIVE reason (the same field
    /// `row()` renders from: a subscribed→inbound flip is a display change and must
    /// repaint even if urgency ever held still), latest-comment author, excerpt, urgency —
    /// so a same-id update (a new comment, an enrichment landing, a reclassification, an
    /// in-place escalation) actually re-renders. Deliberately EXCLUDES the derived
    /// relative age ("2h"), which would force a redraw every poll and defeat the
    /// redraw-on-change-only idle-footprint contract. The live scheduler compares this;
    /// pure + testable here. (Field separator: US, 0x1F, never in the data.)
    public static func changeKey(for radar: [RankedThread]) -> [String] {
        radar.map {
            [$0.thread.id, $0.thread.updatedAt, $0.thread.subject.title, $0.effectiveReason,
             $0.thread.latestCommentAuthorLogin ?? "", $0.thread.latestCommentExcerpt ?? "",
             String($0.classification.urgency)].joined(separator: "\u{1f}")
        }
    }
}
