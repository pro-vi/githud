import AppKit
import GithudCore

/// GitHub's canonical PR/check status icons — THEME-INDEPENDENT by design. A PR's *status*
/// is GitHub's visual language, not githud's chrome (the same reason the auth warning stays
/// systemOrange across themes), so the "Your PRs" lane mirrors GitHub's icons — green check,
/// red ✕, amber pending dot, gray conflict warning — identically in every theme. (The H1
/// radar still follows the color doctrine; only H2 PR-status adopts GitHub's palette.)
enum GitHubStatus {
    case success    // mergeable + checks pass → green check
    case failure    // CI failing / changes requested → red ✕
    case pending    // review required / CI pending / merge unknown → amber dot
    case conflict   // merge conflict → gray warning triangle
    case draft      // draft PR → muted gray pencil

    /// Per-PR mapping (uses the raw merge member so a conflict gets its own glyph).
    static func forPulse(state: PulseState, merge: MergeState) -> GitHubStatus {
        if merge == .conflicting { return .conflict }
        return forState(state)
    }

    /// State-only mapping (the collapsed gauge has no per-PR merge info).
    static func forState(_ state: PulseState) -> GitHubStatus {
        switch state {
        case .ready:   return .success
        case .blocked: return .failure
        case .waiting: return .pending
        case .draft:   return .draft
        }
    }

    /// GitHub Primer status colors (dark-mode values — vivid, and they read on every theme
    /// surface incl. the one light theme).
    var color: NSColor {
        switch self {
        case .success:  return Self.hex(0x3FB950)   // success.emphasis
        case .failure:  return Self.hex(0xF85149)   // danger.emphasis
        case .pending:  return Self.hex(0xD29922)   // attention.emphasis
        case .conflict: return Self.hex(0x6E7681)   // fg.muted
        case .draft:    return Self.hex(0x6E7681)   // fg.muted
        }
    }

    /// The white inner glyph; `nil` = a small white dot (GitHub's pending `dot-fill`).
    var innerSymbol: String? {
        switch self {
        case .success:  return "checkmark"
        case .failure:  return "xmark"
        case .pending:  return nil
        case .conflict: return "exclamationmark.triangle.fill"
        case .draft:    return "pencil"
        }
    }

    var innerPointSize: CGFloat { self == .conflict ? 9 : 8 }

    var label: String {
        switch self {
        case .success:  return "ready — checks pass"
        case .failure:  return "blocked — CI failing or changes requested"
        case .pending:  return "in progress"
        case .conflict: return "merge conflict"
        case .draft:    return "draft"
        }
    }

    private static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255.0,
                green: CGFloat((v >> 8) & 0xFF) / 255.0,
                blue: CGFloat(v & 0xFF) / 255.0, alpha: 1.0)
    }
}

/// A 16pt GitHub-style status badge: a filled status-color circle with a white inner glyph
/// (or a white dot for `pending`). Theme-independent — see `GitHubStatus`.
final class GitHubStatusBadge: NSView {
    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 16) }

    init(_ status: GitHubStatus) {
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 16))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = status.color.cgColor
        translatesAutoresizingMaskIntoConstraints = false

        let inner: NSView
        var extra: [NSLayoutConstraint] = []
        if let symbol = status.innerSymbol {
            let iv = NSImageView()
            iv.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: status.innerPointSize, weight: .bold))
            iv.contentTintColor = .white
            inner = iv
        } else {
            let dot = NSView()              // pending → a small white dot (GitHub's dot-fill)
            dot.wantsLayer = true
            dot.layer?.backgroundColor = NSColor.white.cgColor
            dot.layer?.cornerRadius = 2.5
            extra = [dot.widthAnchor.constraint(equalToConstant: 5),
                     dot.heightAnchor.constraint(equalToConstant: 5)]
            inner = dot
        }
        inner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inner)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 16),
            heightAnchor.constraint(equalToConstant: 16),
            inner.centerXAnchor.constraint(equalTo: centerXAnchor),
            inner.centerYAnchor.constraint(equalTo: centerYAnchor),
        ] + extra)

        setAccessibilityElement(true)
        setAccessibilityLabel(status.label)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
