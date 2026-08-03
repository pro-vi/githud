import AppKit
import QuartzCore

/// One-shot, opacity-only ink fade — the ONLY kind of content animation the doctrine
/// sanctions (ink appears/disappears; it never stretches, travels fake distances, or
/// changes hue outside the critical flip). Shared by the WP-3d morph choreography
/// (HUDPanelController) and the WP-3x slot-morph pill (CollapsedPillView).
///
/// - Retargetable: `from` defaults to the layer's PRESENTATION opacity, so an
///   interrupted transition re-fades from wherever it visibly is (never a snap).
/// - `delay` + `.backwards` fill implement the ratified staggered windows (e.g. the
///   expand's pill-ink 0–100ms / header 80–200ms / body 120–220ms) without a second
///   animation group — one CABasicAnimation per fading view, self-removing.
/// - Idle-footprint: every fade is a finite one-shot; nothing repeats, nothing polls.
enum InkFade {
    static func run(_ view: NSView, from: Float? = nil, to target: Float,
                    delay: TimeInterval, duration: TimeInterval,
                    curve: CAMediaTimingFunction) {
        view.wantsLayer = true
        guard let layer = view.layer else { return }
        let start = from ?? layer.presentation()?.opacity ?? layer.opacity
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = start
        fade.toValue = target
        fade.duration = duration
        fade.timingFunction = curve
        fade.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
        fade.fillMode = .backwards
        layer.opacity = target   // model value = destination, so it sticks after the animation
        layer.add(fade, forKey: "inkFade")
    }
}
