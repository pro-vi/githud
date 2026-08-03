import AppKit
import GithudCore

/// The settings card (mark-and-settings option B, ratified in dogfood 2026-07-14):
/// config lives on the glass — theme chips, the H1 reason set, the reveal toggles,
/// Launch at Login, and doors into the Pill-style and Lens cards. Renders
/// `GithudCore.SettingsCard` (pure copy) and nothing else. Chassis mirrors
/// `LensChooserView` (380pt, fittingHeight, in-place equality-guarded update, "(back)"
/// to the island); the body scrolls scrollerless when a small screen clamps the card
/// (the lane convention: the overflow fade of chrome is not needed — content clips at
/// the card edge). NO key moment.
final class SettingsCardView: NSView {
    static let width: CGFloat = 380

    /// The theme this card was inked with — a theme-chip selection rebuilds the card in
    /// the NEW theme (the render branch compares; `update` can't re-ink baked colors).
    let builtTheme: Theme

    private let theme: Theme
    private let onToggleReason: (String) -> Void
    private let onToggleDrafts: () -> Void
    private let onToggleStale: () -> Void
    private let onToggleHeldBack: () -> Void
    private let onSelectTheme: (ThemeID) -> Void
    private let onToggleLaunch: () -> Void
    private let onOpenPillStyle: () -> Void
    private let onOpenLens: () -> Void

    private var card: SettingsCard
    private let bodyStack = FlippedBodyStack()

    init(card: SettingsCard, theme: Theme,
         onToggleReason: @escaping (String) -> Void,
         onToggleDrafts: @escaping () -> Void, onToggleStale: @escaping () -> Void,
         onToggleHeldBack: @escaping () -> Void,
         onSelectTheme: @escaping (ThemeID) -> Void, onToggleLaunch: @escaping () -> Void,
         onOpenPillStyle: @escaping () -> Void, onOpenLens: @escaping () -> Void,
         onBack: (() -> Void)?) {
        self.card = card
        self.theme = theme
        self.builtTheme = theme
        self.onToggleReason = onToggleReason
        self.onToggleDrafts = onToggleDrafts
        self.onToggleStale = onToggleStale
        self.onToggleHeldBack = onToggleHeldBack
        self.onSelectTheme = onSelectTheme
        self.onToggleLaunch = onToggleLaunch
        self.onOpenPillStyle = onOpenPillStyle
        self.onOpenLens = onOpenLens
        super.init(frame: .zero)

        let title = NSTextField(labelWithString: card.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = theme.inkPrimary
        title.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let back = CardBackControl(theme: theme, onBack: onBack)
        back.setContentHuggingPriority(.required, for: .horizontal)
        let headerRow = NSStackView(views: [title, spacer, back])
        headerRow.orientation = .horizontal
        headerRow.alignment = .centerY
        headerRow.spacing = 6

        bodyStack.orientation = .vertical
        bodyStack.alignment = .leading
        bodyStack.spacing = 4
        bodyStack.translatesAutoresizingMaskIntoConstraints = false

        // Scrollerless scroll wrapper: a small screen clamps the card height and the
        // body scrolls in place (wheel/trackpad; no knob — the app-wide convention).
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.verticalScrollElasticity = .allowed
        scroll.documentView = bodyStack
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let stack = NSStackView(views: [headerRow, scroll])
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
            scroll.widthAnchor.constraint(equalTo: stack.widthAnchor),
            bodyStack.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            // The scroll frame tracks the body's full height; the RENDER branch clamps
            // the card to the screen, and this constraint's lower priority lets the
            // clamp compress the scroll (content then scrolls in place).
            {
                let h = scroll.heightAnchor.constraint(equalTo: bodyStack.heightAnchor)
                h.priority = .defaultHigh
                return h
            }(),
        ])

        rebuild()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Full content height at the fixed width; the render branch clamps to the screen.
    func fittingHeight() -> CGFloat {
        let w = widthAnchor.constraint(equalToConstant: SettingsCardView.width)
        w.isActive = true
        layoutSubtreeIfNeeded()
        let h = ceil(fittingSize.height)
        w.isActive = false
        return h
    }

    /// Refresh in place (a toggle while the card is up). Equality-guarded like its
    /// siblings; theme changes rebuild the whole card instead (see `builtTheme`).
    func update(card: SettingsCard) {
        guard card != self.card else { return }
        self.card = card
        rebuild()
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = theme.inkSecondary
        return label
    }

    private func checkRow(_ item: SettingsCard.CheckItem, onClick: @escaping () -> Void) -> NSView {
        let row = SettingsCheckRow(label: item.label, checked: item.on, theme: theme, onClick: onClick)
        if let tooltip = item.tooltip { row.toolTip = tooltip }
        return row
    }

    private func rebuild() {
        bodyStack.arrangedSubviews.forEach { $0.removeFromSuperview() }

        // THEME — chips, one per theme, live: a pick re-inks the surface and this card.
        bodyStack.addArrangedSubview(sectionHeader(card.themeHeader))
        let chips = NSStackView(views: card.themes.map { chip in
            ThemeChipView(chip: chip, theme: theme,
                          onClick: { [weak self] in
                              if let id = ThemeID(rawValue: chip.id) { self?.onSelectTheme(id) }
                          })
        })
        chips.orientation = .horizontal
        chips.alignment = .centerY
        chips.spacing = 8
        bodyStack.addArrangedSubview(chips)

        bodyStack.addArrangedSubview(spacerView(6))
        bodyStack.addArrangedSubview(sectionHeader(card.surfaceHeader))
        for reason in card.reasons {
            addFullWidth(checkRow(reason) { [weak self] in self?.onToggleReason(reason.id) })
        }

        bodyStack.addArrangedSubview(spacerView(6))
        bodyStack.addArrangedSubview(sectionHeader(card.pulseHeader))
        for item in card.pulseItems {
            let action: () -> Void = item.id == "drafts"
                ? { [weak self] in self?.onToggleDrafts() }
                : { [weak self] in self?.onToggleStale() }
            addFullWidth(checkRow(item, onClick: action))
        }

        bodyStack.addArrangedSubview(spacerView(6))
        bodyStack.addArrangedSubview(sectionHeader(card.inboundHeader))
        for item in card.inboundItems {
            addFullWidth(checkRow(item) { [weak self] in self?.onToggleHeldBack() })
        }

        bodyStack.addArrangedSubview(separator())
        addFullWidth(checkRow(card.launchAtLogin) { [weak self] in self?.onToggleLaunch() })

        bodyStack.addArrangedSubview(separator())
        addFullWidth(DoorRow(label: card.pillStyleDoor, theme: theme,
                             onClick: { [weak self] in self?.onOpenPillStyle() }))
        addFullWidth(DoorRow(label: card.lensDoor, theme: theme,
                             onClick: { [weak self] in self?.onOpenLens() }))
    }

    private func addFullWidth(_ view: NSView) {
        bodyStack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: bodyStack.widthAnchor).isActive = true
    }

    private func spacerView(_ height: CGFloat) -> NSView {
        let v = NSView()
        v.heightAnchor.constraint(equalToConstant: height).isActive = true
        v.setAccessibilityElement(false)
        return v
    }

    private func separator() -> NSView {
        let box = NSBox()
        box.boxType = .separator
        box.setAccessibilityElement(false)
        box.translatesAutoresizingMaskIntoConstraints = false
        box.widthAnchor.constraint(equalToConstant: SettingsCardView.width - 36).isActive = true
        return box
    }
}

/// The scroll wrapper's document stack — flipped so the body opens at the TOP.
private final class FlippedBodyStack: NSStackView {
    override var isFlipped: Bool { true }
}

/// One theme chip: a miniature OF the theme — its SURFACE as the disc, wearing its
/// ACCENT as a center dot (dogfood 2026-07-18: the old accent-only dot was
/// non-discriminating — four near-identical blues, and Solarized Dark/Light share the
/// SAME accent; the surface is what actually tells themes apart). The vibrant theme
/// ("Color") has no fixed surface — it wears the adaptive window ground. Ring in the
/// current theme's primary ink when selected. Tooltip and VoiceOver carry the display
/// name — the chip itself stays wordless ink.
private final class ThemeChipView: IslandClickableView {
    private let onClick: () -> Void

    init(chip: SettingsCard.ThemeChip, theme: Theme, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 13
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill
        toolTip = chip.name

        let chipTheme = Theme.named(ThemeID(rawValue: chip.id) ?? .default)
        let ground: NSColor
        switch chipTheme.surface {
        case .solid(let color): ground = color
        case .vibrant: ground = .windowBackgroundColor   // adaptive stand-in for glass
        }
        let disc = NSView()
        disc.wantsLayer = true
        disc.layer?.cornerRadius = 9
        disc.layer?.backgroundColor = ground.cgColor
        // Hairline so a cream disc reads on light glass and a near-black one on dark;
        // the selected ring replaces it in primary ink.
        disc.layer?.borderWidth = chip.selected ? 2 : 1
        disc.layer?.borderColor = (chip.selected ? theme.inkPrimary : theme.border).cgColor
        disc.translatesAutoresizingMaskIntoConstraints = false
        addSubview(disc)

        let accent = NSView()
        accent.wantsLayer = true
        accent.layer?.cornerRadius = 3.5
        accent.layer?.backgroundColor = chipTheme.accent.cgColor
        accent.translatesAutoresizingMaskIntoConstraints = false
        disc.addSubview(accent)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            heightAnchor.constraint(equalToConstant: 26),
            disc.widthAnchor.constraint(equalToConstant: 18),
            disc.heightAnchor.constraint(equalToConstant: 18),
            disc.centerXAnchor.constraint(equalTo: centerXAnchor),
            disc.centerYAnchor.constraint(equalTo: centerYAnchor),
            accent.widthAnchor.constraint(equalToConstant: 7),
            accent.heightAnchor.constraint(equalToConstant: 7),
            accent.centerXAnchor.constraint(equalTo: disc.centerXAnchor),
            accent.centerYAnchor.constraint(equalTo: disc.centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(chip.name)
        setAccessibilityValue(chip.selected ? "selected" : "not selected")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// One checkable settings row — the LensCheckRow shape (whole row clicks, 14pt box).
private final class SettingsCheckRow: IslandClickableView {
    private let onClick: () -> Void

    init(label: String, checked: Bool, theme: Theme, onClick: @escaping () -> Void) {
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
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
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
        setAccessibilityLabel(label)
        setAccessibilityValue(checked ? "checked" : "unchecked")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// A door into a sibling card ("Pill style…" / "Lens…"): label + trailing chevron.
private final class DoorRow: IslandClickableView {
    private let onClick: () -> Void

    init(label: String, theme: Theme, onClick: @escaping () -> Void) {
        self.onClick = onClick
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill

        let text = NSTextField(labelWithString: label)
        text.font = .systemFont(ofSize: 12)
        text.textColor = theme.inkSecondary
        text.translatesAutoresizingMaskIntoConstraints = false

        let chevron = NSImageView()
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        chevron.contentTintColor = theme.inkTertiary
        chevron.translatesAutoresizingMaskIntoConstraints = false

        addSubview(text)
        addSubview(chevron)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26),
            text.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            text.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevron.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            chevron.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(tapped)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(label)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func tapped() { onClick() }
    override func accessibilityPerformPress() -> Bool { onClick(); return true }
}

/// The card's "(back)" control — shared shape with the lens card's (11px underlined
/// tertiary; returns to the expanded island).
final class CardBackControl: IslandClickableView {
    private let onBack: (() -> Void)?

    init(theme: Theme, onBack: (() -> Void)?) {
        self.onBack = onBack
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        hoverFill = theme.hoverFill

        let attr = NSMutableAttributedString(
            string: PlainWords.lensBackControl,
            attributes: [.font: NSFont.systemFont(ofSize: 11),
                         .foregroundColor: theme.inkTertiary,
                         .underlineStyle: NSUnderlineStyle.single.rawValue])
        let label = NSTextField(labelWithString: "")
        label.attributedStringValue = attr
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            label.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
        addGestureRecognizer(NSClickGestureRecognizer(target: self, action: #selector(clicked)))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(PlainWords.lensBackSpoken)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func accessibilityPerformPress() -> Bool { onBack?(); return true }
    @objc private func clicked() { onBack?() }
}
