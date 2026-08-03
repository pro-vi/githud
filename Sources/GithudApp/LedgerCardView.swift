import AppKit
import GithudCore

/// WP-4d — the handshake-ledger card (ratified D-card `handshake-ledger`), replacing the
/// orange-triangle MessageView for every no-token/auth state. 420pt wide: header (key
/// glyph + "Connect GitHub"), the one-line read-only promise, THREE ledger rows
/// (Token / Keychain / GitHub) whose state slots are live receipts of real system events,
/// a secure token field, and the footer caption + "Create token ↗" link.
///
/// RENDERING CONTRACT: this view renders `TokenLedger.Card` descriptors and NOTHING else —
/// every state decision (event → row states, error routing, reset rules, all strings)
/// lives in `GithudCore.TokenLedger`, pure and tested. `apply(_:)` updates IN PLACE
/// (the field's editing state and in-flight check fades must survive data renders — this
/// card is never torn down per render the way the island content is).
///
/// MOTION (attention-non-theft — every fade maps 1:1 to a real callback):
/// - a slot turning DONE/FAILED fades its glyph in over 120ms, fired ONLY by the real
///   event that flipped the descriptor; two rows flipping in ONE apply (submitToken's
///   shape-gate + Keychain store) stagger 0/150ms — the true event order, visualized;
/// - a reset (done/failed → pending) is INSTANT — a reset is not progress;
/// - detail text changes are 0ms swaps ("verifying…" is static text, deliberately no
///   spinner — no ambient motion, ever);
/// - Reduce Motion → every fade is an instant swap.
///
/// KEY MOMENT (the ratified scoped focus-non-theft relaxation, D-card half): the secure
/// field is the ONE thing in the product that can take keystrokes, and only after the
/// user's own click into it — the field's mouseDown reports up (`onFieldClick`) so the
/// controller can flip `HUDPanel.keySessionActive` + `makeKey()`. Esc reports `onEscape`;
/// the controller ends the session and hands key back. The app never activates.
final class LedgerCardView: NSView, NSTextFieldDelegate {
    static let width: CGFloat = 420

    private let theme: Theme
    private let onSubmit: (String) -> Void
    private let onFieldClick: () -> Void
    private let onEscape: () -> Void

    private var card: TokenLedger.Card
    private var rowViews: [LedgerRowView] = []
    private let field = LedgerTokenField()
    private var fieldWell: NSView!
    private var submitButton: LedgerLinkView!
    private var settingsURL: URL? { URL(string: card.settingsURL) }

    init(card: TokenLedger.Card, theme: Theme,
         onSubmit: @escaping (String) -> Void,
         onFieldClick: @escaping () -> Void,
         onEscape: @escaping () -> Void) {
        self.card = card
        self.theme = theme
        self.onSubmit = onSubmit
        self.onFieldClick = onFieldClick
        self.onEscape = onEscape
        super.init(frame: .zero)

        // HEADER — key glyph + title.
        let keyGlyph = NSImageView()
        keyGlyph.image = NSImage(systemSymbolName: "key.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        keyGlyph.contentTintColor = theme.inkSecondary
        keyGlyph.setContentHuggingPriority(.required, for: .horizontal)
        let title = NSTextField(labelWithString: card.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.inkPrimary
        let header = NSStackView(views: [keyGlyph, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 8

        // PROMISE — the one-line read-only claim.
        let promise = NSTextField(wrappingLabelWithString: card.promise)
        // A wrapping label is SELECTABLE by default, and a selectable NSTextField answers
        // `needsPanelToBecomeKey == true` — the exact predicate `becomesKeyOnlyIfNeeded`
        // consults. Left selectable, a click on this prose would take key and paint the
        // FIELD's focus cue for a focus it doesn't have (the ratified payout line: key is
        // taken ONLY by the user's own click into the card's field). Empirically probed.
        promise.isSelectable = false
        promise.font = .systemFont(ofSize: 11)
        promise.textColor = theme.inkSecondary

        // LEDGER — three receipt rows.
        rowViews = card.rows.map { LedgerRowView(row: $0, theme: theme, openURL: { [weak self] in
            self?.openSettings()
        }) }

        let ledger = NSStackView(views: rowViews)
        ledger.orientation = .vertical
        ledger.alignment = .leading
        ledger.spacing = 8

        // FIELD — the secure well (h32, radius 8, hairline border; focus = accent cue).
        fieldWell = makeFieldWell()

        // FOOTER — caption + trailing "Create token ↗" (visible without hover — the
        // create-token path must exist in EVERY card state, not only inside a remedy).
        let caption = NSTextField(labelWithString: card.footerCaption)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = theme.inkTertiary
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let createLink = LedgerLinkView(title: card.createLinkTitle, font: .systemFont(ofSize: 11),
                                        color: theme.inkSecondary, hover: theme.hoverFill) { [weak self] in
            self?.openSettings()
        }
        let footer = NSStackView(views: [caption, spacer, createLink])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 6

        let stack = NSStackView(views: [header, promise, ledger, fieldWell, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            ledger.widthAnchor.constraint(equalTo: stack.widthAnchor),
            fieldWell.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footer.widthAnchor.constraint(equalTo: stack.widthAnchor),
            promise.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])

        // First paint is NEVER animated: a runtime re-present's pre-checked rows are facts
        // being stated, not events happening now.
        apply(card, animatedBase: false)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The card's height at its 420pt width (mirrors the island's fittingHeight pattern).
    func fittingHeight() -> CGFloat {
        let w = widthAnchor.constraint(equalToConstant: LedgerCardView.width)
        w.isActive = true
        layoutSubtreeIfNeeded()
        let h = ceil(fittingSize.height)
        w.isActive = false
        return h
    }

    // MARK: - descriptor application (in place — the view outlives renders)

    func apply(_ new: TokenLedger.Card) {
        apply(new, animatedBase: true)
    }

    private func apply(_ new: TokenLedger.Card, animatedBase: Bool) {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Stagger newly-done/failed slots by their arrival ORDER within this one apply —
        // rows 1+2 checking together (shape gate, then store: both events truly happened,
        // in that order) land 0/150ms apart. Transitions INTO pending are always instant.
        var stagger: TimeInterval = 0
        for (view, row) in zip(rowViews, new.rows) {
            let advanced = view.currentSlot != row.slot && row.slot != .pending
            let animate = animatedBase && advanced && !reduceMotion
            view.apply(row: row, animated: animate, delay: animate ? stagger : 0)
            if animate { stagger += 0.15 }
        }
        card = new
        // While complete (the 700ms hold before the morph) the field goes quiet — no new
        // submission can outrun the celebration already scheduled. A disabled field also
        // reports `needsPanelToBecomeKey == false`, so a reflexive click on it during the
        // hold can no longer take key (fix round, finding 8).
        field.isEnabled = !new.isComplete
        refreshSubmitAffordance()
    }

    /// The in-progress token text — read ONLY by the controller's surface-rebuild stash
    /// (fix round, finding 9: a theme/a11y switch must not eat a half-pasted secret).
    /// Never logged, never persisted.
    func currentFieldText() -> String? {
        let text = field.stringValue
        return text.isEmpty ? nil : text
    }

    /// Restore stashed in-progress text into a freshly-built card (the surface-rebuild
    /// pair of `currentFieldText`). Editing focus is NOT restored — re-entering the key
    /// moment stays a deliberate user click.
    func restoreFieldText(_ text: String) {
        field.stringValue = text
        refreshSubmitAffordance()
    }

    // MARK: - the secure field well

    private func makeFieldWell() -> NSView {
        let well = FieldWellView()
        well.wantsLayer = true
        well.layer?.cornerRadius = 8
        well.layer?.cornerCurve = .continuous
        // A slightly-lifted fill derived from the theme's hover token (the spec's #161B22
        // over #0D1117 ≈ the same few-percent lift), so every theme gets a coherent well.
        well.layer?.backgroundColor = theme.hoverFill
            .withAlphaComponent(theme.hoverFill.alphaComponent * 0.6).cgColor
        well.layer?.borderWidth = 1
        well.layer?.borderColor = theme.border.cgColor
        well.translatesAutoresizingMaskIntoConstraints = false

        let lock = NSImageView()
        lock.image = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        lock.contentTintColor = theme.inkTertiary
        lock.translatesAutoresizingMaskIntoConstraints = false
        lock.setContentHuggingPriority(.required, for: .horizontal)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none                 // the well's accent border IS the focus cue
        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = theme.inkPrimary
        field.placeholderAttributedString = NSAttributedString(
            string: card.fieldPlaceholder,
            attributes: [.foregroundColor: theme.inkTertiary,
                         .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        field.delegate = self
        field.onFieldClick = { [weak self] in self?.onFieldClick() }
        field.translatesAutoresizingMaskIntoConstraints = false
        field.setAccessibilityLabel("GitHub token")

        submitButton = LedgerLinkView(title: card.submitTitle, font: .systemFont(ofSize: 12, weight: .medium),
                                      color: theme.inkTertiary, hover: theme.hoverFill) { [weak self] in
            self?.submit()
        }

        well.addSubview(lock)
        well.addSubview(field)
        well.addSubview(submitButton)
        NSLayoutConstraint.activate([
            well.heightAnchor.constraint(equalToConstant: 32),
            lock.leadingAnchor.constraint(equalTo: well.leadingAnchor, constant: 10),
            lock.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: lock.trailingAnchor, constant: 8),
            field.centerYAnchor.constraint(equalTo: well.centerYAnchor),
            field.trailingAnchor.constraint(equalTo: submitButton.leadingAnchor, constant: -8),
            submitButton.trailingAnchor.constraint(equalTo: well.trailingAnchor, constant: -10),
            submitButton.centerYAnchor.constraint(equalTo: well.centerYAnchor),
        ])
        return well
    }

    /// "Connect ⏎" is inert (tertiary ink, no hover) while the field is empty — it marks a
    /// genuinely available action, in ink only (the welcome-steps green unlock-check was
    /// amended away; the ledger's row 1 is the shape verdict's real home).
    private func refreshSubmitAffordance() {
        let actionable = !field.stringValue.isEmpty && field.isEnabled
        submitButton.setEnabled(actionable, color: actionable ? theme.inkPrimary : theme.inkTertiary)
    }

    /// The focus cue: border 1px theme.border ⇄ 1.5px accent, 120ms (Reduce Motion →
    /// instant). Driven by the controller's key-session begin/end — the cue and the
    /// relaxation can never disagree.
    func setFieldFocused(_ focused: Bool) {
        guard let layer = fieldWell.layer else { return }
        let color = (focused ? theme.accent : theme.border).cgColor
        let width: CGFloat = focused ? 1.5 : 1
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            layer.borderColor = color
            layer.borderWidth = width
            return
        }
        let group = CAAnimationGroup()
        let colorAnim = CABasicAnimation(keyPath: "borderColor")
        colorAnim.fromValue = layer.presentation()?.borderColor ?? layer.borderColor
        colorAnim.toValue = color
        let widthAnim = CABasicAnimation(keyPath: "borderWidth")
        widthAnim.fromValue = layer.presentation()?.borderWidth ?? layer.borderWidth
        widthAnim.toValue = width
        group.animations = [colorAnim, widthAnim]
        group.duration = 0.12
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
        layer.add(group, forKey: "focusCue")
        layer.borderColor = color
        layer.borderWidth = width
    }

    // MARK: - submission + keyboard

    private func submit() {
        let raw = field.stringValue
        guard !raw.isEmpty, field.isEnabled else { return }   // an empty submit claims nothing
        onSubmit(raw)
    }

    func controlTextDidChange(_ obj: Notification) {
        refreshSubmitAffordance()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) {
            submit()
            return true
        }
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            onEscape()          // Esc ends the key moment instantly; the card stays
            return true
        }
        return false
    }

    private func openSettings() {
        if let url = settingsURL { NSWorkspace.shared.open(url) }
    }
}

// MARK: - one ledger row

/// One receipt row: [16×16 state slot] [10] [label, 76pt column] [detail] — plus the
/// remedy block (danger sentence + settings link) under a failed row. Slot transitions
/// fade 120ms when `animated` (fired only by the descriptor actually changing — the
/// caller binds that to the real event); resets are instant.
private final class LedgerRowView: NSView {
    private(set) var currentSlot: TokenLedger.SlotState
    private var currentRemedy: String?

    private let theme: Theme
    private let openURL: () -> Void
    private let circle = NSView()
    private let slotIcon = NSImageView()
    private let detailLabel = NSTextField(labelWithString: "")
    private let stack = NSStackView()
    private var remedyView: NSView?

    init(row: TokenLedger.Row, theme: Theme, openURL: @escaping () -> Void) {
        self.theme = theme
        self.openURL = openURL
        self.currentSlot = row.slot
        self.currentRemedy = nil
        super.init(frame: .zero)

        // Slot: an empty 16×16 circle (pending) hosting the check, or replaced by the
        // per-reason danger glyph (failed).
        let slot = NSView()
        slot.translatesAutoresizingMaskIntoConstraints = false
        circle.wantsLayer = true
        circle.layer?.cornerRadius = 8
        circle.layer?.borderWidth = 1.5
        circle.layer?.borderColor = theme.border.cgColor
        circle.translatesAutoresizingMaskIntoConstraints = false
        slotIcon.translatesAutoresizingMaskIntoConstraints = false
        slot.addSubview(circle)
        slot.addSubview(slotIcon)
        NSLayoutConstraint.activate([
            slot.widthAnchor.constraint(equalToConstant: 16),
            slot.heightAnchor.constraint(equalToConstant: 16),
            circle.widthAnchor.constraint(equalToConstant: 16),
            circle.heightAnchor.constraint(equalToConstant: 16),
            circle.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            circle.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
            slotIcon.centerXAnchor.constraint(equalTo: slot.centerXAnchor),
            slotIcon.centerYAnchor.constraint(equalTo: slot.centerYAnchor),
        ])

        let label = NSTextField(labelWithString: row.label)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = theme.inkPrimary
        label.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let line = NSStackView(views: [slot, label, detailLabel])
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 10
        line.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 28),
            label.widthAnchor.constraint(equalToConstant: 76),
        ])

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(line)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            line.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        apply(row: row, animated: false, delay: 0, force: true)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func apply(row: TokenLedger.Row, animated: Bool, delay: TimeInterval, force: Bool = false) {
        // Detail text is a 0ms swap in every case ("verifying…" stays deliberately still).
        detailLabel.stringValue = row.detail
        detailLabel.font = row.detailStyle == .mono
            ? .monospacedSystemFont(ofSize: 11, weight: .regular)
            : .systemFont(ofSize: 11)
        detailLabel.textColor = detailColor(row.detailStyle)

        if force || row.slot != currentSlot {
            currentSlot = row.slot
            applySlot(row.slot, animated: animated, delay: delay)
        }
        if force || row.remedy != currentRemedy {
            currentRemedy = row.remedy
            remedyView?.removeFromSuperview()
            remedyView = nil
            if let remedy = row.remedy {
                let view = makeRemedy(remedy)
                remedyView = view
                stack.addArrangedSubview(view)
                stack.setCustomSpacing(2, after: stack.arrangedSubviews[0])
                if animated {   // opacity-only arrival, riding the same real event as the glyph
                    InkFade.run(view, from: 0, to: 1, delay: delay,
                                duration: 0.12, curve: CAMediaTimingFunction(name: .easeOut))
                }
            }
        }
        setAccessibilityLabel(spokenLabel(row))
    }

    private func applySlot(_ slot: TokenLedger.SlotState, animated: Bool, delay: TimeInterval) {
        switch slot {
        case .pending:
            circle.isHidden = false
            slotIcon.image = nil                 // a reset is not progress — instant, no fade
            slotIcon.layer?.removeAllAnimations()
        case .done:
            circle.isHidden = false
            slotIcon.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: "done")?
                .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
            slotIcon.contentTintColor = theme.inkPrimary   // ink — the morph is the celebration, not a hue
            if animated {
                InkFade.run(slotIcon, from: 0, to: 1, delay: delay,
                            duration: 0.12, curve: CAMediaTimingFunction(name: .easeOut))
            }
        case .failed(let symbol):
            circle.isHidden = true               // the reason glyph REPLACES the circle (spec)
            slotIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "failed")?
                .withSymbolConfiguration(.init(pointSize: 12, weight: .semibold))
            slotIcon.contentTintColor = theme.danger       // a genuine intervene — the sanctioned use
            if animated {
                InkFade.run(slotIcon, from: 0, to: 1, delay: delay,
                            duration: 0.12, curve: CAMediaTimingFunction(name: .easeOut))
            }
        }
    }

    private func makeRemedy(_ text: String) -> NSView {
        let sentence = NSTextField(wrappingLabelWithString: text)
        sentence.isSelectable = false   // key stays field-only — see the promise label's note
        sentence.font = .systemFont(ofSize: 11)
        sentence.textColor = theme.danger
        sentence.translatesAutoresizingMaskIntoConstraints = false

        let link = LedgerLinkView(title: "GitHub settings ↗", font: .systemFont(ofSize: 11),
                                  color: theme.danger, underlined: true, hover: theme.hoverFill,
                                  action: openURL)

        let block = NSStackView(views: [sentence, link])
        block.orientation = .vertical
        block.alignment = .leading
        block.spacing = 3
        block.edgeInsets = NSEdgeInsets(top: 0, left: 26, bottom: 2, right: 0)   // indent under the slot
        block.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            sentence.widthAnchor.constraint(lessThanOrEqualToConstant: LedgerCardView.width - 36 - 26 - 26),
        ])
        return block
    }

    private func detailColor(_ style: TokenLedger.DetailStyle) -> NSColor {
        switch style {
        case .placeholder: return theme.inkTertiary
        case .plain, .mono: return theme.inkSecondary
        case .caution: return theme.caution
        }
    }

    private func spokenLabel(_ row: TokenLedger.Row) -> String {
        let state: String
        switch row.slot {
        case .pending: state = "pending"
        case .done: state = "done"
        case .failed: state = "failed"
        }
        var parts = ["\(row.label): \(state)"]
        if !row.detail.isEmpty, row.detail != "—" { parts.append(row.detail) }
        if let remedy = row.remedy { parts.append(remedy) }
        return parts.joined(separator: ". ")
    }
}

// MARK: - supporting leaf views

/// The secure token field, under the non-key panel. Key acquisition is AppKit's own
/// palette mechanism (fix round): the panel has `becomesKeyOnlyIfNeeded = true`, and this
/// field answers `needsPanelToBecomeKey` while enabled — so the user's click INTO the
/// field (and nothing else on the card) makes the panel key, decided in sendEvent where
/// the click→key decision actually lives. `onFieldClick` remains as a same-click-context
/// fallback (`beginKeySession` → `makeKey()` if the sendEvent path declined), guarded on
/// `isEnabled` so a dead field during the completion hold can never take key.
private final class LedgerTokenField: NSSecureTextField {
    var onFieldClick: (() -> Void)?
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var needsPanelToBecomeKey: Bool { isEnabled }
    override func mouseDown(with event: NSEvent) {
        if isEnabled { onFieldClick?() }
        super.mouseDown(with: event)
    }
}

/// The well view under the field (kill window-drag, accept first mouse — same non-key
/// event contract as every island surface).
private final class FieldWellView: NSView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A small text "link" — gesture-driven like every clickable under the non-key panel
/// (never an NSButton), visible without hover; hover adds the standard fill + hand.
final class LedgerLinkView: IslandClickableView {
    private let action: () -> Void
    private let label: NSTextField
    private let hoverColor: NSColor
    private var isEnabledFlag = true

    init(title: String, font: NSFont, color: NSColor, underlined: Bool = false,
         hover: NSColor, action: @escaping () -> Void) {
        self.action = action
        self.hoverColor = hover
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if underlined { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
        label = NSTextField(labelWithString: "")
        label.attributedStringValue = NSAttributedString(string: title, attributes: attributes)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        hoverFill = hover
        translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -3),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Inert ⇄ actionable (the "Connect ⏎" affordance): inert drops the hover cue too, so
    /// the view never signals a click it would ignore.
    func setEnabled(_ enabled: Bool, color: NSColor) {
        isEnabledFlag = enabled
        hoverFill = enabled ? hoverColor : nil
        let current = label.attributedStringValue
        let mutable = NSMutableAttributedString(attributedString: current)
        mutable.addAttribute(.foregroundColor, value: color,
                             range: NSRange(location: 0, length: mutable.length))
        label.attributedStringValue = mutable
    }

    @objc private func tapped() {
        guard isEnabledFlag else { return }
        action()
    }
    override func accessibilityPerformPress() -> Bool {
        guard isEnabledFlag else { return false }
        action(); return true
    }
}
