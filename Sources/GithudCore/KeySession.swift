import Foundation

/// WP-6k — the ⌃⌥G scoped key session's pure brain (⛔ G-keyboard, ratified variant
/// `slot-morph-inkfocus`, keyboard half — designer session 2026-07-06). Three decisions
/// live here so they are headlessly tested and the panel/view layers just execute them:
///
/// 1. **The flattened actionable list.** Radar rows in order, then the pulse rows the
///    island actually renders — the live/active group always, the Stale and Drafts groups
///    only when the user opted them in (the same `PulsePresenter.sections(for:)` regroup
///    the view consumes, so the selection can never land on a row that isn't on screen).
///    Section headers, captions and the stale-count line are STRUCTURE, not rows — they
///    are skipped by construction because only real rows contribute ids.
///
/// 2. **The selection** (`KeySelection`). Initial selection = the first actionable row;
///    ↑/↓ move by one, clamped at both ends, NO wrap; the selection survives a
///    data-driven rebuild keyed on the STABLE row id (`RadarRow.id` / `PulseRow.id` — the
///    peek stash's own identity rule), and a rebuild that drops the selected row clamps
///    to the nearest index instead of resetting to the top.
///
/// 3. **The key map.** Which keyCodes the session consumes — ↑126 · ↓125 · ⏎36 · esc53 ·
///    space49 (Space = the D-reveal chevron peek's ratified keyboard mapping). Everything
///    else is `.passthrough`: it falls through to the existing behavior (the ⌘-edit
///    routing stays card-scoped; letters reach nothing — honestly, because the panel IS
///    key during the session).
public enum KeySession {
    /// The flattened actionable row ids, in on-screen order: radar (already
    /// urgency-sorted upstream), then pulse `active`, then `stale`/`drafts` only when
    /// rendered. A collapsed stale group's caption line ("N gone quiet (show)") — and its
    /// revealed header's (hide) control — contribute nothing; they are not actionable rows.
    public static func actionableIDs(radar: [RadarRow], pulse: [PulseRow],
                                     showDrafts: Bool, showStale: Bool,
                                     inbound: [InboundRow] = [], showHeldBackInbound: Bool = false,
                                     lens: LensPreferences = .default) -> [String] {
        let sections = PulsePresenter.sections(for: pulse)
        let inboundSections = InboundPresenter.sections(for: inbound)
        var ids = radar.map(\.id)
        // On-screen order: Needs you -> Inbound (the standing queue) -> Your PRs.
        ids += inboundSections.active.map(\.id)
        if showHeldBackInbound { ids += inboundSections.heldBack.map(\.id) }
        // The lane walks the owner-lens layout (WP 2026-07-14-001): a folded owner's rows are
        // NOT on screen — their ledger line is structure, not a row — so they contribute
        // nothing (the selection must never land on an invisible row). The default lens is
        // the identity (one flat run), so pre-lens callers are unchanged.
        //
        // WP 2026-07-26-001 / 2026-07-29-001: the lens lays out all three regions, so a group's
        // tails walk right after its live rows — the walk order IS the render order, which is the
        // whole contract here. `showDrafts` gates the lens's INPUT at this edge exactly as the
        // view does; `showStale` gates further down, at the point of walking, because quiet rows
        // must still reach the lens to be counted on a folded owner's ledger line.
        let regions = sections.lensRegions(showDrafts: showDrafts)
        let layout = PulsePresenter.lensLayout(live: regions.live, drafts: regions.drafts,
                                               quiet: sections.stale, prefs: lens, selfLogin: nil,
                                               lastOpened: [:])
        for entry in layout.entries {
            switch entry {
            case .rows(let rows): ids += rows.map(\.id)
            case .group(_, _, let rows, let drafts, let quiet):
                // A COLLAPSED quiet tail contributes NOTHING: its caption is structure, not a
                // row — the same rule that keeps a ledger line out of the walk.
                ids += rows.map(\.id) + drafts.map(\.id) + (showStale ? quiet.map(\.id) : [])
            case .ledger: break
            }
        }
        // Flat shape keeps its tails terminal; grouped shape already walked them. Both sets come
        // from `LensLayout`, so the walk cannot compute one shape rule while the view computes
        // another — that drift was a real finding on the previous WP and this is its structural
        // fix. DRAFTS BEFORE QUIET, matching the ratified group order (before V3 the lane put
        // stale above drafts, inherited from region order rather than chosen).
        //
        // The quiet ids are now FOLD-FILTERED, where the pre-V3 code appended `sections.stale`
        // whole: a folded owner's rotting rows were keyboard-reachable while off-screen, which is
        // the reported dogfood defect's keyboard half.
        ids += layout.terminalDrafts.map(\.id)
        if showStale { ids += layout.terminalQuiet.map(\.id) }
        return ids
    }

    /// What one session keyDown means. `.passthrough` = not ours; the caller falls
    /// through to the existing responder behavior.
    public enum Intent: Equatable, Sendable {
        case moveUp        // 126 — selection −1, clamped at 0
        case moveDown      // 125 — selection +1, clamped at last
        case open          // 36  — open the selected row (Open-on-GitHub ceiling), end + collapse
        case dismiss       // 53  — end session + collapse
        case peek          // 49  — toggle the focused row's chevron peek (no-op without one)
        case passthrough   // everything else
    }

    /// The ratified key map (spec: ↑/↓/⏎/esc + D-reveal's Space-toggles-peek). Keypad
    /// Enter (76) is deliberately NOT mapped — the spec names keyCode 36 only.
    public static func intent(forKeyCode code: UInt16) -> Intent {
        switch code {
        case 126: return .moveUp
        case 125: return .moveDown
        case 36:  return .open
        case 53:  return .dismiss
        case 49:  return .peek
        default:  return .passthrough
        }
    }
}

/// The live selection over the flattened actionable list. Pure value type — the
/// controller owns one while (and only while) a ⌃⌥G session is live; the view just
/// paints the ink bar on `selectedID`.
public struct KeySelection: Equatable, Sendable {
    /// The flattened actionable row ids, on-screen order (see `KeySession.actionableIDs`).
    public private(set) var ids: [String]
    /// The selected position. Meaningful only while `ids` is non-empty (an empty island's
    /// session still exists — esc must still dismiss — it just has nothing to select).
    public private(set) var index: Int

    /// Initial selection = the first actionable row (index 0), per the ratified spec.
    public init(ids: [String]) {
        self.ids = ids
        self.index = 0
    }

    /// The stable id the bar sits on — nil when there is nothing actionable to select.
    public var selectedID: String? { ids.indices.contains(index) ? ids[index] : nil }
    public var isEmpty: Bool { ids.isEmpty }

    /// ↓ — +1, clamped at the last row. NO wrap (the ratified spec is explicit).
    public mutating func moveDown() {
        guard !ids.isEmpty else { return }
        index = min(index + 1, ids.count - 1)
    }

    /// ↑ — −1, clamped at the first row. NO wrap.
    public mutating func moveUp() {
        guard !ids.isEmpty else { return }
        index = max(index - 1, 0)
    }

    /// Survive a data-driven rebuild: follow the selected row's STABLE id to its new
    /// position; a rebuild that drops the selected row clamps the old index to the
    /// nearest valid one (never a reset to the top mid-session, never out of bounds).
    public mutating func rebuild(ids newIDs: [String]) {
        let previousID = selectedID
        let previousIndex = index
        ids = newIDs
        if let previousID, let found = newIDs.firstIndex(of: previousID) {
            index = found
        } else {
            index = newIDs.isEmpty ? 0 : min(max(previousIndex, 0), newIDs.count - 1)
        }
    }
}
