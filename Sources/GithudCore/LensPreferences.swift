import Foundation

/// WP 2026-07-14-001 — the owner lens: which repo owners lead the "Your PRs" lane on
/// THIS machine, and whether the lane wears owner titles at all. Two orthogonal facts:
///   • `groupByOwner` — the lane's SHAPE (titled owner groups vs the one flat list).
///     Default `false`: the feature is opt-in; "now" stays the default until the user
///     reaches for the eye.
///   • `foldedOwners` — WHO LEADS, applied in both shapes (the ratified amendment: the
///     toggle changes shape, never visibility). Persisted as a DENYLIST so an owner the
///     app has never seen leads by default — new work never starts hidden (RUBRIC #11:
///     misses are fatal; a fold always leaves a counted ledger line behind).
/// Logins compare case-insensitively (GitHub's rule); the set stores lowercase and
/// callers pass any casing. Mirrors `PulsePreferences`; UserDefaults I/O lives in the
/// App-side `LensStore`.
public struct LensPreferences: Sendable, Equatable {
    /// The lane's shape: owner-titled groups (`true`) or the one flat list (`false`).
    public var groupByOwner: Bool
    /// Lowercased logins of owners folded on this machine (the denylist).
    public private(set) var foldedOwners: Set<String>
    /// The user's drag order for owner groups + ledger lines (dogfood 2026-07-14),
    /// lowercased + deduped. Owners not placed here fall back to discovery (lead-row)
    /// order AFTER the placed ones — so a brand-new org appears, it just appears last
    /// among the unplaced, never hidden.
    public private(set) var ownerOrder: [String]

    public static let `default` = LensPreferences(groupByOwner: false, foldedOwners: [])

    public init(groupByOwner: Bool, foldedOwners: Set<String> = [], ownerOrder: [String] = []) {
        self.groupByOwner = groupByOwner
        self.foldedOwners = Set(foldedOwners.map { $0.lowercased() })
        var seen = Set<String>()
        self.ownerOrder = ownerOrder.map { $0.lowercased() }.filter { seen.insert($0).inserted }
    }

    public func isFolded(_ owner: String) -> Bool { foldedOwners.contains(owner.lowercased()) }
    public func leads(_ owner: String) -> Bool { !isFolded(owner) }
    /// True iff the lens is actually hiding rows' place in the lane — the eye's slash.
    public var foldsAnything: Bool { !foldedOwners.isEmpty }

    public func togglingGroupByOwner() -> LensPreferences {
        LensPreferences(groupByOwner: !groupByOwner, foldedOwners: foldedOwners, ownerOrder: ownerOrder)
    }

    /// Fold ⇄ unfold one owner; the same transition whether it came from the ledger
    /// line, the card, or the gear (three handles, one truth).
    public func togglingFolded(_ owner: String) -> LensPreferences {
        var next = foldedOwners
        let key = owner.lowercased()
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        return LensPreferences(groupByOwner: groupByOwner, foldedOwners: next, ownerOrder: ownerOrder)
    }

    /// Adopt a full drag order from the card (lowercased + deduped by init).
    public func settingOwnerOrder(_ order: [String]) -> LensPreferences {
        LensPreferences(groupByOwner: groupByOwner, foldedOwners: foldedOwners, ownerOrder: order)
    }
}
