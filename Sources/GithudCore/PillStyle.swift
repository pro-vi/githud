import Foundation

/// The collapsed pill's caught-up VOCABULARY — the config the D-pill session ratified
/// (2026-07-10-001) in place of a single winner: "allow config with actual visual preview
/// therefore we may provide a default but user can switch it up." All three agree on the
/// acute region (loading / radar / critical are identical everywhere); they differ ONLY in
/// how a standing inbound queue composes with the living gauge when the inbox is clear.
///
/// Stored raw via UserDefaults (the existing preferences pattern); an absent key → the
/// default. Threaded in LOCKSTEP through `PillMorph.fingerprint` / `PillMorph.width` /
/// `PillAccessibilityPresenter.value` — the F5 style-matrix test pins all three per
/// (style × state) so the three functions cannot drift.
public enum PillStyle: String, CaseIterable, Sendable, Equatable {
    /// DEFAULT — the ladder as amended: loading > radar > INBOUND > gauge > check. A
    /// standing queue is EXCLUSIVE (it walls off the gauge — the utility cost the user
    /// objected to, answered BY the config, not dismissed). The user's stated aesthetic
    /// lean: ink, pinned width, chronic color retired.
    case queueLeads
    /// Hybrid, MARKED: the standing tier composes gauge + a dim, count-free tray mark
    /// (someone is at the door, by presence not number). The mark's absence means only
    /// "no one at the door by count" — never confirmed-empty (the island keeps that gate).
    case standingMarked
    /// Hybrid, COUNTED: the standing tier composes gauge + a glyph+count queue segment
    /// riding the gauge's own atoms.
    case standingCounted
}

/// The pill-style chooser card's content (WP 2026-07-10-001 §4) — pure copy + the option
/// list, so the card's text and its option→style mapping are headlessly tested; the AppKit
/// `PillStyleChooserView` renders this and feeds each row a LIVE `CollapsedPillView`
/// preview of its style, fed the user's CURRENT data with radar suppressed.
public struct PillStyleChooser: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public let style: PillStyle
        public let label: String
        public init(style: PillStyle, label: String) {
            self.style = style
            self.label = label
        }
    }

    public let title: String
    /// The plain caption under the previews — names WHY the previews show the caught-up
    /// state (radar is identical across styles) and that the data is real, not a specimen.
    public let caption: String
    /// Shown ONLY when the door is CONFIRMED empty (a complete sweep has read it): the three
    /// previews legitimately coincide, so the card SAYS so rather than fabricating a queue.
    public let coincideNote: String
    /// The count-0-but-UNCONFIRMED sibling (fix round M-3): before the first complete sweep
    /// the door merely hasn't been read — "empty" would be the same fabricated confirmation
    /// the island's `inboundConfirmed` gate bans. This line claims only the coincidence
    /// (which is true at count 0 regardless), never the emptiness.
    public let unconfirmedNote: String
    public let options: [Option]

    public init(title: String, caption: String, coincideNote: String, unconfirmedNote: String,
                options: [Option]) {
        self.title = title
        self.caption = caption
        self.coincideNote = coincideNote
        self.unconfirmedNote = unconfirmedNote
        self.options = options
    }

    /// A chooser card has NO editable field, so it can never take a key moment — the
    /// controller reads THIS to keep `keySessionActive` false in the chooser render branch
    /// (focus-non-theft: panel-content changes owe non-interruption proof; headlessly pinned).
    public var takesKeyMoment: Bool { false }

    /// D-copy plainspoken (the panel may refine the wording without touching the mapping).
    public static let standard = PillStyleChooser(
        title: "Pill style",
        caption: "when nothing acute needs you — previews use your live data",
        coincideNote: "your door is empty right now, so the styles look the same",
        unconfirmedNote: "your door hasn't been checked yet, so the styles look the same for now",
        options: [
            Option(style: .queueLeads,      label: "Door first"),
            Option(style: .standingMarked,  label: "Side by side — quiet mark"),
            Option(style: .standingCounted, label: "Side by side — with the count"),
        ])
}
