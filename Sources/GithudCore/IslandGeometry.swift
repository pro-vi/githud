import CoreGraphics

/// Where the island sits and how big it is — the load-bearing placement math,
/// kept pure (CoreGraphics only, no AppKit) so it is unit-testable headlessly.
/// The app shell feeds it a screen's `visibleFrame`; it never touches a window.
public enum IslandSizeClass: String, Sendable {
    case collapsed, expanded, other
}

public struct IslandGeometry: Sendable {
    /// Collapsed island size class (≈ 280×42). Dynamic-Island-style pill.
    public static let collapsedSize = CGSize(width: 280, height: 42)
    /// Expanded island size class (≈ 520×120). Lands when hover-expand is wired.
    public static let expandedSize = CGSize(width: 520, height: 120)
    /// Per-lane scroll-pane height cap. A lane ("Needs you" / "Your PRs") grows to fit its
    /// content up to this, then scrolls its overflow in place. The island as a whole is
    /// REACTIVE — it sizes to the sum of its lanes (no dead space when a lane is short), while
    /// this cap bounds how tall one busy lane can push the panel. Clamped to the screen.
    public static let perPaneMaxHeight: CGFloat = 240
    /// Gap between the menu bar and the top of the island.
    public static let menuBarGap: CGFloat = 8

    /// Top-center placement just under the menu bar, in the screen's
    /// `visibleFrame` (AppKit bottom-left coordinate space, so `maxY` is the top).
    public static func collapsedFrame(in visibleFrame: CGRect) -> CGRect {
        frame(size: collapsedSize, in: visibleFrame)
    }

    public static func frame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let x = visibleFrame.midX - size.width / 2
        let y = visibleFrame.maxY - size.height - menuBarGap
        return CGRect(x: x, y: y, width: size.width, height: size.height)
    }

    /// Classify a size into the island's known classes (tolerant). Mirrors the
    /// `window-probe.swift` classifier so the on-screen window and the intended
    /// geometry can be cross-checked.
    public static func sizeClass(of size: CGSize) -> IslandSizeClass {
        func near(_ a: CGFloat, _ b: CGFloat, _ tol: CGFloat) -> Bool { abs(a - b) <= tol }
        if near(size.width, 280, 60), near(size.height, 42, 24) { return .collapsed }
        if near(size.width, 520, 80), near(size.height, 130, 70) { return .expanded }
        return .other
    }
}
