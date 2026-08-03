import AppKit
import Carbon.HIToolbox

/// Global summon hotkey — WP-6h. Registers **⌃⌥G** ("githud") so the island can be
/// raised/expanded from anywhere, with NO key status and NO Input Monitoring permission.
///
/// Mechanism: the Carbon Event Manager's `RegisterEventHotKey` + `InstallEventHandler`
/// (`kEventClassKeyboard` / `kEventHotKeyPressed`) — NOT
/// `NSEvent.addGlobalMonitorForEvents(.keyDown)`. That AppKit path requires the user to
/// grant Input Monitoring (a TCC prompt) and observes EVERY keystroke system-wide just to
/// filter for one chord. `RegisterEventHotKey` needs no permission at all, the OS itself
/// dispatches only the ONE registered chord, and — unlike an `NSEvent` global monitor,
/// which is scoped to apps that are frontmost-eligible in the ways AppKit expects — it
/// fires reliably for a plain `.accessory` app with no windows ever becoming key. Carbon
/// HIToolbox is marked deprecated in the headers, but it remains, to date, THE sanctioned,
/// fully-functional mechanism for a permissionless global hotkey on macOS; there is no
/// AppKit/SwiftUI replacement. (See DESIGN DIRECTIVES / WP-6h.)
///
/// `focus-non-theft`: this file never calls `makeKey`/`makeKeyAndOrderFront`/`activate` —
/// registration only arms a system-level chord notification; the actual summon action
/// (below, via the injected `onSummon` closure) routes through `HUDPanelController`'s
/// existing `show()`/`setExpanded`/`toggleExpand()`, which already only ever
/// `orderFrontRegardless`s the panel.
/// `idle-footprint`: no timer, no polling — this is a one-time OS registration that then
/// sits silent until the OS itself delivers the one matching key-down system-wide.
final class SummonHotkey {
    /// ⌃⌥G — hardcoded default chord. A later Settings surface may make this
    /// user-configurable; that is explicitly OUT of scope here (no preferences surface,
    /// low collision risk for control+option+G on a menu-bar utility).
    private static let keyCode = UInt32(kVK_ANSI_G)
    private static let modifiers = UInt32(controlKey | optionKey)
    /// Four-char signature ('gthd') identifying OUR hotkey registration among any other
    /// app's — required by the Carbon Event Manager API shape, not user-visible.
    private static let signature: OSType = 0x67746864
    private static let hotKeyID = EventHotKeyID(signature: signature, id: 1)

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    /// Fired on the main thread when the chord is pressed. Externally owned, like
    /// `HUDPanelController.onGearTap`/`screenProvider` — AppDelegate wires this to the HUD
    /// controller's existing show/expand paths; this file invents no new panel behavior.
    private let onSummon: () -> Void

    init(onSummon: @escaping () -> Void) {
        self.onSummon = onSummon
        register()
    }

    private func register() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let hotkey = Unmanaged<SummonHotkey>.fromOpaque(userData).takeUnretainedValue()
                var receivedID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    eventRef, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                    nil, MemoryLayout<EventHotKeyID>.size, nil, &receivedID
                )
                guard paramStatus == noErr,
                      receivedID.signature == SummonHotkey.signature,
                      receivedID.id == SummonHotkey.hotKeyID.id
                else { return noErr }
                // Carbon delivers this on the main thread already (no dedicated Carbon
                // event thread in this app), but hop defensively anyway — cheap, and it
                // makes the "always main thread" contract explicit rather than assumed.
                if Thread.isMainThread {
                    hotkey.onSummon()
                } else {
                    DispatchQueue.main.async { hotkey.onSummon() }
                }
                return noErr
            },
            1, &eventType, selfPtr, &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            log("InstallEventHandler failed, OSStatus \(handlerStatus) — hotkey disabled, menu/click paths unaffected")
            return
        }

        let registerStatus = RegisterEventHotKey(
            Self.keyCode, Self.modifiers, Self.hotKeyID,
            GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registerStatus == noErr else {
            // Most likely cause: another app already owns ⌃⌥G. Degrade SILENTLY — no
            // alert, no retry-with-a-different-chord — the status-item click and gear
            // menu still summon the island fine either way.
            log("RegisterEventHotKey failed, OSStatus \(registerStatus) — hotkey disabled, menu/click paths unaffected")
            return
        }
        log("registered ⌃⌥G, OSStatus \(registerStatus)")
    }

    private func log(_ message: String) {
        if ProcessInfo.processInfo.environment["GITHUD_DEBUG"] != nil {
            FileHandle.standardError.write(Data("▸ hotkey: \(message)\n".utf8))
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }
}
