import Foundation

/// What the menu-bar status item should DRAW — the Glyphling g as the bar's constant mark,
/// its EYE doing the states (WP 2026-07-22-001 "the g takes the bar", which retired the
/// D-glyph arcs instrument while keeping its ratified priority/composition spine):
///  - the eye's vocabulary: a dilated pupil probing (loading), a sidelong pupil still
///    looking (clearUnconfirmed), the half-lid down at ease (clear), a locked pupil while
///    the count text counts (action);
///  - degraded COMPOSES over every non-loading state — the dashed arc pair survives as pure
///    freshness chrome FLANKING the mark (g or narrowed shield), so a stale/failing reading
///    is never hidden exactly where trust matters most;
///  - LOADING dims the WHOLE mark to α 0.55 (`loadingAlpha`, the waking register) — a
///    full-strength mark must never show pre-first-poll (the same never-fake-clear rule as
///    the pill's waking face).
///
/// Pure data, no AppKit: the state priority + composition matrix here is TRUST logic — the
/// bar must never claim a state the data can't back — so it lives in Core and is tested like
/// `PillAccessibilityPresenter`. `StatusItemController` translates a descriptor into the
/// actual 18×18pt template image + button-title count.
///
/// SCOPE (ratified record-wide, D-glyph rule 3): the glyph answers **H1 only** ("does GitHub
/// need me?") — it never grows an H2 gauge, so a hidden island shows no PR-pulse signal on
/// the bar. That call was made consciously in the designer session, not by omission. The
/// pulse still reaches the TOOLTIP via `PillAccessibilityPresenter` (spoken, not drawn) —
/// see `StatusGlyphPresenter.toolTip`.
public enum StatusGlyphDescriptor: Equatable, Sendable {
    /// The g AT EASE — half-lid down, pupil resting low: "nothing needs you". No count
    /// text. CONFIRMED read only — the earned clear cue.
    case clear(degraded: Bool)
    /// Clear-LOOKING but not confirmed read (ratified A2, 2026-07-21): the earned clear
    /// cue may not show until all three lanes confirmed a read this session. A distinct
    /// STATE with its final form (WP 2026-07-22-001): the g STILL LOOKING — a sidelong
    /// pupil at full alpha, form-distinct from at-ease, never alpha-distinct.
    case clearUnconfirmed(degraded: Bool)
    /// The g with a LOCKED pupil; the count rides beside the mark as adjacent REAL text
    /// (the only 1x-guaranteed-legible count treatment — never sub-5px knockout digits).
    case action(countText: String, degraded: Bool)
    /// The whole mark yields to a filled shield with a knocked-out '!' — identity yields
    /// ONLY for the one categorical emergency (security_alert), exactly the classifier's
    /// own hierarchy (critical-first sort). The count text stays.
    case critical(countText: String, degraded: Bool)
    /// Pre-first-poll: the WHOLE g dimmed to α 0.55 (`loadingAlpha`) with a dilated,
    /// probing pupil. The at-ease half-lid is the CLEAR cue, so it may not appear before
    /// the first poll can back it — the dimmed probing eye promises nothing.
    /// `degraded` never composes here BY RATIFIED SPEC (D-glyph state 4 composes over states
    /// 1–3 only). NOTE the reachable edge this scoping accepts: `.failing` CAN fire with a
    /// nil lastSuccess (2+ failed polls before any success), in which case the drawn mark
    /// stays the plain dim probing g while the tooltip honestly speaks "Reading may be
    /// stale" — the mark under-reports relative to its own tooltip. Deliberate, not an
    /// oversight.
    case loading

    /// The transition class — crossfades are decided on THIS, never on payload changes
    /// (count text / degraded-dash toggles are 0ms hard swaps; see `crossfades(from:to:)`).
    public enum MarkClass: Equatable, Sendable { case clear, action, critical, loading }

    public var markClass: MarkClass {
        switch self {
        case .clear, .clearUnconfirmed: return .clear   // same transition class — the
                                                        // confirm flip is a 0ms hard swap
        case .action: return .action
        case .critical: return .critical
        case .loading: return .loading
        }
    }

    /// True when the arcs render dashed (degraded reading — freshness chrome, the ONE
    /// sanctioned `caution` meaning carried by shape, not hue). Always false for `.loading`.
    public var isDegraded: Bool {
        switch self {
        case .clear(let degraded), .clearUnconfirmed(let degraded),
             .action(_, let degraded), .critical(_, let degraded):
            return degraded
        case .loading:
            return false
        }
    }

    /// The button-title count ("1"…"99", then "99+") — nil when clear/loading (no title).
    public var countText: String? {
        switch self {
        case .action(let text, _), .critical(let text, _): return text
        case .clear, .clearUnconfirmed, .loading: return nil
        }
    }
}

/// (rows, pulse, freshness, loading) → `StatusGlyphDescriptor` + the item's tooltip.
/// Same inputs as `PillAccessibilityPresenter.value` (the two surfaces may never disagree
/// about what the data says), same priority spine as the pill:
///   loading → critical → action → clear, with degraded composing over everything EXCEPT
///   loading. `pulse` is accepted for signature symmetry but deliberately UNUSED by the
///   mark — the glyph is H1-only by ratified scope (see the type doc above).
public enum StatusGlyphPresenter {
    /// The loading mark's whole-image alpha — the waking register (WP 2026-07-22-001, "the g
    /// takes the bar"): the g at α0.55 dims identity pre-first-poll, echoing the pill's
    /// inkTertiary waking face and carrying the tentative cue the retired α0.40 arcs held.
    /// One shared home so the drawn value can't drift; SPEC DECISION, amendable one-line.
    public static let loadingAlpha: Double = 0.55

    public static func descriptor(rows: [RadarRow], pulse: [PulseRow] = [],
                                  freshness: Freshness = .fresh,
                                  loading: Bool = false,
                                  clearConfirmed: Bool = false) -> StatusGlyphDescriptor {
        _ = pulse   // H1-only scope (ratified): the mark never reads the H2 lane.
        if loading { return .loading }                       // outranks all — no reading exists yet
        let degraded = freshness.isDegraded
        if rows.contains(where: { $0.isCritical }) {
            return .critical(countText: countText(rows.count), degraded: degraded)
        }
        if !rows.isEmpty {
            return .action(countText: countText(rows.count), degraded: degraded)
        }
        // The clear cue is a CLAIM — it rides the same three-lane confirmation gate as
        // the island's affirmation (fail-closed default, the reviews precedent).
        return clearConfirmed ? .clear(degraded: degraded)
                              : .clearUnconfirmed(degraded: degraded)
    }

    /// Exact 1–99, "99+" beyond — the menu bar is the one surface where an unbounded count
    /// could push neighbors around, so it caps; the island itself never truncates.
    public static func countText(_ count: Int) -> String {
        count > 99 ? "99+" : String(count)
    }

    /// Whether a descriptor change earns the one-shot 180ms opacity crossfade. BINDING
    /// (review overall_note): the crossfade is reserved for clear↔action↔critical CLASS
    /// changes; count-text changes and degraded-dash toggles are 0ms hard swaps (freshness
    /// degradation must never be celebrated with motion — `attention-non-theft`), and
    /// loading in/out is also a hard swap (motion is spent ONLY on the three named classes).
    public static func crossfades(from old: StatusGlyphDescriptor, to new: StatusGlyphDescriptor) -> Bool {
        guard old.markClass != new.markClass else { return false }
        if old.markClass == .loading || new.markClass == .loading { return false }
        return true
    }

    /// The status item's tooltip — copy verbatim from the ratified spec: the SAME spoken
    /// value the collapsed pill carries (`PillAccessibilityPresenter`), so the bar, the
    /// pill, and VoiceOver can never tell three different stories. Note the pulse DOES
    /// flow in here: the H2 gauge is withheld from the drawn mark (H1-only scope) but not
    /// from speech/hover — count context honored off-glass.
    public static func toolTip(rows: [RadarRow], pulse: [PulseRow] = [],
                               freshness: Freshness = .fresh, loading: Bool = false,
                               clearConfirmed: Bool = false) -> String {
        toolTip(value: PillAccessibilityPresenter.value(rows: rows, pulse: pulse,
                                                        freshness: freshness, loading: loading,
                                                        clearConfirmed: clearConfirmed))
    }

    /// Formatting half, split out so a caller that already computed the spoken value (for
    /// `accessibilityDescription`) doesn't compute it twice.
    ///
    /// D-copy fix (WP-3d′): the LOADING value now carries the wordmark itself
    /// ("githud — checking GitHub"), so re-prefixing it here produced the old
    /// "githud — githud, loading" double wordmark. A value that already leads with the
    /// wordmark is used verbatim. Known composed edge (pinned in tests): a degraded
    /// loading reading ("Reading may be stale. githud — checking GitHub") is prefixed —
    /// the wordmark then appears mid-sentence once; both facts + identity stay spoken.
    public static func toolTip(value: String) -> String {
        let head = value.hasPrefix("githud") ? value : "githud — \(value)"
        return "\(head). Click to expand, right-click for menu."
    }
}
