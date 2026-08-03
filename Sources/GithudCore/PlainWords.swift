import Foundation

/// WP 2026-07-12-001 — the island's plain-words copy (flavor C, ratified 2026-07-12
/// "yeah i like C"). The dogfood tell was syntax, not facts: interpunct-glued fragments
/// ("3 stale · untouched 14d+") and jargon ("14d+", "bots/drafts") read machine-made. C
/// answers in the earlier-web register — a count and a parenthesized verb, nothing else.
///
/// This is the ONE home for those strings (the `CaughtUpPresenter` precedent: Core decides
/// the words, the App layer only inks them), so the count interpolation is CLT-pinned and
/// the caption, its revealed header, and the gear item that flips the SAME preference can
/// never drift apart. The parenthesized verb is baked into the caption string on purpose —
/// it IS the line's affordance (the whole caption is the click target); the App underlines
/// just that token where a styled-substring precedent already exists.
public enum PlainWords {
    // MARK: Pulse "gone quiet" (stale) subsection — untouched-14d+ PRs, default-off.

    /// "3 gone quiet" — THE one home for the quiet noun phrase, sibling of `draftsNoun`. No
    /// plural inflection: the phrase is adjectival, so "1 gone quiet" is already right. Five
    /// surfaces say it now (the collapsed caption, its spoken twin, a group's revealed tail
    /// label, a folded ledger line and the Owners card row) and WP 2026-07-29-001 added three of
    /// them at once — exactly the moment a repeated string literal becomes a rule with no home.
    static func quietNoun(_ n: Int) -> String { "\(n) gone quiet" }

    /// The collapsed stand-in, e.g. "3 gone quiet (show)". The 14-day threshold left the
    /// glass for the gear tooltip (`staleGearTooltip`) — a deliberate demotion, not a loss.
    ///
    /// SCOPED PER GROUP by WP 2026-07-29-001, not restyled: in grouped shape each owner's quiet
    /// tail collapses to this same caption under its own title. That reuse is the point — the
    /// ratified string is the affordance, and quiet's whole grammar is that it leaves a count
    /// behind, which is why `showStale` gates rendering rather than the lens's input.
    public static func staleCaption(_ count: Int) -> String { quietNoun(count) + " " + showVerb }
    /// VoiceOver form — a button spoken with the verb as a word, not a glyph-parens.
    public static func staleCaptionSpoken(_ count: Int) -> String { quietNoun(count) + ", show" }
    /// The header the revealed section gains (was the bare "Stale"); paired with `hide`.
    public static let staleHeader = "Gone quiet"
    /// A group's quiet tail once REVEALED — the collapsed caption with one token changed:
    /// "2 gone quiet (hide)". Same noun, same shape, same click target; only the verb flips, so
    /// the two states read as one object rather than two.
    ///
    /// This closes gap G1 (`docs/TOPOLOGY.md`). Grouped shape gained a per-group `(show)` and no
    /// per-group way back, because the lane-level "Gone quiet" header — which carries the only
    /// other `(hide)` in the app — renders in the FLAT shape only. The way in was on the glass
    /// and the way out was in the gear.
    ///
    /// Deliberately NOT the lane header's right-edge `HideControlView`: every `(hide)` in the app
    /// is bound to a revealed SECTION HEADER, one-to-one, and a group tail is not a section. The
    /// caption family — count + parenthesised verb — is the ratified grammar at this scope, so
    /// the verb token is the form that adds no new pattern.
    public static func staleRevealedCaption(_ count: Int) -> String {
        quietNoun(count) + " " + hideControl
    }
    /// VoiceOver twin — a button spoken with the verb as a word, mirroring `staleCaptionSpoken`.
    public static func staleRevealedCaptionSpoken(_ count: Int) -> String {
        quietNoun(count) + ", " + hideSpoken
    }

    // MARK: Inbound "bots & drafts" (held-back) subsection — bot/draft arrivals, default-off.

    /// The collapsed stand-in, e.g. "2 from bots & drafts (show)".
    public static func heldBackCaption(_ count: Int) -> String { "\(count) from bots & drafts (show)" }
    /// VoiceOver form.
    public static func heldBackCaptionSpoken(_ count: Int) -> String { "\(count) from bots & drafts, show" }
    /// The header the revealed rows gain (today they render headerless); paired with `hide`.
    public static let heldBackHeader = "Bots & drafts"

    // MARK: Pulse "draft PRs" subsection — WIP PRs (isDraft), default-off.

    /// The revealed header (was the bare "Drafts"); paired with `hide`. NOTE the preserved
    /// asymmetry: drafts have NO collapsed caption — hidden drafts stay fully invisible
    /// (deliberate doctrine, unlike stale/held-back which leave a count behind). This string
    /// is the revealed header only; there is intentionally no `draftsCaption`.
    public static let draftsHeader = "Draft PRs"
    /// A group's draft-tail label in GROUPED shape (WP 2026-07-26-001): the owner title above
    /// already named the org, so the tail only has to say what it is and how much — "5 drafts".
    /// Lowercase and countful, deliberately quieter than `draftsHeader`, which stays the FLAT
    /// shape's revealed header (a flat list has no groups to tail). Same no-caption asymmetry:
    /// this label carries no verb, because hidden drafts stay fully invisible.
    public static func draftTailLabel(_ count: Int) -> String { draftsNoun(count) }

    /// "5 drafts" / "1 draft" — THE one home for the drafts noun phrase. Eight call sites across
    /// the ledger lines, the tail label and the card row spelled this conditional out by hand,
    /// under comments claiming the plural rule was single-homed.
    static func draftsNoun(_ n: Int) -> String { "\(n) draft\(n == 1 ? "" : "s")" }

    // MARK: Radar "just cleared" subsection — the departure receipt (plan 2026-07-21-001,
    // caption B1 ratified). Same family: count + parenthesized verb, revealed header + hide.

    /// The collapsed stand-in, e.g. "2 just cleared (show)".
    public static func justClearedCaption(_ count: Int) -> String { "\(count) just cleared (show)" }
    /// VoiceOver form.
    public static func justClearedCaptionSpoken(_ count: Int) -> String { "\(count) just cleared, show" }
    /// The revealed header; paired with `hide`.
    public static let justClearedHeader = "Just cleared"

    /// A cleared row's reason suffix — present ONLY when the reading actually knew why
    /// (the reason-honesty rule: a plain feed departure renders no suffix, never a guess).
    public static func clearedWhyText(_ why: ClearedWhy) -> String {
        switch why {
        case .read:            return "read ✓"
        case .reviewSubmitted: return "review submitted ✓"
        case .merged:          return "merged"
        case .closed:          return "closed"
        }
    }

    /// Gear/settings title for the receipts band (land-triage F5 — the plan says
    /// gear-owned; the caption and this row flip the SAME preference).
    public static let justClearedGearItem = "Show just cleared"
    public static let justClearedGearTooltip = "Recent departures from Needs you, with reasons where known"

    // MARK: The affordance verbs — the caption's trailing token + the header's fold-back.

    /// The caption's link token (underlined where a substring precedent exists). Kept as a
    /// constant so the App can locate the range without re-hardcoding it.
    public static let showVerb = "(show)"
    /// A revealed header's right-edge control — flips the same preference back off.
    public static let hideControl = "(hide)"
    /// VoiceOver form of the hide control.
    public static let hideSpoken = "hide"

    // MARK: Gear items — the OTHER handle on the same two preferences (one truth).

    /// Gear title (was "Show stale PRs (untouched 14d+)"); the threshold moves to the tooltip.
    public static let staleGearItem = "Show PRs gone quiet"
    public static let staleGearTooltip = "untouched for 14 days or more"
    /// Gear title (was "Show held-back inbound (bots/drafts)"); the tooltip names what's held.
    public static let heldBackGearItem = "Show bots & drafts"
    public static let heldBackGearTooltip = "Bot and draft arrivals held back from the queue"
    /// Gear title (title unchanged — just moved to the one string home); the tooltip names
    /// what's held, matching its two siblings.
    public static let draftsGearItem = "Show draft PRs"
    public static let draftsGearTooltip = "Your works-in-progress, kept out of the glance"

    // MARK: Owner lens (WP 2026-07-14-001) — folded ledger lines, the eye, and its card.

    /// The TAIL NOUNS a folded ledger line carries, in ratified clause order — drafts then quiet
    /// (WP 2026-07-26-001, extended by 2026-07-29-001). A fold hides an owner's tails along with
    /// its live rows, so the line must admit them — otherwise "acme · 4" claims to hide four
    /// things while hiding nine. Each is dropped at zero, so every earlier line stays
    /// byte-identical, and the common case is still the bare "yours · 2".
    ///
    /// One list, not two clause-builders: every consumer (visible line, both spoken forms, the
    /// card row) needs the same nouns in the same order and differs only in how it joins them.
    static func tailNouns(draftCount: Int, quietCount: Int) -> [String] {
        var nouns: [String] = []
        if draftCount > 0 { nouns.append(draftsNoun(draftCount)) }
        if quietCount > 0 { nouns.append(quietNoun(quietCount)) }
        return nouns
    }

    /// A folded owner's ledger line, e.g. "acme · 3, 2 drafts, 2 gone quiet, 1 new" /
    /// "yours · 2". The live count always prints (fold, not filter); the tail and fresh clauses
    /// appear only when non-zero — never ", 0 new" or ", 0 drafts". An owner with NO live rows
    /// has no live count worth printing, so its tail nouns carry the line — "facebook · 1 draft",
    /// "helios-oss · 3 gone quiet" — rather than the nonsense "· 0, 1 draft". NOTE: no verb
    /// token — ratified round 5 removed "(show)"; the whole line is the click target and the
    /// eye/card carry the vocabulary now.
    public static func lensLedger(_ title: String, count: Int, draftCount: Int = 0,
                                  quietCount: Int = 0, fresh: Int = 0) -> String {
        let freshClause = fresh > 0 ? ", \(fresh) new" : ""
        let tails = tailNouns(draftCount: draftCount, quietCount: quietCount)
        // Zero live: the first tail noun becomes the line's own count, and the rest follow it.
        // (Zero live AND zero tails is the honest "ghost · 0" — unreachable from `lensLayout`,
        // which only builds buckets for owners that have rows, but a total function all the same.)
        let head = count == 0 && !tails.isEmpty ? tails[0] : "\(count)"
        let rest = count == 0 && !tails.isEmpty ? tails.dropFirst() : tails.dropFirst(0)
        return "\(title) · \(head)" + rest.map { ", \($0)" }.joined() + freshClause
    }
    /// The Owners-card row's spoken form. Its visible twin is `lensLedger` (same numbers, same
    /// plural rule — one home), but the row is a CHECKBOX whose value carries shown/hidden, so
    /// it must not end in the ledger's "folded … open" verb: VoiceOver would announce an action
    /// the row does not perform.
    public static func lensCardRowSpoken(_ title: String, count: Int, draftCount: Int = 0,
                                         quietCount: Int = 0) -> String {
        var parts = [title]
        if count > 0 { parts.append("\(count)") }
        parts += tailNouns(draftCount: draftCount, quietCount: quietCount)
        return parts.joined(separator: ", ")
    }

    /// VoiceOver form — spoken as a button whose action opens the group. Its "elsewhere" twin
    /// differs in exactly one token (the verb names which surface the click opens), so both
    /// delegate here rather than each carrying its own copy of the zero-live branch.
    public static func lensLedgerSpoken(_ title: String, count: Int, draftCount: Int = 0,
                                        quietCount: Int = 0, fresh: Int = 0) -> String {
        spokenLedger(title, count: count, draftCount: draftCount, quietCount: quietCount,
                     fresh: fresh, verb: "open")
    }
    private static func spokenLedger(_ title: String, count: Int, draftCount: Int,
                                     quietCount: Int, fresh: Int, verb: String) -> String {
        let freshClause = fresh > 0 ? ", \(fresh) new" : ""
        let tails = tailNouns(draftCount: draftCount, quietCount: quietCount)
        // Spoken joins with "and" where the visible line uses commas — a screen reader reading
        // "3, 2 drafts, 2 gone quiet" hears a list of unrelated numbers.
        if count == 0 && !tails.isEmpty {
            return "\(title), \(tails.joined(separator: " and ")) folded\(freshClause), \(verb)"
        }
        let tail = tails.map { " and \($0)" }.joined()
        return "\(title), \(count) folded\(tail)\(freshClause), \(verb)"
    }
    /// The merged line when more than two owners fold (the tail safety valve). Its click
    /// opens the lens card — one owner can't be inferred from a merged line.
    public static func lensElsewhereLedger(count: Int, draftCount: Int = 0, quietCount: Int = 0,
                                           fresh: Int = 0) -> String {
        lensLedger(lensElsewhereTitle, count: count, draftCount: draftCount,
                   quietCount: quietCount, fresh: fresh)
    }
    public static func lensElsewhereLedgerSpoken(count: Int, draftCount: Int = 0,
                                                 quietCount: Int = 0, fresh: Int = 0) -> String {
        spokenLedger(lensElsewhereTitle, count: count, draftCount: draftCount,
                     quietCount: quietCount, fresh: fresh, verb: "open lens")
    }
    /// Group titles: the viewer's own repos read as a word, not a login.
    public static let yoursTitle = "yours"
    public static let lensElsewhereTitle = "elsewhere"

    // The lens's other handles — gear submenu, the card, and the eye (one truth).
    // (Dogfood 2026-07-14: the card caption was cut — the card explains itself — and
    // "Lead with:" became "Owners:" when rows gained drag-order + show/hide eyes.)
    public static let lensGearItem = "Lens…"
    public static let lensOwnersHeader = "Owners:"
    public static let groupByOwnerItem = "Group by owner"
    public static let groupByOwnerTooltip = "off keeps the one list, as before"
    public static let lensCardTitle = "Lens"
    /// The card's way back to the island (click-away still means "leave entirely").
    public static let lensBackControl = "(back)"
    public static let lensBackSpoken = "back"
    /// The eye's tooltip / a11y label; state-bearing so VoiceOver hears what's folded.
    public static func lensEyeLabel(foldedCount: Int) -> String {
        foldedCount > 0 ? "Lens — \(foldedCount) folded" : "Lens"
    }

    // MARK: Settings card (mark-and-settings seed 2026-07-12-002, option B — ratified in
    // dogfood 2026-07-14: "why can't the setting be like that too"). The gear opens ONE
    // in-island card; the system menu shrinks to verbs (Settings… / Hide / Quit).

    public static let settingsCardTitle = "Settings"
    public static let settingsGearTooltip = "Settings"
    public static let settingsMenuItem = "Settings…"
    public static let settingsThemeHeader = "Theme:"
    public static let settingsSurfaceHeader = "Surface which reasons:"
    public static let settingsPRHeader = "Your PRs:"
    public static let settingsInboundHeader = "Inbound:"
    public static let launchAtLoginItem = "Launch at Login"
    /// Doors into the sibling cards (the card swaps — the ordinary card lifecycle).
    public static let pillStyleDoor = "Pill style…"
    public static let lensDoor = "Lens…"
}
