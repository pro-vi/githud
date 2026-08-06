import AppKit
import GithudCore

/// WP 2026-07-14-001 — the owner-lens card, the eye's destination. Renders
/// `GithudCore.LensChooser` (pure copy): "Owners:" rows — each with a drag handle
/// (reorder = the lane's group order), the owner title + count, and an eye toggle
/// (show/hide = the fold) — then a separator, then the "Group by owner" shape toggle.
/// Dogfood 2026-07-14 iteration: caption cut (the card explains itself), "(back)"
/// returns to the island (click-away still means "leave"), rows drag to reorder.
/// Chassis mirrors `PillStyleChooserView` (380pt, same insets, fittingHeight, in-place
/// update). NO key moment: no field, `LensChooser.takesKeyMoment == false`.
final class LensChooserView: NSView {
    static let width: CGFloat = 380

    private let theme: Theme
    private let onToggleOwner: (String) -> Void
    private let onToggleGroup: () -> Void
    private let onReorder: ([String]) -> Void

    private var chooser: LensChooser
    private let rowsStack = FlippedCardRows()

    init(chooser: LensChooser, theme: Theme,
         onToggleOwner: @escaping (String) -> Void, onToggleGroup: @escaping () -> Void,
         onReorder: @escaping ([String]) -> Void, onBack: (() -> Void)?) {
        self.chooser = chooser
        self.theme = theme
        self.onToggleOwner = onToggleOwner
        self.onToggleGroup = onToggleGroup
        self.onReorder = onReorder
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: chooser.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.inkPrimary
        title.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        // The way back to the island (the eye's origin) — the revealed-header verb idiom.
        let back = CardBackControl(theme: theme, onBack: onBack)
        back.setContentHuggingPriority(.required, for: .horizontal)
        let headerRow = NSStackView(views: [title, spacer, back])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 4
        rowsStack.translatesAutoresizingMaskIntoConstraints = false

        // Scrollerless scroll wrapper (Codex P2, PR #1 round 4): a large owner set (or a
        // small screen) clamps the card in the render branch and the rows scroll in
        // place — nothing can sit unreachable off-screen. The rows stack is FLIPPED so
        // content opens at the top (drag math below is written in flipped coords).
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = rowsStack
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [headerRow, scroll])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let scrollTracksContent = scroll.heightAnchor.constraint(equalTo: rowsStack.heightAnchor)
        scrollTracksContent.priority = .defaultHigh   // the screen clamp may compress it
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rowsStack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            scrollTracksContent,
        ])

        rebuildRows()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The card's height at its fixed width (the ledger/chooser fittingHeight pattern).
    func fittingHeight() -> CGFloat {
        let w = widthAnchor.constraint(equalToConstant: LensChooserView.width)
        w.isActive = true
        layoutSubtreeIfNeeded()
        let h = ceil(fittingSize.height)
        w.isActive = false
        return h
    }

    /// Refresh in place (a toggle, a reorder, or a data poll while the card is up).
    /// Equality-guarded: the descriptor is recomputed fresh each render, so an unchanged
    /// card repaints nothing. Skipped mid-drag — the drop commit re-renders anyway, and a
    /// rebuild under the pointer would tear the row being dragged.
    func update(chooser: LensChooser) {
        guard chooser != self.chooser, !dragInFlight else { return }
        self.chooser = chooser
        rebuildRows()
    }

    private var dragInFlight = false

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        let header = NSTextField(labelWithString: chooser.ownersHeader)
        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.textColor = theme.inkSecondary
        rowsStack.addArrangedSubview(header)

        for entry in chooser.owners {
            let row = LensOwnerRow(entry: entry, theme: theme,
                                   onToggle: { [weak self] in self?.onToggleOwner(entry.owner) },
                                   host: self)
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }

        // The ratified ─── : shape below, owners above — two orthogonal preferences.
        let separator = NSBox()
        separator.boxType = .separator
        separator.setAccessibilityElement(false)   // decorative
        rowsStack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true

        let group = LensCheckRow(label: chooser.groupByOwnerLabel,
                                 spokenLabel: chooser.groupByOwnerLabel,
                                 checked: chooser.groupByOwner, theme: theme,
                                 onClick: { [weak self] in self?.onToggleGroup() })
        group.toolTip = chooser.groupByOwnerTooltip
        rowsStack.addArrangedSubview(group)
        group.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
    }

    // MARK: - drag-to-reorder (owner rows only, between the header and the separator)

    fileprivate func beginDrag() { dragInFlight = true }

    /// Live-reorder the dragged row toward the pointer. The rows stack is FLIPPED
    /// (y-down: index 0 is the TOP = LOWEST y), so "pointer above a row" means
    /// `pointer.y < row.midY`. Pure arrangement — nothing commits until the drop.
    fileprivate func drag(_ row: LensOwnerRow, pointerInStack: NSPoint) {
        let others = rowsStack.arrangedSubviews
            .compactMap { $0 as? LensOwnerRow }
            .filter { $0 !== row }
            .sorted { $0.frame.midY < $1.frame.midY }          // flipped: top → bottom = ascending y
        guard let firstOwnerIndex = rowsStack.arrangedSubviews.firstIndex(where: { $0 is LensOwnerRow }),
              let current = rowsStack.arrangedSubviews.firstIndex(of: row) else { return }
        var position = others.count
        for (i, other) in others.enumerated() where pointerInStack.y < other.frame.midY {
            position = i
            break
        }
        // `position` indexes the OTHERS list (dragged row excluded), so
        // `firstOwnerIndex + position` is already the POST-removal insertion index —
        // no current<target shift correction on top, or downward drags land one slot
        // short / no-op (Codex P2, PR #1 review round 2: the double-adjust bug).
        let target = firstOwnerIndex + position
        guard target != current else { return }
        rowsStack.removeArrangedSubview(row)                    // stays a subview; frame kept
        rowsStack.insertArrangedSubview(row, at: min(target, rowsStack.arrangedSubviews.count))
        layoutSubtreeIfNeeded()
    }

    /// Drop: commit the visual order as the ONE pref order (lowercased keys) — the lane's
    /// groups, ledger lines, and the card all re-read it on the same re-render.
    fileprivate func endDrag() {
        dragInFlight = false
        let keys = rowsStack.arrangedSubviews.compactMap { ($0 as? LensOwnerRow)?.ownerKey }
        onReorder(keys)
    }

    /// VoiceOver reorder (the pointer-drag's accessible twin — the old gear submenu
    /// fallback died with the verbs-only menu): move one owner row a single step and
    /// commit. Returns false at the edges so the custom action reports honestly.
    fileprivate func moveOwnerRow(_ row: LensOwnerRow, by delta: Int) -> Bool {
        let ownerRows = rowsStack.arrangedSubviews.compactMap { $0 as? LensOwnerRow }
        guard let i = ownerRows.firstIndex(where: { $0 === row }) else { return false }
        let j = i + delta
        guard j >= 0, j < ownerRows.count,
              let targetGlobal = rowsStack.arrangedSubviews.firstIndex(of: ownerRows[j])
        else { return false }
        // Adjacent swap: moving UP inserts at the (unshifted) target index; moving DOWN
        // inserts at the target's index, which the removal just shifted left by one —
        // both land exactly one step over (walked for A/B/C in both directions).
        rowsStack.removeArrangedSubview(row)
        rowsStack.insertArrangedSubview(row, at: targetGlobal)
        endDrag()
        return true
    }
}

/// The card's scrollable rows — flipped so content opens at the TOP inside the wrapper.
private final class FlippedCardRows: NSStackView {
    override var isFlipped: Bool { true }
}

/// One owner row: ≡ drag handle · title with count · eye toggle at the right edge
/// (eye = shown/leads, eye.slash = hidden/folded — the lane eye's own vocabulary).
/// The whole row DRAGS; only the eye toggles (drag and click can't collide). Plain
/// NSView, not IslandClickableView, so the embedded eye button receives its own events
/// (the clickable base flattens hitTest to itself). VoiceOver: the eye button carries a
/// state-bearing label; drag order is pointer-only for now — the gear submenu remains
/// the ordered, item-per-owner fallback (recorded gap).
private final class LensOwnerRow: NSView {
    let ownerKey: String
    private weak var host: LensChooserView?
    private var dragging = false
    private var eye: IconButton!
    private var onToggleForA11y: (() -> Void)?

    // The HUD is a NON-KEY panel while the card is up (no key moment): without
    // first-mouse the initial drag-click is swallowed, and without the hitTest flatten
    // the label/handle subviews win the click (Codex P2, PR #1 round 3). The eye keeps
    // its own target — the row/chevron carve-out pattern.
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        return eye.frame.contains(p) ? eye : self
    }

    init(entry: LensChooser.OwnerEntry, theme: Theme, onToggle: @escaping () -> Void,
         host: LensChooserView) {
        self.ownerKey = entry.owner.lowercased()
        self.host = host
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous

        let handle = NSImageView()
        handle.image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .regular))
        handle.contentTintColor = theme.inkTertiary
        handle.translatesAutoresizingMaskIntoConstraints = false
        handle.setAccessibilityElement(false)   // decorative — the row itself drags

        // Reuse the LEDGER grammar so the card row and the folded line it produces can never
        // read differently ("four surfaces, one truth"): "acme · 4, 5 drafts, 2 gone quiet",
        // and the zero-live forms "facebook · 1 draft" / "helios-oss · 3 gone quiet" for a
        // tail-only owner. A folded remnant with nothing left in the lane still prints its bare
        // title — the `· 0` the ledger would honestly render is not what a card row wants to say.
        let hasRows = entry.count > 0 || entry.draftCount > 0 || entry.quietCount > 0
        let label = hasRows
            ? PlainWords.lensLedger(entry.title, count: entry.count, draftCount: entry.draftCount,
                                    quietCount: entry.quietCount)
            : entry.title
        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: entry.leads ? .medium : .regular)
        text.textColor = entry.leads ? theme.inkPrimary : theme.inkTertiary
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false

        eye = IconButton(symbol: entry.leads ? "eye" : "eye.slash",
                         tooltip: "\(entry.title) — \(entry.leads ? "shown" : "hidden")",
                         tint: entry.leads ? theme.inkSecondary : theme.inkTertiary,
                         hover: theme.hoverFill, action: onToggle)
        // ONE VoiceOver stop per owner row: press toggles show/hide, custom actions
        // reorder (the pointer drag's accessible twin). The eye stays pointer-only —
        // exposing both would double-speak every owner.
        eye.setAccessibilityElement(false)
        self.onToggleForA11y = onToggle
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        // Spoken form goes through the SAME PlainWords home as the visible label above, so a
        // row and the folded ledger line it produces can never read differently — and the
        // drafts plural rule stays in one place instead of being hand-inlined here.
        setAccessibilityLabel(PlainWords.lensCardRowSpoken(entry.title, count: entry.count,
                                                           draftCount: entry.draftCount,
                                                           quietCount: entry.quietCount))
        setAccessibilityValue(entry.leads ? "shown" : "hidden")

        addSubview(handle)
        addSubview(text)
        addSubview(eye)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            handle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            handle.centerYAnchor.constraint(equalTo: centerYAnchor),
            text.leadingAnchor.constraint(equalTo: handle.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: eye.leadingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            eye.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            eye.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func mouseDown(with event: NSEvent) {
        dragging = true
        alphaValue = 0.7
        host?.beginDrag()
    }

    override func mouseDragged(with event: NSEvent) {
        guard dragging, let stack = superview as? NSStackView else { return }
        host?.drag(self, pointerInStack: stack.convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        guard dragging else { return }
        dragging = false
        alphaValue = 1
        host?.endDrag()
    }

    override func accessibilityPerformPress() -> Bool {
        onToggleForA11y?()
        return true
    }

    override func accessibilityCustomActions() -> [NSAccessibilityCustomAction]? {
        [
            NSAccessibilityCustomAction(name: "Move up") { [weak self] in
                guard let self, let host = self.host else { return false }
                return host.moveOwnerRow(self, by: -1)
            },
            NSAccessibilityCustomAction(name: "Move down") { [weak self] in
                guard let self, let host = self.host else { return false }
                return host.moveOwnerRow(self, by: 1)
            },
        ]
    }
}

/// One checkable card row (the "Group by owner" shape toggle): a 14pt check box +
/// label; the whole row is the click target. VoiceOver: a checkbox.
private final class LensCheckRow: IslandClickableView {
    private let onClick: () -> Void

    init(label: String, spokenLabel: String, checked: Bool, theme: Theme, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill

        let box = NSView()
        box.wantsLayer = true
        box.layer?.cornerRadius = 3.5
        box.layer?.cornerCurve = .continuous
        box.layer?.borderWidth = 1.5
        box.layer?.borderColor = (checked ? theme.accent : theme.inkTertiary).cgColor
        box.layer?.backgroundColor = checked ? theme.accent.cgColor : nil
        box.translatesAutoresizingMaskIntoConstraints = false
        let check = NSImageView()
        check.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .bold))
        check.contentTintColor = theme.badgeInk
        check.isHidden = !checked
        check.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(check)

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12, weight: checked ? .medium : .regular)
        text.textColor = checked ? theme.inkPrimary : theme.inkSecondary
        text.lineBreakMode = .byTruncatingTail
        text.translatesAutoresizingMaskIntoConstraints = false

        addSubview(box)
        addSubview(text)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 28),
            box.widthAnchor.constraint(equalToConstant: 14),
            box.heightAnchor.constraint(equalToConstant: 14),
            box.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            box.centerYAnchor.constraint(equalTo: centerYAnchor),
            check.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            check.centerYAnchor.constraint(equalTo: box.centerYAnchor),
            text.leadingAnchor.constraint(equalTo: box.trailingAnchor, constant: 10),
            text.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(spokenLabel)
        setAccessibilityValue(checked ? "checked" : "unchecked")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}
