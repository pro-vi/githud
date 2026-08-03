import Foundation

/// The owner-lens card's pure descriptor (WP 2026-07-14-001) — mirrors `PillStyleChooser`:
/// Core decides the words and the entry set; the App only inks it. Owners are DISCOVERED,
/// never configured: whoever is present in the lane, in lead-row order, plus any
/// currently-folded owner whose rows aged out (count 0 renders honestly, so an old fold
/// can always be released). No key moment: the card has no editable field.
public struct LensChooser: Equatable, Sendable {
    public struct OwnerEntry: Equatable, Sendable {
        /// Display casing (first-seen in the data; folded-but-absent owners fall back to
        /// their stored lowercase). Identity upstream is always the lowercased login.
        public let owner: String
        /// "yours" for the viewer's own login, else the owner itself.
        public let title: String
        /// Checked = leading; unchecked = folded to a ledger line.
        public let leads: Bool
        /// LIVE rows currently in the lane under this owner (0 = folded remnant, or a
        /// tail-only owner — all still listed).
        public let count: Int
        /// Draft rows under this owner (WP 2026-07-26-001). An owner present ONLY in drafts
        /// is a first-class lens owner — ratified 2026-07-26, "facebook should be there as
        /// an org" — so it must be listed, foldable, and draggable like any other.
        public let draftCount: Int
        /// Quiet (gone-quiet) rows under this owner (WP 2026-07-29-001). Same precedent
        /// extended: an owner whose only rows are 16 weeks old is still an owner here.
        public let quietCount: Int

        public init(owner: String, title: String, leads: Bool, count: Int,
                    draftCount: Int = 0, quietCount: Int = 0) {
            self.owner = owner
            self.title = title
            self.leads = leads
            self.count = count
            self.draftCount = draftCount
            self.quietCount = quietCount
        }
    }

    public let title: String
    public let ownersHeader: String
    public let owners: [OwnerEntry]
    public let groupByOwner: Bool
    public let groupByOwnerLabel: String
    public let groupByOwnerTooltip: String
    /// Like `PillStyleChooser.takesKeyMoment`: no field, never takes key (focus-non-theft).
    public static let takesKeyMoment = false

    /// Build from the CURRENT lane rows + prefs + login — called fresh at every render while
    /// the card is up, so the checks can never disagree with the lane behind it. Takes ALL THREE
    /// regions the lens governs: an owner present only in `drafts` (WP 2026-07-26-001) or only in
    /// `quiet` (WP 2026-07-29-001) is a real owner here, listed after every owner with live work,
    /// exactly as the lane ranks it.
    ///
    /// GATING MIRRORS THE LANE, and asymmetrically on purpose. The caller gates `drafts` on
    /// `showDrafts`, so with drafts hidden a draft-only owner correctly disappears from the card
    /// too — unless it is folded, which the remnant rule below keeps listed so the fold stays
    /// releasable. `quiet` is NEVER gated: `showStale` hides quiet rows behind a caption that
    /// still counts them, so a quiet-only owner exists whether or not you can see its rows.
    public static func make(live: [PulseRow], drafts: [PulseRow], quiet: [PulseRow],
                            prefs: LensPreferences, selfLogin: String?) -> LensChooser {
        // Discovery + partition come from PulsePresenter.ownerBuckets — the ONE home for the
        // "live owners by lead-row rank, then draft-only, then quiet-only" rule. This function
        // used to walk it by hand in parallel dictionaries, so the card and the lane implemented
        // the same ratified ordering twice.
        var order: [String] = []
        var casing: [String: String] = [:]
        var counts: [String: Int] = [:]
        var draftCounts: [String: Int] = [:]
        var quietCounts: [String: Int] = [:]
        for bucket in PulsePresenter.ownerBuckets(live: live, drafts: drafts, quiet: quiet) {
            order.append(bucket.key)
            casing[bucket.key] = bucket.owner
            counts[bucket.key] = bucket.live.count
            draftCounts[bucket.key] = bucket.drafts.count
            quietCounts[bucket.key] = bucket.quiet.count
        }
        // Folded owners with no rows on screen still list (a fold must stay releasable).
        for folded in prefs.foldedOwners.sorted() where counts[folded] == nil {
            order.append(folded)
            casing[folded] = folded
            counts[folded] = 0
        }
        // Same effective order as the lane's groups/ledgers (drag order, then discovery).
        let owners = PulsePresenter.lensOrderedKeys(order, prefs: prefs).compactMap { key -> OwnerEntry? in
            guard let display = casing[key] else { return nil }
            return OwnerEntry(owner: display,
                              title: PulsePresenter.lensTitle(owner: display, selfLogin: selfLogin),
                              leads: prefs.leads(key),
                              count: counts[key] ?? 0,
                              draftCount: draftCounts[key] ?? 0,
                              quietCount: quietCounts[key] ?? 0)
        }
        return LensChooser(title: PlainWords.lensCardTitle,
                           ownersHeader: PlainWords.lensOwnersHeader,
                           owners: owners,
                           groupByOwner: prefs.groupByOwner,
                           groupByOwnerLabel: PlainWords.groupByOwnerItem,
                           groupByOwnerTooltip: PlainWords.groupByOwnerTooltip)
    }
}
