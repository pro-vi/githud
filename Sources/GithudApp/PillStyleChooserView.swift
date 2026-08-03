import AppKit
import GithudCore

/// WP 2026-07-10-001 §4 — the pill-style chooser card. "Config with actual visual preview":
/// three radio rows, each carrying a LIVE `CollapsedPillView` preview of THAT style, fed the
/// user's CURRENT model data with radar SUPPRESSED (radar states are identical across styles,
/// so the preview shows the one state where the styles differ, from real data — never a
/// fabricated specimen). When the door is empty the three coincide, and the card SAYS so.
///
/// Renders `GithudCore.PillStyleChooser` (pure copy) and nothing else. NO key moment: the card
/// has no editable field, so `PillStyleChooser.takesKeyMoment == false` and the controller
/// keeps `keySessionActive` false throughout (focus-non-theft). Selection reports up via
/// `onSelect`; the controller persists + applies instantly (the pill morphs on dismiss).
final class PillStyleChooserView: NSView {
    static let width: CGFloat = 380

    private let theme: Theme
    private let onSelect: (PillStyle) -> Void

    private var chooser: PillStyleChooser
    private var selected: PillStyle
    private var pulse: [PulseRow]
    private var inboundActive: Int
    private var pollFreshness: Freshness
    private var sweepFreshness: Freshness
    /// Whether a COMPLETE sweep has ever read the door (fix round M-3): the empty-door note
    /// may claim "empty" only over a confirmed read — the unconfirmed line claims only the
    /// coincidence.
    private var sweepConfirmed: Bool

    private let rowsStack = NSStackView()
    private let coincideLabel = NSTextField(labelWithString: "")

    init(chooser: PillStyleChooser, selected: PillStyle, pulse: [PulseRow], inboundActive: Int,
         freshness: Freshness, sweepFreshness: Freshness, sweepConfirmed: Bool, theme: Theme,
         onSelect: @escaping (PillStyle) -> Void, onBack: (() -> Void)? = nil) {
        self.chooser = chooser
        self.selected = selected
        self.pulse = pulse
        self.inboundActive = inboundActive
        self.pollFreshness = freshness
        self.sweepFreshness = sweepFreshness
        self.sweepConfirmed = sweepConfirmed
        self.theme = theme
        self.onSelect = onSelect
        super.init(frame: .zero)

        // HEADER — title + "(back)" (every pane carries one; dogfood 2026-07-14).
        let title = NSTextField(labelWithString: chooser.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.inkPrimary
        title.setContentHuggingPriority(.required, for: .horizontal)
        let headerSpacer = NSView()
        headerSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerSpacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let back = CardBackControl(theme: theme, onBack: onBack)
        back.setContentHuggingPriority(.required, for: .horizontal)
        let headerRow = NSStackView(views: [title, headerSpacer, back])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        rowsStack.orientation = .vertical
        rowsStack.alignment = .leading
        rowsStack.spacing = 6

        // CAPTION — names why the previews show the caught-up state, from real data.
        let caption = NSTextField(wrappingLabelWithString: chooser.caption)
        caption.isSelectable = false   // key stays nowhere on this card (no field, no selection)
        caption.font = .systemFont(ofSize: 11)
        caption.textColor = theme.inkTertiary

        coincideLabel.isSelectable = false
        coincideLabel.font = .systemFont(ofSize: 11)
        coincideLabel.textColor = theme.inkSecondary

        let stack = NSStackView(views: [headerRow, rowsStack, caption, coincideLabel])
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
            headerRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            rowsStack.widthAnchor.constraint(equalTo: stack.widthAnchor),
            caption.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            coincideLabel.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
        ])

        rebuildRows()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The card's height at its fixed width (mirrors the ledger/island fittingHeight pattern).
    func fittingHeight() -> CGFloat {
        let w = widthAnchor.constraint(equalToConstant: PillStyleChooserView.width)
        w.isActive = true
        layoutSubtreeIfNeeded()
        let h = ceil(fittingSize.height)
        w.isActive = false
        return h
    }

    /// Refresh in place (a data poll while the card is up, or a selection). No teardown of the
    /// whole card — just rebuild the option rows (previews + radios) from current state.
    func update(chooser: PillStyleChooser, selected: PillStyle, pulse: [PulseRow],
                inboundActive: Int, freshness: Freshness, sweepFreshness: Freshness,
                sweepConfirmed: Bool) {
        // Input-diff guard (fix round M-2): a poll tick that changed nothing the previews
        // RENDER must not recreate three live pills every ~60s while the card is open. The
        // clocks compare on their render-affecting boolean (`isDegraded` — the previews'
        // stale prefix); a degraded clock's ageing seconds repaint nothing here.
        let unchanged = chooser == self.chooser && selected == self.selected
            && pulse == self.pulse && inboundActive == self.inboundActive
            && sweepConfirmed == self.sweepConfirmed
            && freshness.isDegraded == self.pollFreshness.isDegraded
            && sweepFreshness.isDegraded == self.sweepFreshness.isDegraded
        self.chooser = chooser
        self.selected = selected
        self.pulse = pulse
        self.inboundActive = inboundActive
        self.pollFreshness = freshness
        self.sweepFreshness = sweepFreshness
        self.sweepConfirmed = sweepConfirmed
        guard !unchanged else { return }
        rebuildRows()
    }

    private func rebuildRows() {
        rowsStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for option in chooser.options {
            let preview = CollapsedPillView(
                rows: [],                                  // radar SUPPRESSED — identical across styles
                pulse: pulse, freshness: pollFreshness, sweepFreshness: sweepFreshness,
                theme: theme, loading: false, inboundActive: inboundActive, style: option.style)
            let row = PillStyleOptionRow(option: option, selected: option.style == selected,
                                         preview: preview, theme: theme,
                                         onClick: { [weak self] in self?.onSelect(option.style) })
            rowsStack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rowsStack.widthAnchor).isActive = true
        }
        // Honesty edge: an empty door means the three previews legitimately coincide — say so
        // (never fabricate a queue to force a visible difference). But "empty" is a CONFIRMED
        // claim (fix round M-3): before the first complete sweep the door merely hasn't been
        // read, so the unconfirmed line claims only the coincidence, never the emptiness.
        if inboundActive == 0 {
            coincideLabel.stringValue = sweepConfirmed ? chooser.coincideNote : chooser.unconfirmedNote
            coincideLabel.isHidden = false
        } else {
            coincideLabel.stringValue = ""
            coincideLabel.isHidden = true
        }
    }
}

/// One chooser row: a radio, the live preview pill, and the option label — the whole row is
/// the click target (a bigger, more forgiving hit area than the radio dot alone).
private final class PillStyleOptionRow: IslandClickableView {
    private let onClick: () -> Void

    init(option: PillStyleChooser.Option, selected: Bool, preview: CollapsedPillView,
         theme: Theme, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill

        // Radio — a 14pt ring; a filled inner dot marks the current selection.
        let radio = NSView()
        radio.wantsLayer = true
        radio.layer?.cornerRadius = 7
        radio.layer?.borderWidth = 1.5
        radio.layer?.borderColor = (selected ? theme.accent : theme.inkTertiary).cgColor
        radio.translatesAutoresizingMaskIntoConstraints = false
        let dot = NSView()
        dot.wantsLayer = true
        dot.layer?.cornerRadius = 3.5
        dot.layer?.backgroundColor = theme.accent.cgColor
        dot.isHidden = !selected
        dot.translatesAutoresizingMaskIntoConstraints = false
        radio.addSubview(dot)

        let previewSize = preview.frame.size
        preview.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: option.label)
        label.font = .systemFont(ofSize: 12, weight: selected ? .medium : .regular)
        label.textColor = selected ? theme.inkPrimary : theme.inkSecondary
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)

        addSubview(radio)
        addSubview(preview)
        addSubview(label)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: max(36, previewSize.height + 8)),
            radio.widthAnchor.constraint(equalToConstant: 14),
            radio.heightAnchor.constraint(equalToConstant: 14),
            radio.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            radio.centerYAnchor.constraint(equalTo: centerYAnchor),
            dot.widthAnchor.constraint(equalToConstant: 7),
            dot.heightAnchor.constraint(equalToConstant: 7),
            dot.centerXAnchor.constraint(equalTo: radio.centerXAnchor),
            dot.centerYAnchor.constraint(equalTo: radio.centerYAnchor),
            preview.widthAnchor.constraint(equalToConstant: previewSize.width),
            preview.heightAnchor.constraint(equalToConstant: previewSize.height),
            preview.leadingAnchor.constraint(equalTo: radio.trailingAnchor, constant: 10),
            preview.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: preview.trailingAnchor, constant: 12),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(option.label)
        setAccessibilityValue(selected ? "selected" : "not selected")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}
