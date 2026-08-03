import CoreGraphics
import Foundation

/// WP-3d′ — the chevron inline peek's pure brain (D-reveal `chevron-inline-peek` with its
/// BLOCKING amendments, ratified 2026-07-06). Three decisions live here so they are
/// headlessly tested and the view layer just executes them:
///
/// 1. **The truncation predicate (amendment 3).** A row grows a chevron iff its title OR
///    subtitle OR excerpt truncates (measured). The subtitle is deliberately in the OR —
///    the review caught that a title-or-excerpt predicate would HIDE a subtitle-only
///    truncation, cutting against never-miss.
///
/// 2. **The hitTest carve-out (amendment 1).** `IslandClickableView.hitTest` flattens each
///    row to ONE target (so child labels never swallow first-mouse clicks on the non-key
///    panel) — which means a naive chevron child could never receive its own click and the
///    failure direction is the worst one: a peek attempt that NAVIGATES. The carve-out
///    decision is this pure function; the row's `hitTest` override delegates to it, and the
///    "a chevron click never resolves to the row" proof is a Core test.
///
/// 3. **The peek line caps** (ratified): title ≤3 lines, subtitle ≤2, excerpt ≤4.
public enum PeekReveal {
    /// Ratified un-truncation caps (D-reveal spec verbatim).
    public static let titleLineCap = 3
    public static let subtitleLineCap = 2
    public static let excerptLineCap = 4

    /// Amendment 3: the chevron renders iff ANY of the three texts truncates. Rows with
    /// nothing hidden get no chevron (truncated-only rule — never fake chrome).
    /// A row without an excerpt passes `excerptFits: true` (nothing to hide there).
    public static func needsChevron(titleFits: Bool, subtitleFits: Bool, excerptFits: Bool) -> Bool {
        !(titleFits && subtitleFits && excerptFits)
    }

    /// Who owns a click at `point` (row-local coordinates).
    public enum HitTarget: Equatable, Sendable {
        case chevron   // the peek toggle — NEVER a navigation
        case row       // Open-on-GitHub, byte-for-byte today's behavior
        case none      // outside the row
    }

    /// The carve-out: a point inside the chevron's frame resolves to the chevron and
    /// nothing else; everywhere else in the row stays the flattened one-target row.
    /// `chevronFrame == nil` (no chevron on this row) → the whole row is the target.
    public static func hitTarget(point: CGPoint, rowBounds: CGRect, chevronFrame: CGRect?) -> HitTarget {
        guard rowBounds.contains(point) else { return .none }
        if let chevronFrame, chevronFrame.contains(point) { return .chevron }
        return .row
    }
}

/// The peek stash — which rows are un-truncated, carried ACROSS data rebuilds within one
/// expanded session (the render path tears down and rebuilds the whole island on every
/// poll change; only stashed state survives — exactly the `ScrollOffsets` contract).
///
/// Keyed on the row's STABLE id (thread id / repo#number — amendment 2: never the
/// optional/collidable url), and each entry remembers the row's change signature at peek
/// time: a rebuilt row is restored open ONLY if its signature still matches. A changed
/// signature means the content is new — the peek drops and the row re-truncates honestly.
///
/// Reset-on-collapse is the CALLER's job (the controller simply doesn't carry the stash
/// across a collapsed render), so a fresh expand always opens clean.
public struct PeekStash: Equatable, Sendable {
    /// Open peeks: row id → the row's change signature when the peek was opened.
    private var open: [String: String] = [:]

    public init() {}

    public var isEmpty: Bool { open.isEmpty }

    /// Record a toggle. Closing removes the entry (a closed row carries no state).
    public mutating func setOpen(_ isOpen: Bool, id: String, signature: String) {
        open[id] = isOpen ? signature : nil
    }

    /// Should this (re)built row render peeked? True only for a stashed id whose
    /// signature is unchanged — the drop-on-changed-signature rule is structural here.
    public func isOpen(id: String, signature: String) -> Bool {
        open[id] == signature
    }
}
