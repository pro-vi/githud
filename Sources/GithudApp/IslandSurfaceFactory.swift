import AppKit

/// Builds the themed island SURFACE (WP-6a extraction) — the theme→view construction that
/// used to live in `HUDPanelController.buildSurface()`. Pure construction: given the theme +
/// the two a11y flags + geometry, it returns a ready surface view (vibrant material or solid
/// brand color, rounded mask, hairline border, optional static grain). The CONTROLLER keeps
/// everything lifecycle: when to rebuild, the scroll-offset stash, content swaps, panel
/// attachment, and render coordination.
///
/// The appearance-change hook is INSTALLED here (once per built surface, exactly as before)
/// but OWNED by the caller: the controller passes its `handleAppearanceChange` closure, which
/// re-bakes colors IN PLACE via `rebakeAppearanceColors` — never by rebuilding the surface.
/// That preserves WP-5i's in-place re-bake design: a rebuild inside the hook would reinstall
/// this very hook on a freshly-attached view (a real self-trigger risk it deliberately avoids).
enum IslandSurfaceFactory {
    /// Build a fresh island surface from the current theme + a11y state.
    /// - `theme` is the STORED theme; the two flags fold in the a11y coercions exactly as the
    ///   controller's old `buildSurface()` did — `effectiveSurface(reduceTransparency:)` picks
    ///   vibrant vs solid, `effectiveTheme(increaseContrast:)` supplies the border color, and
    ///   `Theme.borderWidth(increaseContrast:)` the 0.5→1px promotion.
    /// - `onAppearanceChange` fires on a REAL system appearance change (Light↔Dark, accent) —
    ///   see `IslandEffectView`/`IslandSolidView`. The caller re-bakes in place; see above.
    static func makeSurface(theme: Theme,
                            reduceTransparency: Bool,
                            increaseContrast: Bool,
                            size: NSSize,
                            cornerRadius: CGFloat,
                            onAppearanceChange: @escaping () -> Void) -> NSView {
        let view: NSView
        switch theme.effectiveSurface(reduceTransparency: reduceTransparency) {
        case .vibrant(let material):
            let effect = IslandEffectView()   // no window-drag, accepts first mouse (non-key panel)
            effect.material = material      // .popover etc — "alive", not a flat slab
            effect.blendingMode = .behindWindow
            effect.state = .active
            // Clip the VIBRANCY to the rounded shape. Layer cornerRadius/masksToBounds do
            // NOT clip an NSVisualEffectView's material (a private backdrop layer draws it),
            // so without this the translucent material bleeds to the rectangular window
            // bounds — reading as a box around the rounded border. `maskImage` is the
            // documented fix, and it also makes the window's drop shadow follow the corners.
            effect.maskImage = roundedMaskImage(cornerRadius: cornerRadius)
            effect.onAppearanceChange = onAppearanceChange
            view = effect
        case .solid(let color):
            let solid = IslandSolidView()     // same non-key event behavior as the vibrant surface
            solid.wantsLayer = true
            solid.layer?.backgroundColor = color.cgColor
            solid.onAppearanceChange = onAppearanceChange
            view = solid
        }
        view.frame = NSRect(origin: .zero, size: size)
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = Theme.borderWidth(increaseContrast: increaseContrast)   // 0.5 default; 1px + opaque under Increase Contrast
        view.layer?.borderColor = theme.effectiveTheme(increaseContrast: increaseContrast).border.cgColor
        if theme.grainOpacity > 0 {
            let grain = GrainView(opacity: theme.grainOpacity)
            grain.frame = view.bounds
            view.addSubview(grain)         // below content (content added later in present())
        }
        return view
    }

    /// Re-resolve the surface's baked `CGColor`s (border, solid-surface fill) IN PLACE on a
    /// REAL system appearance change (Light↔Dark, accent). `CALayer` color properties are
    /// `CGColor`, a fixed RGBA snapshot that does NOT auto-track a dynamic `NSColor` the way
    /// `textColor`/`contentTintColor` do, so a bake made under the previous appearance would
    /// otherwise sit stale until some UNRELATED render happened to occur. Applies to the
    /// CURRENT surface — never builds a new one (see the self-trigger note on the type).
    static func rebakeAppearanceColors(on surface: NSView,
                                       theme: Theme,
                                       reduceTransparency: Bool,
                                       increaseContrast: Bool) {
        surface.layer?.borderColor = theme.effectiveTheme(increaseContrast: increaseContrast).border.cgColor
        if case .solid(let color) = theme.effectiveSurface(reduceTransparency: reduceTransparency) {
            surface.layer?.backgroundColor = color.cgColor
        }
    }

    /// A resizable rounded-rect mask (black-filled, stretchable cap insets) for shaping an
    /// `NSVisualEffectView`. Stretches with the island across content swaps, keeping a
    /// constant corner radius. Black = opaque/keep, transparent = clip.
    static func roundedMaskImage(cornerRadius r: CGFloat) -> NSImage {
        let edge = r * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
