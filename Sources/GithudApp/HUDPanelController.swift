import AppKit
import GithudCore

/// Positions, shows, and renders the HUD overlay panel and its glass island.
///
/// WP-6a shape: this controller is LIFECYCLE + RENDER COORDINATION only. All app state
/// (rows, pulse, freshness, preferences, theme id, a11y flags, message) lives in the
/// injected `AppModel` — AppDelegate mutates it, this controller observes and renders.
/// Theme→surface construction lives in `IslandSurfaceFactory`. What stays here: the
/// panel itself, visibility/expansion (with their side-effectful transitions — the
/// click-away monitor and the `onExpandChange` seam), the render coalescer, content
/// swaps, screen anchoring, and the scroll-offset stash across surface rebuilds.
///
/// WP-3d adds THE MORPH (ratified `morph-hand-off-header`): expand/collapse is one
/// continuous surface animating on a single curve while the pill's top band crossfades
/// into the header in place — plus the hide tuck / show settle. WP-3x adds the
/// slot-morph pill (ratified `slot-morph-inkfocus`, G-crossfade half only): cross-state
/// pill changes fade ONLY the changed cell(s); equal-digit ticks stay at today's 0ms.
/// Every path collapses to today's hard cut under Reduce Motion.
///
/// Pressures honored:
/// - `native-feel`  → vibrancy is an AppKit `NSVisualEffectView`, not SwiftUI `.material`.
/// - `focus-non-theft` → shown via `orderFrontRegardless`, never `makeKeyAndOrderFront`;
///   the morph never makes the panel key — it animates frame + ink opacity only. The ONE
///   ratified exception (WP-4d): `beginKeySession`/`endKeySession` scope the
///   `keySessionActive` relaxation to the user's own click into the ledger card's field,
///   reset at every teardown choke point; the app never activates.
/// - `idle-footprint` → no timers / `CADisplayLink`; the island is static at rest. Every
///   animation here is a finite one-shot mapped 1:1 to a user action (summon, collapse,
///   hide, show) or a real data change (the slot-morph's changed cell) — nothing repeats.
/// - `attention-non-theft` → motion maps 1:1 to the click/chord or the changed fact;
///   the slot-morph invariant ("no motion where no fact changed") lives in `PillMorph`.
final class HUDPanelController {
    private let model: AppModel
    private let panel: HUDPanel
    private var surface: NSView!             // the themed island container (vibrant or solid)
    private var contentView: NSView?         // the current content (radar/pill/message), swapped on render
    /// Read externally (the unified menu's "Hide island"/"Show island" item reflects this —
    /// WP-5i) so the checkmark/title can never drift from the panel's real state; only this
    /// controller may WRITE it (via `show()`/`hide()`).
    private(set) var isVisible = false

    /// Collapsed island size class (≈ 280×42). Geometry lives in `GithudCore`.
    private let collapsedSize = IslandGeometry.collapsedSize
    private let islandCornerRadius: CGFloat = 14

    init(model: AppModel) {
        self.model = model
        let contentRect = NSRect(origin: .zero, size: collapsedSize)
        panel = HUDPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: 1, height: 1)
        panel.maxSize = NSSize(width: 4000, height: 4000)   // don't clamp expand → collapse width
        // WP-4d key moment (fix round): AppKit's DESIGNED palette mechanism. With this set,
        // the panel becomes key ONLY when the clicked view answers `needsPanelToBecomeKey`
        // (the token field, while enabled) — the click→key decision happens in sendEvent,
        // where it actually lives, instead of a structurally-late mouseDown makeKey().
        // `canBecomeKey` (gated on `keySessionActive`) still walls it off entirely unless a
        // field-bearing card is showing.
        panel.becomesKeyOnlyIfNeeded = true

        buildSurface()                                       // themed island surface + panel.contentView

        // The focus cue follows REAL key status (fix round: painting it off the attempt let
        // the accent border claim a focus that may not exist). becomeKey → cue on.
        panel.onDidBecomeKey = { [weak self] in
            (self?.contentView as? LedgerCardView)?.setFieldFocused(true)
        }
        // Click-away during a key moment: another app's window takes key, AppKit resigns
        // ours. Two jobs: retire the cue, and DETACH the field editor — while it overlays
        // the field, a return click would hit-test to the editor (an NSTextView) and the
        // field could never be re-entered (fix round BLOCKER 2: the secret then routes to
        // the other app). With the editor detached, the return click lands on the field
        // itself and `becomesKeyOnlyIfNeeded` re-acquires key — eligibility persists for
        // the whole life of the card.
        panel.onDidResignKey = { [weak self] in
            guard let self else { return }
            (self.contentView as? LedgerCardView)?.setFieldFocused(false)
            self.panel.makeFirstResponder(nil)
            // WP-6k: losing key MID-list-session (a browser open off a row click, a
            // click into another app's window) ends the session — a bar + hint that
            // outlive the panel's keys would claim keystrokes that now land elsewhere.
            // No-op for the session's own order-out pulse (the flag is already nil) and
            // for card moments (the flag was never set).
            self.endKeySummonSession()
        }

        // WP-6k: list-session key routing + the VoiceOver focus mirror. Both are inert
        // outside a session (`keySelection == nil` → passthrough / nil).
        panel.onSessionKeyDown = { [weak self] event in self?.handleSessionKey(event) ?? false }
        panel.sessionFocusElement = { [weak self] in
            guard let self, self.keySelection != nil else { return nil }
            return (self.contentView as? IslandContentView)?.keyFocusedRowView()
        }

        // Render on model change — each change kind maps onto the SAME render path its old
        // direct setter used (see handle(_:)), so the model adds zero renders per event.
        model.addObserver { [weak self] change in self?.handle(change) }

        // Correct screen anchoring (WP-5i): re-clamp/reposition on a REAL screen-parameter
        // change (monitor connected/disconnected, resolution change, menu-bar height change,
        // Spaces/display arrangement) — a stale-anchored island could otherwise land on the
        // wrong monitor or orphan off-screen after such a change. Event-driven (fires only on
        // an actual system notification, never a timer — idle-footprint), and it goes through
        // the EXISTING coalesced render/present path (no new reposition mechanism): `present()`
        // already recomputes the frame origin from the current screen on every render.
        screenParamsObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.setNeedsRender()
        }
    }

    /// Map a model change onto the render path its OLD direct setter used — coalesced for
    /// poll-driven data (a changed poll's radar+pulse+freshness burst still collapses to ONE
    /// rebuild), immediate for user-visible must-feel-instant changes (theme switch, a11y
    /// flip, a setup/auth message). `.surfacePreferences` deliberately renders NOTHING: the
    /// H1 reason toggle's repaint arrives via the scheduler's recompute → fresh rows →
    /// `.radar`, exactly the two-step flow the direct wiring had.
    private func handle(_ change: AppModel.Change) {
        switch change {
        case .radar, .pulse, .inbound, .freshness, .pulsePreferences, .inboundPreferences, .pillStyle,
             .sweepFreshness, .lensPreferences, .selfLogin:
            // `.lensPreferences`/`.selfLogin` (owner lens): re-render from cached rows —
            // a fold/shape flip and the one-shot login resolution ride the same coalesced
            // path as the sibling pulse preferences.
            // `.pillStyle`: a deliberate vocabulary switch — the pill morphs to the new
            // shape (or the chooser card refreshes its radios), coalesced like a data change.
            // `.sweepFreshness` (D1, F-1): the sweep clock crossed fresh↔stale — the ONLY
            // guaranteed repaint for the inbound tier's stale prefix (a 304-ing poll clock,
            // an unchanged lane key, and a collapsed pill are all otherwise render-silent);
            // exactly one per crossing, coalesced here like every data change.
            setNeedsRender()   // coalesced with any sibling changes this runloop turn
        case .theme, .reduceTransparency, .increaseContrast:
            // Surface rebuild (material/border/grain are baked into the surface) + instant
            // re-render — a menu theme switch / a11y setting flip must apply immediately.
            buildSurface()
            renderNow()
        case .ledger:
            // The WP-4d ledger card is a state the user must see NOW → force visible +
            // immediate. Route the force-show through the SAME cancellation `show()` does, so a
            // card presented mid-hide-tuck can't be tucked away / ordered out under it (which
            // would leave isVisible==true with the panel off screen — the WP-5i menu lying).
            // Clearing (ledger == nil) re-renders without touching visibility — but it IS the
            // card's exit: the key moment ends at this teardown choke point, and when the
            // outgoing content is the card the render runs as the success morph — the card
            // becomes whatever the island now measures, on the WP-3d machinery. DELIBERATE
            // SPEC SUBSTITUTION (flagged for the decision record): D-card's handshake-ledger
            // text specs 320ms cubic-bezier(0.32,0.72,0,1); this reuses the ratified WP-3d
            // container-morph grammar instead (180ms collapse / 220ms expand, bezier
            // 0.2,0,0,1) so the product speaks ONE morph vocabulary — and inherits its
            // Reduce-Motion / hidden-panel hard-cut gates for free.
            if model.ledger != nil {
                isVisible = true
                cancelWindowHideFx()
                renderNow()
            } else {
                endKeySession()
                pendingMorph = contentView is LedgerCardView ? (expanded ? .expand : .collapse) : nil
                renderNow()
                pendingMorph = nil
            }
        case .pillStyleChooser:
            if model.pillStyleChooser != nil {
                // Show: must-appear on the gear click. Treat like an EXPAND so the click-away
                // monitor arms + the expand seam fires — the chooser IS dismissable (unlike the
                // must-see ledger). No key moment: the chooser render branch keeps
                // keySessionActive false (PillStyleChooser.takesKeyMoment == false).
                isVisible = true
                cancelWindowHideFx()
                let wasExpanded = expanded
                if !wasExpanded {
                    expanded = true
                    onExpandChange?(true)         // the seam (poll-now on expand)
                    updateClickAwayMonitor()      // arm click-away dismissal
                }
                pendingMorph = .expand   // pane arrivals ALWAYS animate (dogfood 2026-07-14)
                renderNow()
                pendingMorph = nil
            } else if model.lensChooser != nil || model.settingsCard != nil {
                // Pane navigation: another card already took the surface — animate the
                // swap on the WP-3d morph, stay expanded. Never a collapse.
                pendingMorph = .expand
                renderNow()
                pendingMorph = nil
            } else if pillCardBackToIsland {
                pillCardBackToIsland = false
                pendingMorph = .expand        // card → island, animated
                renderNow()
                pendingMorph = nil
            } else {
                // Dismiss (click-away / chevron / gear-again): collapse back to the pill.
                endKeySummonSession()
                let wasExpanded = expanded
                if wasExpanded {
                    expanded = false
                    onExpandChange?(false)
                    updateClickAwayMonitor()      // tear down the click-away monitor
                }
                pendingMorph = (contentView is PillStyleChooserView) ? .collapse : nil
                renderNow()
                pendingMorph = nil
            }
        case .lensChooser:
            // The owner-lens card (WP 2026-07-14-001) — same lifecycle as its pill-style
            // sibling: show-as-expand (click-away arms, expand seam fires, no key moment),
            // dismiss-as-collapse.
            if model.lensChooser != nil {
                isVisible = true
                cancelWindowHideFx()
                let wasExpanded = expanded
                if !wasExpanded {
                    expanded = true
                    onExpandChange?(true)
                    updateClickAwayMonitor()
                }
                pendingMorph = .expand   // pane arrivals ALWAYS animate (dogfood 2026-07-14)
                renderNow()
                pendingMorph = nil
            } else if model.pillStyleChooser != nil || model.settingsCard != nil {
                // Pane navigation — animate the swap, stay expanded.
                pendingMorph = .expand
                renderNow()
                pendingMorph = nil
            } else if lensCardBackToIsland {
                // "(back)": return to the expanded island (the eye's origin) — animated.
                lensCardBackToIsland = false
                pendingMorph = .expand
                renderNow()
                pendingMorph = nil
            } else {
                endKeySummonSession()
                let wasExpanded = expanded
                if wasExpanded {
                    expanded = false
                    onExpandChange?(false)
                    updateClickAwayMonitor()
                }
                pendingMorph = (contentView is LensChooserView) ? .collapse : nil
                renderNow()
                pendingMorph = nil
            }
        case .settingsCard:
            // Same lifecycle as its two card siblings: show-as-expand, dismiss-as-collapse,
            // "(back)" returns to the island.
            if model.settingsCard != nil {
                isVisible = true
                cancelWindowHideFx()
                let wasExpanded = expanded
                if !wasExpanded {
                    expanded = true
                    onExpandChange?(true)
                    updateClickAwayMonitor()
                }
                pendingMorph = .expand   // pane arrivals ALWAYS animate (dogfood 2026-07-14)
                renderNow()
                pendingMorph = nil
            } else if model.pillStyleChooser != nil || model.lensChooser != nil {
                // Pane navigation — animate the swap, stay expanded.
                pendingMorph = .expand
                renderNow()
                pendingMorph = nil
            } else if settingsBackToIsland {
                settingsBackToIsland = false
                pendingMorph = .expand        // card → island, animated
                renderNow()
                pendingMorph = nil
            } else {
                endKeySummonSession()
                let wasExpanded = expanded
                if wasExpanded {
                    expanded = false
                    onExpandChange?(false)
                    updateClickAwayMonitor()
                }
                pendingMorph = (contentView is SettingsCardView) ? .collapse : nil
                renderNow()
                pendingMorph = nil
            }
        case .surfacePreferences:
            // No island render — fresh H1 rows arrive via the scheduler's recompute →
            // `.radar` (the two-step flow). But the SETTINGS CARD shows the reason set
            // live: while it is up, a toggle re-renders the card in place.
            if model.settingsCard != nil { setNeedsRender() }
        }
    }

    /// (Re)build the island surface from the model's theme + a11y state via
    /// `IslandSurfaceFactory` — a vibrant `NSVisualEffectView` (translucent, picks up the
    /// desktop) or a solid layer-backed view (exact brand color), with the themed hairline
    /// border + an optional STATIC grain overlay. The grain is a sibling of the content (not
    /// removed by `present()`), so it survives content swaps. The appearance-change hook the
    /// factory installs re-bakes IN PLACE (see `handleAppearanceChange`) — never a rebuild.
    private func buildSurface() {
        // Stash the outgoing per-lane scroll offsets before the teardown below nils the
        // content — the immediately-following renderNow() consumes them, so a mid-read theme /
        // Reduce-Transparency switch keeps the reader's place (nil when not the expanded island).
        pendingScrollOffsets = (contentView as? IslandContentView)?.scrollOffsets()
        // Same contract for the WP-3d′ open peeks — a theme switch mid-read must not
        // silently re-truncate the row the user just opened.
        pendingPeekStash = (contentView as? IslandContentView)?.peekStash()
        // Same contract for the ledger card's in-progress token text (fix round, finding 9):
        // a theme/a11y surface rebuild would otherwise destroy a half-pasted secret. Held
        // only across the synchronous buildSurface()→renderNow() pair, never logged.
        pendingFieldText = (contentView as? LedgerCardView)?.currentFieldText()
        surface = IslandSurfaceFactory.makeSurface(
            theme: .named(model.themeID),
            reduceTransparency: model.reduceTransparency,
            increaseContrast: model.increaseContrast,
            size: collapsedSize,
            cornerRadius: islandCornerRadius,
            onAppearanceChange: { [weak self] in self?.handleAppearanceChange() })
        contentView = nil
        panel.contentView = surface
    }

    /// Re-resolve every baked `CGColor` (border, solid-surface fill) on a REAL system
    /// appearance change (Light↔Dark, accent) — see `IslandEffectView`/`IslandSolidView`'s
    /// `onAppearanceChange`. `CALayer` color properties are `CGColor`, a fixed RGBA snapshot
    /// that does NOT auto-track a dynamic `NSColor` the way `textColor`/`contentTintColor` do,
    /// so a bake made under the previous appearance would otherwise sit stale until some
    /// UNRELATED render happened to occur. Re-applies IN PLACE on the CURRENT surface via the
    /// factory (never `buildSurface()`, which would reinstall this very hook on a
    /// freshly-attached view — a real self-trigger risk); then re-renders the content through
    /// the EXISTING coalesced path so its own baked colors (the count badge's accent)
    /// re-resolve too. No new render mechanism, per WP-5i's contract.
    private func handleAppearanceChange() {
        IslandSurfaceFactory.rebakeAppearanceColors(
            on: surface,
            theme: .named(model.themeID),
            reduceTransparency: model.reduceTransparency,
            increaseContrast: model.increaseContrast)
        setNeedsRender()
    }

    /// The theme actually handed to the content — the model's stored theme with Increase
    /// Contrast's rendering-only adjustments folded in (border opacity, hover fill, tertiary
    /// ink). Every color the content draws reads through this ONE call site, so a11y state
    /// can never be forgotten at a new call site. (The surface applies the same fold inside
    /// `IslandSurfaceFactory`.)
    private func effectiveTheme() -> Theme {
        Theme.named(model.themeID).effectiveTheme(increaseContrast: model.increaseContrast)
    }

    private var expanded = false
    /// Tapping the in-island gear → show the unified gear menu (Surface + Theme + Quit)
    /// anchored to the gear. Externally owned (AppDelegate wires it to the status item's menu).
    var onGearTap: ((NSView) -> Void)?
    /// WP 2026-07-12-001: the island's plain-words caption/hide controls flip the SAME
    /// preferences the gear items flip. Externally owned like `onGearTap` — AppDelegate wires
    /// these to the EXACT toggle funcs the gear actions call (`toggleShowStale` /
    /// `toggleShowHeldBackInbound`), so the reveal re-renders + eases on the existing
    /// `Change.pulsePreferences`/`inboundPreferences` machinery (no new state, no new motion).
    var onToggleStale: (() -> Void)?
    var onToggleHeldBackInbound: (() -> Void)?
    var onToggleJustCleared: (() -> Void)?
    /// WP 2026-07-12-001 addendum: the Drafts (hide) control flips the same `showDrafts` pref
    /// the gear item flips — externally owned like its two siblings; AppDelegate wires it to
    /// the exact `toggleShowDrafts` func the gear action calls (one truth, honest checkmark).
    var onToggleDrafts: (() -> Void)?
    /// Owner lens (WP 2026-07-14-001): a folded ledger line's click unfolds its owner —
    /// externally owned like its caption siblings; AppDelegate wires it to the exact
    /// `toggleFoldedOwner` func the lens card and gear call (three handles, one truth).
    var onToggleFoldedOwner: ((String) -> Void)?
    /// The lens eye's (and the merged "elsewhere" line's) destination — the lens card.
    var onOpenLensCard: (() -> Void)?
    /// The ledger card's token submission (WP-4d) — externally owned, like `onGearTap`:
    /// AppDelegate wires it to `submitToken` (the WP-4e intake wire this card was built for).
    var onTokenSubmit: ((String) -> Void)?
    /// The pill-style chooser's selection (WP 2026-07-10-001) — externally owned: AppDelegate
    /// persists it + applies via `model.setPillStyle`. The card stays up; the pill morphs on
    /// dismiss (the selection also refreshes the card's radios via the re-render).
    var onPillStyleSelect: ((PillStyle) -> Void)?
    /// The lens card's two toggles (WP 2026-07-14-001) — externally owned: AppDelegate
    /// routes them to the SAME `toggleFoldedOwner`/`toggleGroupByOwner` funcs every other
    /// handle uses; the card refreshes in place via the `.lensPreferences` re-render.
    var onLensToggleOwner: ((String) -> Void)?
    var onLensToggleGroup: (() -> Void)?
    /// The card's drag-reorder drop (dogfood 2026-07-14) — AppDelegate persists + applies.
    var onLensReorder: (([String]) -> Void)?
    /// Dismiss the lens card (click-away / chevron collapse) — AppDelegate wires it to
    /// `model.clearLensChooser()` (the pill-chooser dismissal twin).
    var onDismissLensChooser: (() -> Void)?
    /// Card "(back)" routing (dogfood 2026-07-14): every pane carries a back button and
    /// BACK RETURNS WHERE YOU CAME FROM — AppDelegate owns the provenance (a door from
    /// Settings goes back to Settings; the eye goes back to the island), these externally
    /// owned closures carry the press out, and the `return…ToIsland()` funcs below are
    /// the island leg (the flag makes the NEXT dismissal render instead of collapse).
    /// Click-away keeps meaning "leave entirely" on every pane.
    var onLensBack: (() -> Void)?
    var onPillBack: (() -> Void)?
    var onSettingsBack: (() -> Void)?
    private var lensCardBackToIsland = false
    func returnLensCardToIsland() {
        lensCardBackToIsland = true
        onDismissLensChooser?()
    }
    private var pillCardBackToIsland = false
    func returnPillCardToIsland() {
        pillCardBackToIsland = true
        onDismissPillStyleChooser?()
    }
    func returnSettingsCardToIsland() {
        settingsBackToIsland = true
        onDismissSettingsCard?()
    }

    /// Settings card (mark-and-settings option B, dogfood-ratified 2026-07-14) — the
    /// gear's destination; every config the dropdown held. Same externally-owned shape
    /// as the lens card's closures.
    var onSettingsToggleReason: ((String) -> Void)?
    var onSettingsSelectTheme: ((ThemeID) -> Void)?
    var onSettingsToggleLaunch: (() -> Void)?
    var onSettingsOpenPillStyle: (() -> Void)?
    var onSettingsOpenLens: (() -> Void)?
    var onDismissSettingsCard: (() -> Void)?
    /// Live launch-at-login status (SMAppService), read fresh per render — never cached.
    var currentLaunchAtLogin: (() -> Bool)?
    private var settingsBackToIsland = false
    /// Dismiss the chooser card (click-away / chevron collapse) — AppDelegate wires it to
    /// `model.clearPillStyleChooser`, whose notification drives the collapse-back morph.
    var onDismissPillStyleChooser: (() -> Void)?
    /// Fired exactly once per real collapsed⇄expanded transition (inside `setExpanded`'s
    /// change guard). Wired by AppDelegate to the poll scheduler (poll-now on expand;
    /// age-bucket re-renders only while the ages are visible).
    var onExpandChange: ((Bool) -> Void)?
    /// Correct screen anchoring (WP-5i): externally owned, like `onGearTap` — AppDelegate
    /// wires this to the status item's screen (`statusItem.button?.window?.screen`), falling
    /// back to the screen under the mouse, then `NSScreen.main`. `nil` (unset, e.g. in a
    /// fixture/preview context) falls back to `NSScreen.main` alone via `resolvedScreen()`.
    var screenProvider: (() -> NSScreen?)?
    /// Live for the controller's whole lifetime (removed in `deinit`) — a real screen-topology
    /// change is rare and event-driven, so this is not a permanent-timer idle-footprint concern.
    private var screenParamsObserver: NSObjectProtocol?

    /// Coalescing: `render()` builds a brand-new content view and tears down the old one, so a
    /// burst of data changes in one runloop turn (a changed poll fires radar + pulse +
    /// freshness back-to-back) must NOT rebuild the island 2–3×. Data changes mark the island
    /// dirty and schedule ONE next-runloop flush; user actions (expand, theme) flush immediately.
    /// No repeating timer — a one-shot `DispatchQueue.main.async` per burst (idle-footprint clean).
    private var renderScheduled = false

    /// A passive global mouse-down monitor, live ONLY while expanded (click-away collapse).
    /// `nil` while collapsed — never a permanent monitor (idle-footprint).
    private var clickAwayMonitor: Any?

    /// Scroll offsets stashed by `buildSurface()`: a surface rebuild (theme switch /
    /// Reduce-Transparency) nils `contentView` BEFORE its `renderNow()` runs, so render()'s
    /// normal capture would read nil and both lanes would jump to top mid-read (the unified
    /// gear menu makes a theme switch reachable while scrolled). Consumed one-shot by the
    /// next render; `buildSurface()`+`renderNow()` are synchronous, so it can never go stale.
    private var pendingScrollOffsets: IslandContentView.ScrollOffsets?

    /// The ledger card's in-progress field text, stashed by `buildSurface()` exactly like
    /// the scroll offsets (fix round, finding 9): a theme / Increase-Contrast /
    /// Reduce-Transparency rebuild mid-entry must not destroy a half-typed token. One-shot,
    /// consumed (and cleared) by the very next render; never logged, never persisted.
    private var pendingFieldText: String?

    /// WP-3d′ peek stash, `pendingScrollOffsets`' sibling: open peeks survive data-driven
    /// rebuilds within one expanded session (captured from the outgoing island, fed into
    /// the next island's init — where a changed row signature drops its peek honestly).
    /// Reset-on-collapse is structural: only the expanded render path carries it forward,
    /// so a fresh expand from the pill always opens clean. This slot covers the surface
    /// rebuilds (theme / a11y flips) that tear the content down before render() runs.
    private var pendingPeekStash: PeekStash?

    // MARK: - WP-3d/3x animation state

    /// The container morph (expand ⇄ collapse), per the ratified `morph-hand-off-header`.
    private enum MorphKind { case expand, collapse }
    /// Set by `setExpanded` for exactly the one render it triggers — a data render can
    /// never accidentally run a container morph.
    private var pendingMorph: MorphKind?
    /// The outgoing content still crossfading during a container morph (the pill ink that
    /// present() used to remove synchronously — keeping it alive through flight is the
    /// spec's main build delta). Removed in the morph's completion, or immediately when a
    /// morph is retargeted / superseded by a hard render.
    private var outgoingMorphView: NSView?
    /// Guards stale morph completion handlers after an interruption (retarget).
    private var morphGeneration = 0
    /// Guards stale hide-tuck / show-settle completions (the whole-window fades).
    private var windowFxGeneration = 0
    /// True while a whole-window fade (hide tuck or show settle) is animating the panel's
    /// frame + alpha. A hard render must not partially fight it (see `renderNow`): during a
    /// hide tuck, snapping the frame while the alpha keeps fading would pop the pill back down
    /// mid-dissolve. Reset by the fade's completion or by `cancelWindowHideFx()`.
    private var windowFxInFlight = false
    /// Hide-while-expanded is a two-beat sequence (ratified): the 180ms collapse morph
    /// FIRST, then the 140ms upward tuck. This flag carries the tuck across the collapse.
    private var pendingHideTuck = false
    /// WP-3x rule (e): one transition per poll burst — a second change landing mid-fade
    /// jumps to the end state (the hard-swap path) instead of stacking animations.
    private var pillFadeInFlight = false
    /// The fingerprint of the pill currently on screen (nil when the island/message is
    /// showing) — `PillMorph.plan(from:to:)` diffs against it. See `GithudCore.PillMorph`
    /// for the transition rules and the written invariant.
    private var lastPillFingerprint: PillMorph.Fingerprint?

    /// Reduce Motion (a11y): EVERY group below is skipped — expand/collapse/hide/show and
    /// the slot-morph all collapse to today's hard cut (same check as the hover fade,
    /// HUDPanel.setHoverBackground).
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Show the island (collapsed by default — ambient, not a persistent guilt-list).
    /// From hidden, the pill settles in: order front at opacity 0, then fade 0→1 with an
    /// 8px downward settle over 140ms — the reverse of the hide tuck (motion maps 1:1 to
    /// the user's own summon). Reduce Motion → plain orderFront, exactly today.
    func show() {
        let wasOnScreen = panel.isVisible
        cancelWindowHideFx()   // a re-assertion of visibility beats any hide-in-flight choreography
        isVisible = true
        renderNow()   // a launch/summon action → render immediately (isVisible now true → orders front)
        if !wasOnScreen, !reduceMotion, panel.isVisible {
            runShowSettle()
        }
    }

    /// Neutralize any hide-in-flight window choreography so a re-assertion of visibility — an
    /// explicit `show()`/summon, or a must-see-NOW auth/setup card (`handle(.ledger)`) —
    /// always wins over a running (or pending) hide tuck. Without this a card presented during
    /// the 140ms tuck is ordered out ~140ms later while `isVisible` stays true (the WP-5i menu
    /// checkmark would then lie), and a summon lands the panel stranded at alpha≈0.
    ///
    /// Three moves, mirroring what a clean show needs: (1) drop `pendingHideTuck` so a hard
    /// render can't consume it and tuck the just-presented card; (2) bump `windowFxGeneration`
    /// so a running tuck's completion (which would `orderOut`) is silenced; (3) SUPERSEDE the
    /// in-flight window alpha animation with a 0-duration animator group — a *direct*
    /// `alphaValue` set does NOT retarget a running NSWindow animator (the exact AppKit contract
    /// `snapPanelFrame` already handles for the frame), so without this the tuck's alpha
    /// animation keeps driving to 0 and the panel is ordered-front but invisible.
    private func cancelWindowHideFx() {
        pendingHideTuck = false
        windowFxGeneration += 1
        windowFxInFlight = false
        snapPanelAlpha(1)
    }

    /// Hide the island entirely (the seam WP-5i's Hide will call). A hidden island is a
    /// COLLAPSED island: hiding funnels through `setExpanded(false)`, so the click-away
    /// monitor is removed and `onExpandChange(false)` fires exactly once — and the change
    /// guard makes hide-while-collapsed skip the collapse work (no spurious seam fire).
    /// `isVisible` flips false FIRST so no render during the flight can order the panel
    /// back front; the collapsed pill still renders (hidden) so a later `show()` opens coherent.
    ///
    /// Ratified choreography: if expanded, the 180ms collapse morph runs FIRST, then the
    /// pill tucks 8px upward under the menu bar it hangs from, fading over 140ms — the
    /// signal now lives only in the static status-item glyph (the handle back; no glyph
    /// change, no flash — attention-non-theft). Reduce Motion → today's instant orderOut.
    func hide() {
        endKeySummonSession()   // WP-6k: a hidden island cannot hold a list session (choke point)
        endKeySession()   // a hidden card cannot hold a key moment (teardown choke point)
        isVisible = false
        guard !reduceMotion, panel.isVisible else {
            panel.orderOut(nil)
            setExpanded(false)
            return
        }
        if expanded {
            pendingHideTuck = true
            setExpanded(false)      // the 180ms collapse morph; its completion runs the tuck
        } else {
            runHideTuck()
        }
    }

    // MARK: - render coalescing

    /// Data-driven update: mark the island dirty and schedule EXACTLY ONE render on the next
    /// runloop turn. Any further changes this turn collapse into the same flush (the guard makes
    /// the burst idempotent) — so a changed poll's radar + pulse + freshness, all delivered
    /// in one main-queue block, produce a single teardown/rebuild instead of two or three.
    private func setNeedsRender() {
        guard !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.renderScheduled else { return }   // superseded by an immediate render → skip
            self.renderNow()
        }
    }

    /// Immediate render — for user-initiated changes (expand/collapse, theme switch, first show)
    /// that must feel instant. Supersedes any pending coalesced render so the burst never
    /// double-rebuilds. `orderFrontRegardless` (never `makeKeyAndOrderFront`) only when visible.
    private func renderNow() {
        renderScheduled = false
        // A hide tuck owns the window (frame + alpha animating to hidden). A data render that
        // is NOT re-asserting visibility must not fight it: the hard cut would snapPanelFrame
        // the pill back to rest while the tuck's alpha keeps fading to 0 (the split-supersede
        // glitch — frame pops, ink dissolves). The panel is about to orderOut; show() and the
        // message force-show both re-render fresh (and clear windowFxInFlight first), so nothing
        // is lost by letting the tuck finish. (windowFxInFlight && !isVisible ⇔ a hide tuck.)
        if windowFxInFlight, !isVisible { return }
        render()
        if isVisible { panel.orderFrontRegardless() }
    }

    // MARK: - WP-6k — the ⌃⌥G scoped key session (the list half of `keySessionActive`)

    /// THE session flag: non-nil ⇔ a ⌃⌥G list session is live. Selection decisions are
    /// the pure `GithudCore.KeySelection`; the island view just paints `selectedID`.
    /// Eligibility (`panel.keySessionActive`) derives from this at render() exactly as
    /// the WP-4d card gate derives from card presence — and the flag dies at the same
    /// choke points that audit walked: `setExpanded` (esc/⏎/second-⌃⌥G/click-away/
    /// chevron all funnel a collapse through it), `hide()`, render()'s card branch (a
    /// force-rendered card takes the surface), render()'s collapsed branch (defensive),
    /// and the panel's own key LOSS (`onDidResignKey` — a bar that outlives its keys
    /// would lie about where keystrokes land).
    private var keySelection: KeySelection?

    /// Begin the list session. The ⌃⌥G summon path (AppDelegate) is the ONLY caller —
    /// mouse paths (pill click, status-item click, "Show island") never reach this, so
    /// the F8 boundary is structural. No-ops unless the EXPANDED island is really the
    /// surface: with a ledger card up, ⌃⌥G keeps today's WP-4d behavior (force-shown
    /// card, no list session — there is no list). Acquisition is `makeKey()` only —
    /// never `makeKeyAndOrderFront`, never `NSApp.activate`: the app stays `.accessory`,
    /// the foreground app keeps its menu bar, and key snaps back to it on resign
    /// because githud never activated (the Spotlight pattern, same as WP-4d).
    func beginKeySummonSession() {
        guard expanded, isVisible, model.ledger == nil,
              let island = contentView as? IslandContentView else { return }
        if keySelection == nil {
            keySelection = KeySelection(ids: KeySession.actionableIDs(
                radar: model.radarRows, pulse: model.pulseRows,
                showDrafts: model.pulsePreferences.showDrafts,
                showStale: model.pulsePreferences.showStale,
                inbound: model.inboundRows,
                showHeldBackInbound: model.inboundPreferences.showHeldBack,
                lens: model.lensPreferences))   // folded rows are off-screen → never in the walk
        }
        panel.keySessionActive = true            // eligibility flips with the session
        island.setKeySessionHint(true)           // session-only chrome
        island.setKeyFocus(id: keySelection?.selectedID)   // initial selection = first actionable row
        panel.makeKey()
        // Chrome follows REAL key state, not the attempt (the WP-4d fix-round rule: a
        // "keys land here" hint wired to nothing is a fabricated interaction state).
        // If the window server declined key (e.g. a secure-input session elsewhere),
        // retire everything now — no `didResignKey` will ever come to do it, because
        // key was never gained. Review panel: trust minor 1 / AppKit (c).
        guard panel.isKeyWindow else {
            debugKeyLog("session begin REFUSED — makeKey() did not take (secure input?)")
            endKeySummonSession()
            return
        }
        debugKeyLog("session begin — isKeyWindow=true selected=\(keySelection?.selectedID ?? "none")")
    }

    /// End the list session: the flag dies, the ink retires (bar + hint), eligibility
    /// drops, and the key moment ends through the SAME order-out pulse WP-4d ratified
    /// (`endKeySession` — key snaps back to the still-active foreground app; never
    /// `resignKey()`, per the recorded spec amendment). Safe to call with no session
    /// live (no-op) — every choke point calls it unconditionally.
    private func endKeySummonSession() {
        guard keySelection != nil else { return }
        keySelection = nil
        panel.keySessionActive = false           // the never-key resting state (no card can
                                                 // coexist with a list session — the card
                                                 // branch re-derives its own eligibility)
        if let island = contentView as? IslandContentView {
            island.setKeySessionHint(false)
            island.setKeyFocus(id: nil)
        }
        endKeySession()
        debugKeyLog("session end — isKeyWindow=\(panel.isKeyWindow)")
    }

    /// WP-6k key handling (↑126 ↓125 ⏎36 esc53 space49 — the map is
    /// `GithudCore.KeySession.intent`, tested). Everything else falls through to the
    /// existing behavior (the ⌘-edit routing is `isKeyWindow`-scoped in
    /// `performKeyEquivalent` — during a list session its V/C/X/A/Z probe finds no
    /// editable responder and falls through harmlessly; a card's keystrokes never
    /// reach here — its field editor is first responder). Selection moves are 0ms;
    /// the peek toggle inherits the chevron click's own motion sanction (the same
    /// onPeekToggle → reflow seam). MODIFIED chords (⌘↓, ⌥⏎, …) fall through: the
    /// ratified map is plain ↑/↓/⏎/esc/space — consuming surplus chords would be
    /// unratified capture (review panel: AppKit LOW / trust note 5).
    private func handleSessionKey(_ event: NSEvent) -> Bool {
        guard keySelection != nil else { return false }   // not a list session → existing behavior
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return false }
        switch KeySession.intent(forKeyCode: event.keyCode) {
        case .moveUp:
            keySelection?.moveUp()
            (contentView as? IslandContentView)?.setKeyFocus(id: keySelection?.selectedID)
            debugKeyLog("move up → \(keySelection?.selectedID ?? "none")")
            return true
        case .moveDown:
            keySelection?.moveDown()
            (contentView as? IslandContentView)?.setKeyFocus(id: keySelection?.selectedID)
            debugKeyLog("move down → \(keySelection?.selectedID ?? "none")")
            return true
        case .open:
            // The existing row-open path (Open-on-GitHub ceiling), incl. its nil-url
            // no-op guard — then the session ends and the island collapses (spec F5).
            let opened = (contentView as? IslandContentView)?.openKeyFocusedRow() ?? false
            debugKeyLog("return — opened=\(opened)")
            endKeySummonSession()
            setExpanded(false)
            return true
        case .dismiss:
            debugKeyLog("esc — dismiss")
            endKeySummonSession()
            setExpanded(false)
            return true
        case .peek:
            let toggled = (contentView as? IslandContentView)?.togglePeekOnKeyFocusedRow() ?? false
            debugKeyLog("space — peek toggled=\(toggled)")
            return true
        case .passthrough:
            return false
        }
    }

    /// GITHUD_DEBUG-gated stderr trace (same env gate as `SummonHotkey.log`) — the
    /// recorded proof's honest in-process probe for key/session state. Silent (and
    /// branch-cheap) in normal runs; never logs row content beyond the stable id.
    private func debugKeyLog(_ message: String) {
        if ProcessInfo.processInfo.environment["GITHUD_DEBUG"] != nil {
            FileHandle.standardError.write(Data("▸ keysession: \(message)\n".utf8))
        }
    }

    // MARK: - WP-4d — the scoped key moment (shared flag with WP-6k: `keySessionActive`)

    /// Belt to `becomesKeyOnlyIfNeeded`'s suspenders: the field's own mouseDown (a genuine
    /// user-click context) asks for key in case the sendEvent path declined — harmless
    /// when already key. `makeKey()` only (never `makeKeyAndOrderFront`, never
    /// `NSApp.activate`): keystrokes route to the field while the foreground app stays
    /// active — its menu bar never blinks. The focus cue is NOT painted here — it follows
    /// the panel's real becomeKey (fix round, finding 4).
    private func beginKeySession() {
        guard panel.keySessionActive, contentView is LedgerCardView, !panel.isKeyWindow else { return }
        panel.makeKey()
    }

    /// End the key moment and hand key back to the foreground app. Called from every
    /// teardown choke point — Esc, card dismissal/clear (`handle(.ledger)`), a fresh card
    /// build, `hide()`, `setExpanded` (the system's own resign on click-away needs none of
    /// this — AppKit transfers key itself; `onDidResignKey` just detaches the editor).
    ///
    /// SPEC AMENDMENT (fix round, finding 3 — Gates.json prescribed `resignKey()`): AppKit
    /// has NO request API to give key away while staying visible — `resignKey()` is the
    /// system's notification callback ("never invoke directly"), and calling it hands key
    /// to NOBODY: the panel would stay key with a nil first responder, silently swallowing
    /// the editor's keystrokes. The ecosystem pattern (every real palette found: iTerm2,
    /// CotEditor, Maccy, Strongbox) releases key by ordering out — so: detach the editor,
    /// pulse orderOut (the window server returns key to the still-active foreground app),
    /// then orderFrontRegardless at the same frame (never key-taking). The card never
    /// leaves the screen for more than the flip; eligibility (`keySessionActive`) is
    /// untouched here — it belongs to the card's presence, not the moment.
    private func endKeySession() {
        (contentView as? LedgerCardView)?.setFieldFocused(false)
        panel.makeFirstResponder(nil)
        guard panel.isKeyWindow else { return }
        let frame = panel.frame
        panel.orderOut(nil)
        panel.setFrame(frame, display: false)
        if isVisible { panel.orderFrontRegardless() }   // guards LATER choke points: hide()
                                                        // flips isVisible false BEFORE its
                                                        // teardown lands here, so a hidden
                                                        // panel never re-fronts off a stale
                                                        // session end
    }

    func setExpanded(_ value: Bool) {
        guard expanded != value else { return }
        // WP-4d (fix round, finding 11): while a ledger card owns the surface, an EXPAND
        // request is an invisible state flip — the card renders regardless, but the flip
        // would end a live key moment mid-typing and retarget the completion morph to a
        // surface the user never chose. Refuse it. Collapse (false) must still proceed —
        // hide()'s funnel and the click-away monitor teardown depend on it.
        if value, model.ledger != nil { return }
        // Collapsing away from the chooser card DISMISSES it (click-away / chevron) — the
        // ordinary card lifecycle. Clearing fires `.pillStyleChooser(nil)` → its handle
        // branch flips `expanded` false + morphs back, so we return and let it drive.
        if !value, model.pillStyleChooser != nil {
            onDismissPillStyleChooser?()
            return
        }
        // Same lifecycle for the owner-lens card (WP 2026-07-14-001).
        if !value, model.lensChooser != nil {
            onDismissLensChooser?()
            return
        }
        // …and for the settings card (mark-and-settings option B).
        if !value, model.settingsCard != nil {
            onDismissSettingsCard?()
            return
        }
        endKeySummonSession()   // WP-6k: every real expand/collapse transition ends a live list
                                // session — esc/⏎/second-⌃⌥G/click-away/chevron/hide all funnel here
        endKeySession()   // any expand/collapse click is a click AWAY from the field (WP-6k's choke point)
        // Don't expand a panel that is mid-HIDE. During the 140ms tuck (and the 180ms collapse
        // beat before it) isVisible is already false but the panel is still on screen and its
        // fading pill still clickable — a click would otherwise run an expand morph on a panel
        // about to orderOut, stranding expanded==true with the global click-away monitor armed
        // on a hidden panel. `!isVisible && panel.isVisible` is exactly "hidden-but-still-on-
        // screen" (a hide in flight); at launch the panel isn't on screen yet, so an initial
        // expand-before-show still proceeds, and the ⌃⌥G summon (show() first → isVisible true)
        // is unaffected. Collapse (value == false) must always proceed (hide() drives it).
        if value, !isVisible, panel.isVisible { return }
        expanded = value
        onExpandChange?(value)              // the seam (fires once per real transition)
        updateClickAwayMonitor()            // add/remove the passive click-away monitor
        pendingMorph = value ? .expand : .collapse   // this ONE render may run the container morph
        renderNow()                         // a deliberate summon/collapse → render instantly
        pendingMorph = nil
    }

    /// Passive click-away collapse. A GLOBAL monitor sees only mouse-downs routed to OTHER
    /// apps — clicks inside githud's own panel or status item never reach it, so anything it
    /// DOES see is by definition an outside click → collapse. It only observes (never consumes
    /// the event, never becomes key), so focus/attention non-theft are preserved. Live ONLY
    /// while expanded, torn down on collapse — never a permanent monitor (idle-footprint).
    private func updateClickAwayMonitor() {
        if expanded, clickAwayMonitor == nil {
            clickAwayMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
                guard let self else { return }
                // Defensive belt-and-suspenders (should always pass — a global monitor never
                // sees our own clicks): if the pointer is within the panel frame, don't collapse.
                // NSEvent.mouseLocation and panel.frame are both screen coords (bottom-left origin).
                if self.panel.frame.contains(NSEvent.mouseLocation) { return }
                self.setExpanded(false)
            }
        } else if !expanded, let monitor = clickAwayMonitor {
            NSEvent.removeMonitor(monitor)
            clickAwayMonitor = nil
        }
    }

    deinit {
        if let clickAwayMonitor { NSEvent.removeMonitor(clickAwayMonitor) }
        if let screenParamsObserver { NotificationCenter.default.removeObserver(screenParamsObserver) }
    }

    /// The screen to anchor the island to (WP-5i): the injected provider (status item's
    /// screen → screen under the mouse → main, per AppDelegate's wiring), falling back to
    /// `NSScreen.main` when unset — never a hardcoded assumption about which monitor is
    /// "the" screen (today's bug: always `NSScreen.main`, which can differ from the monitor
    /// the menu-bar item actually lives on).
    private func resolvedScreen() -> NSScreen? {
        screenProvider?() ?? NSScreen.main
    }

    /// The summon: collapsed ⇄ expanded (a deliberate status-item click, NOT a
    /// top-edge-hover trap). While a ledger card is showing, the summon just re-asserts
    /// visibility (the card is already the must-see surface — fix round, finding 11: no
    /// invisible expanded-flip, no key-session kill mid-typing).
    func toggleExpand() {
        if model.ledger != nil {
            show()
            return
        }
        setExpanded(!expanded)
    }

    private func render() {
        // Increase-Contrast's rendering-only adjustments (border opacity, hover fill,
        // tertiary ink) flow through every content view via this ONE call site — never the
        // raw theme — so a11y state can't be forgotten at a future call site.
        let theme = effectiveTheme()
        if let card = model.ledger {
            endKeySummonSession()       // WP-6k end path: the card takes the surface → the list
                                        // session dies here (its key moment hands back via the
                                        // pulse; the fresh-card build below re-derives the card's
                                        // OWN eligibility from its presence)
            lastPillFingerprint = nil   // the pill left the screen; a later return is a fresh paint
            // Key ELIGIBILITY rides the card's presence (fix round): a field-bearing card
            // with a live field may take key — on the user's field click only
            // (`becomesKeyOnlyIfNeeded`). During the completion hold the field is disabled
            // and eligibility drops with it (finding 8).
            panel.keySessionActive = !card.isComplete
            // The ledger card UPDATES IN PLACE (unlike every other content, which rebuilds):
            // the field's editing state and the receipt fades must survive renders — a
            // teardown would eat a keystroke mid-paste and orphan the key moment. Only the
            // frame is re-solved (a remedy line appearing/disappearing changes the height);
            // the reflow is a hard snap riding the same real event that changed the card.
            if let existing = contentView as? LedgerCardView {
                existing.apply(card)
                let size = NSSize(width: LedgerCardView.width, height: existing.fittingHeight())
                panel.setContentSize(size)
                if let target = resolvedScreen().map({ IslandGeometry.frame(size: size, in: $0.visibleFrame) }) {
                    snapPanelFrame(target)
                }
                panel.invalidateShadow()
            } else {
                endKeySession()   // a FRESH card can never inherit a stale key moment
                let view = LedgerCardView(
                    card: card, theme: theme,
                    onSubmit: { [weak self] raw in self?.onTokenSubmit?(raw) },
                    onFieldClick: { [weak self] in self?.beginKeySession() },
                    onEscape: { [weak self] in self?.endKeySession() })
                // A surface rebuild (theme / a11y flip) mid-entry must not eat the user's
                // in-progress token (fix round, finding 9) — restore the stashed text into
                // the fresh field (never logged; consumed one-shot).
                if let text = pendingFieldText {
                    view.restoreFieldText(text)
                }
                view.layoutSubtreeIfNeeded()
                present(content: view, size: NSSize(width: LedgerCardView.width, height: view.fittingHeight()))
            }
            pendingFieldText = nil
            return
        }
        // The pill-style chooser card (WP 2026-07-10-001 §4) — rides render() presence like
        // the ledger, but it is DISMISSABLE and takes NO key moment. Its previews are live
        // CollapsedPillViews fed the user's current data with radar suppressed.
        if let chooser = model.pillStyleChooser {
            endKeySummonSession()       // a card takes the surface → any list session dies here
            lastPillFingerprint = nil   // the pill left the screen; a later return is a fresh paint
            // Focus-non-theft: the chooser has no field, so it can NEVER take key — the
            // never-key resting state, exactly (PillStyleChooser.takesKeyMoment == false,
            // pinned headlessly). No `panel.becomesKeyOnlyIfNeeded` field lives here.
            panel.keySessionActive = false
            pendingFieldText = nil
            let inboundActive = InboundPresenter.sections(for: model.inboundRows).active.count
            let sweep = currentSweepFreshness()
            // The coincide note's honesty gate (fix round M-3): "your door is empty" is a
            // CONFIRMED claim — before the first complete sweep the door merely hasn't been
            // read, so the card's empty-door line must not claim emptiness.
            let sweepConfirmed = model.lastInboundSuccessAt != nil
            if let existing = contentView as? PillStyleChooserView {
                // In place (a data poll or a selection while the card is up) — no teardown;
                // a changed height eases on the reflow grammar (dogfood 2026-07-14).
                existing.update(chooser: chooser, selected: model.pillStyle, pulse: model.pulseRows,
                                inboundActive: inboundActive, freshness: model.freshness,
                                sweepFreshness: sweep, sweepConfirmed: sweepConfirmed)
                animateCardResize(existing, to: NSSize(width: PillStyleChooserView.width,
                                                       height: existing.fittingHeight()))
            } else {
                let view = PillStyleChooserView(
                    chooser: chooser, selected: model.pillStyle, pulse: model.pulseRows,
                    inboundActive: inboundActive, freshness: model.freshness, sweepFreshness: sweep,
                    sweepConfirmed: sweepConfirmed,
                    theme: theme, onSelect: { [weak self] style in self?.onPillStyleSelect?(style) },
                    onBack: { [weak self] in self?.onPillBack?() })
                view.layoutSubtreeIfNeeded()
                present(content: view,
                        size: NSSize(width: PillStyleChooserView.width, height: view.fittingHeight()),
                        morph: pendingMorph)
            }
            return
        }
        // The owner-lens card (WP 2026-07-14-001) — the eye's destination. Rides render()
        // presence like the pill-style chooser (dismissable, NO key moment). The
        // descriptor is recomputed FRESH each pass from the model (prefs/rows/login), so
        // a toggle while the card is up refreshes its checks in place and the card can
        // never disagree with the lane it will collapse back onto.
        if model.lensChooser != nil {
            endKeySummonSession()       // a card takes the surface → any list session dies here
            lastPillFingerprint = nil   // the pill left the screen; a later return is a fresh paint
            panel.keySessionActive = false   // no field, never key (LensChooser.takesKeyMoment == false)
            pendingFieldText = nil
            // Rebuilt fresh every render pass so the card can never disagree with the lane
            // behind it. Same gating as AppDelegate.makeLensChooser: `showDrafts` gates drafts
            // (hidden means the lens holds its pre-WP domain), `showStale` gates nothing here —
            // quiet stays counted behind its caption (WP 2026-07-26-001, 2026-07-29-001).
            let lensSections = PulsePresenter.sections(for: model.pulseRows)
            let regions = lensSections.lensRegions(showDrafts: model.pulsePreferences.showDrafts)
            let chooser = LensChooser.make(
                live: regions.live, drafts: regions.drafts, quiet: lensSections.stale,
                prefs: model.lensPreferences, selfLogin: model.selfLogin)
            // Screen clamp (Codex P2, round 4): a large owner set must scroll in place,
            // never push the card's lower rows off-screen.
            let cardCap = (resolvedScreen()?.visibleFrame.height ?? 1000) - IslandGeometry.menuBarGap - 12
            if let existing = contentView as? LensChooserView {
                existing.update(chooser: chooser)
                animateCardResize(existing, to: NSSize(width: LensChooserView.width,
                                                       height: min(existing.fittingHeight(), cardCap)))
            } else {
                let view = LensChooserView(
                    chooser: chooser, theme: theme,
                    onToggleOwner: { [weak self] owner in self?.onLensToggleOwner?(owner) },
                    onToggleGroup: { [weak self] in self?.onLensToggleGroup?() },
                    onReorder: { [weak self] order in self?.onLensReorder?(order) },
                    onBack: { [weak self] in self?.onLensBack?() })
                view.layoutSubtreeIfNeeded()
                present(content: view,
                        size: NSSize(width: LensChooserView.width,
                                     height: min(view.fittingHeight(), cardCap)),
                        morph: pendingMorph)
            }
            return
        }
        // The settings card (mark-and-settings option B, dogfood-ratified 2026-07-14) —
        // the gear's destination. Same presence lifecycle as its two card siblings; the
        // descriptor is recomputed FRESH each pass, and a THEME-chip pick rebuilds the
        // card in the new theme (baked colors can't be updated in place).
        if model.settingsCard != nil {
            endKeySummonSession()
            lastPillFingerprint = nil
            panel.keySessionActive = false   // no field, never key
            pendingFieldText = nil
            let card = SettingsCard.make(
                surface: model.surfacePreferences, pulse: model.pulsePreferences,
                inbound: model.inboundPreferences, themeID: model.themeID,
                launchAtLogin: currentLaunchAtLogin?() ?? false,
                showJustCleared: model.showJustCleared)
            let cardCap = (resolvedScreen()?.visibleFrame.height ?? 1000) - IslandGeometry.menuBarGap - 12
            if let existing = contentView as? SettingsCardView, existing.builtTheme == theme {
                existing.update(card: card)
                animateCardResize(existing, to: NSSize(width: SettingsCardView.width,
                                                       height: min(existing.fittingHeight(), cardCap)))
            } else {
                let view = SettingsCardView(
                    card: card, theme: theme,
                    onToggleReason: { [weak self] reason in self?.onSettingsToggleReason?(reason) },
                    onToggleDrafts: { [weak self] in self?.onToggleDrafts?() },
                    onToggleStale: { [weak self] in self?.onToggleStale?() },
                    onToggleHeldBack: { [weak self] in self?.onToggleHeldBackInbound?() },
                    onSelectTheme: { [weak self] id in self?.onSettingsSelectTheme?(id) },
                    onToggleLaunch: { [weak self] in self?.onSettingsToggleLaunch?() },
                    onOpenPillStyle: { [weak self] in self?.onSettingsOpenPillStyle?() },
                    onOpenLens: { [weak self] in self?.onSettingsOpenLens?() },
                    onBack: { [weak self] in self?.onSettingsBack?() })
                view.layoutSubtreeIfNeeded()
                present(content: view,
                        size: NSSize(width: SettingsCardView.width,
                                     height: min(view.fittingHeight(), cardCap)),
                        morph: pendingMorph)
            }
            return
        }
        // WP-6k eligibility extension: with no card, key eligibility rides the live ⌃⌥G
        // list session — nil at rest, so this is byte-for-byte the never-key resting
        // state whenever no session is live. A collapsed surface can never hold a list
        // session (every collapse path already killed it in setExpanded — this is the
        // defensive backstop the WP-4d audit shape demands).
        if !expanded { endKeySummonSession() }
        panel.keySessionActive = keySelection != nil
        pendingFieldText = nil           // a non-card render drops any stale stash
        // Per-lane scroll preservation: a data-driven rebuild mid-read must not yank the user's
        // scroll position. Capture the OUTGOING island's offsets before teardown (only meaningful
        // expanded→expanded — a fresh expand from the pill legitimately opens at the top). When
        // buildSurface() already tore the content down (theme / Reduce-Transparency), fall back
        // to the offsets it stashed. One-shot: consumed here (or dropped by a collapsed render).
        let previousScroll = (contentView as? IslandContentView)?.scrollOffsets() ?? pendingScrollOffsets
        pendingScrollOffsets = nil
        // WP-3d′ peeks ride the same channel; consumed ONLY by the expanded branch below,
        // so a collapsed render drops them — peeks reset when the island collapses (spec).
        let previousPeeks = (contentView as? IslandContentView)?.peekStash() ?? pendingPeekStash
        pendingPeekStash = nil
        if expanded {
            lastPillFingerprint = nil   // pill leaves the screen; collapse re-tracks from scratch
            // WP-6k: the selection survives a data rebuild keyed on the STABLE row id
            // (the ink bar's PeekStash-analog) — a rebuild that drops the selected row
            // clamps to the nearest index (pure rule, tested in Core).
            if var selection = keySelection {
                selection.rebuild(ids: KeySession.actionableIDs(
                    radar: model.radarRows, pulse: model.pulseRows,
                    showDrafts: model.pulsePreferences.showDrafts,
                    showStale: model.pulsePreferences.showStale,
                    inbound: model.inboundRows,
                    showHeldBackInbound: model.inboundPreferences.showHeldBack,
                    lens: model.lensPreferences))   // folded rows are off-screen → out of the walk
                keySelection = selection
            }
            let view = IslandContentView(rows: model.radarRows, pulse: model.pulseRows,
                                         inbound: model.inboundRows,
                                         showDrafts: model.pulsePreferences.showDrafts,
                                         showStale: model.pulsePreferences.showStale,
                                         showHeldBackInbound: model.inboundPreferences.showHeldBack,
                                         freshness: model.freshness,
                                         radarConfirmed: model.radarConfirmed,   // the affirmation's gate — a
                                         inboundConfirmed: model.inboundConfirmed,
                                         reviewsConfirmed: model.reviewsConfirmed,
                                         clearedRows: model.clearedRows,
                                         showJustCleared: model.showJustCleared,
                                         onToggleJustCleared: onToggleJustCleared,
                                                                                 // CONFIRMED inbox read, never the
                                                                                 // looser hasData (fix round, 1a)
                                         peeks: previousPeeks ?? PeekStash(),
                                         theme: theme, onGearTap: onGearTap,
                                         onCollapse: { [weak self] in self?.setExpanded(false) },
                                         onToggleStale: onToggleStale,
                                         onToggleHeldBackInbound: onToggleHeldBackInbound,
                                         onToggleDrafts: onToggleDrafts,
                                         lensPreferences: model.lensPreferences,
                                         selfLogin: model.selfLogin,
                                         lensLastOpened: model.lensLastOpened,
                                         onToggleFoldedOwner: onToggleFoldedOwner,
                                         onOpenLensCard: onOpenLensCard)
            // A chevron peek changed a row's height → re-measure and ease the panel frame
            // on the WP-3d machinery (see animatePeekReflow — never a second animation system).
            view.onPeekChange = { [weak self] in self?.animatePeekReflow() }
            // REACTIVE height — the island sizes to its content (no dead space when a lane is
            // short); each lane self-caps at perPaneMaxHeight and scrolls, so this stays bounded.
            // Clamped to the screen as a final safety.
            let screenCap = (resolvedScreen()?.visibleFrame.height ?? 1000) - IslandGeometry.menuBarGap - 12
            let height = min(view.fittingHeight(), screenCap)
            let size = NSSize(width: IslandContentView.width, height: height)
            present(content: view, size: size, morph: pendingMorph)
            // Restore AFTER present() (the panes are now framed + laid out) so each lane resumes
            // where the reader left it, clamped to the rebuilt content height.
            if let previousScroll { view.applyScrollOffsets(previousScroll) }
            // WP-6k: re-ink the live session onto the rebuilt island — hint back on, bar
            // on the (id-followed) selection. AFTER the scroll restore, so the focused
            // row's whole-row visibility wins: the bar is where the keys act.
            if let selection = keySelection {
                view.setKeySessionHint(true)
                view.setKeyFocus(id: selection.selectedID)
            }
            return
        }
        // COLLAPSED — WP-3x slot morph: diff the pill's cell fingerprints per render. The
        // rules (and the invariant "no motion where no fact changed") live in
        // `GithudCore.PillMorph`; here we only pick the path the plan dictates.
        let loading = !model.hasData
        let inboundActive = InboundPresenter.sections(for: model.inboundRows).active.count
        let sweepFreshness = currentSweepFreshness()   // D1: the inbound tier's own stale clock
        let style = model.pillStyle
        let clearConfirmed = model.radarConfirmed && model.inboundConfirmed && model.reviewsConfirmed
        let fingerprint = PillMorph.fingerprint(rows: model.radarRows, pulse: model.pulseRows,
                                                loading: loading, freshness: model.freshness,
                                                sweepFreshness: sweepFreshness,
                                                inboundActive: inboundActive, style: style,
                                                clearConfirmed: clearConfirmed)
        let plan = PillMorph.plan(from: lastPillFingerprint, to: fingerprint)
        lastPillFingerprint = fingerprint
        let size = CollapsedPillView.size(for: model.radarRows, pulse: model.pulseRows,
                                          loading: loading, freshness: model.freshness,
                                          sweepFreshness: sweepFreshness,
                                          inboundActive: inboundActive, style: style,
                                          clearConfirmed: clearConfirmed)
        if pendingMorph == nil,                                // a container morph owns this render
           let pill = contentView as? CollapsedPillView,       // pill→pill only (data-driven change)
           !plan.isInstant,                                    // rules (a)/noop → today's 0ms swap
           !reduceMotion,                                      // rule (d): Reduce Motion → all 0ms
           !pillFadeInFlight,                                  // rule (e): mid-fade change → jump to end state
           outgoingMorphView == nil,                           // never during a container morph flight
           isVisible, panel.isVisible {                        // unwitnessed motion is pointless
            let a11y = PillAccessibilityPresenter.value(rows: model.radarRows, pulse: model.pulseRows,
                                                        freshness: model.freshness, sweepFreshness: sweepFreshness,
                                                        loading: loading, inboundActive: inboundActive, style: style,
                                                        clearConfirmed: clearConfirmed)
            animateSlotMorph(pill: pill, to: fingerprint, plan: plan, size: size, accessibilityValue: a11y)
            return
        }
        let content = CollapsedPillView(rows: model.radarRows, pulse: model.pulseRows,
                                        freshness: model.freshness, sweepFreshness: sweepFreshness,
                                        theme: theme, loading: loading, inboundActive: inboundActive, style: style,
                                        clearConfirmed: clearConfirmed,
                                        onTap: { [weak self] in self?.toggleExpand() })   // click the bubble to expand
        present(content: content, size: size, morph: pendingMorph)
    }

    /// The inbound SWEEP CLOCK (D1) at render time — `FreshnessModel.sweepStatus` over the
    /// model's last-complete-sweep date (nil ⇒ never swept ⇒ stale, which bites only over a
    /// real painted count). Distinct from the poll clock the radar/gauge read.
    private func currentSweepFreshness() -> Freshness {
        FreshnessModel.sweepStatus(lastSweepSuccess: model.lastInboundSuccessAt, now: Date())
    }

    /// Swap content, resize, reposition top-center. Size the EMPTY panel first so
    /// the content's Auto Layout can't pin the window width (see iter 8). Removes ONLY the
    /// previous content view — the grain overlay (a sibling) stays put across swaps.
    ///
    /// With a `morph` kind (set only by `setExpanded`) and motion allowed, the swap runs as
    /// the ratified 220ms/180ms container morph instead — the outgoing content stays alive
    /// through flight (the main build delta over the old synchronous removal). Every other
    /// case — data renders, Reduce Motion, hidden panel, first paint — is the hard cut,
    /// exactly as before.
    private func present(content: NSView, size: NSSize, morph: MorphKind? = nil) {
        let target = resolvedScreen().map { IslandGeometry.frame(size: size, in: $0.visibleFrame) }
        if let morph, let target, let outgoing = contentView, !reduceMotion, panel.isVisible {
            runMorph(morph, from: outgoing, to: content, size: size, target: target)
            return
        }
        // Hard cut. A hard render also supersedes any in-flight morph: retire its ghost and
        // snap the window animation to the new truth (generation bump silences stale completions).
        morphGeneration += 1
        pillFadeInFlight = false
        outgoingMorphView?.removeFromSuperview()
        outgoingMorphView = nil
        contentView?.removeFromSuperview()
        panel.setContentSize(size)
        content.frame = NSRect(origin: .zero, size: size)
        content.autoresizingMask = [.width, .height]
        surface.addSubview(content)
        contentView = content
        panel.setContentSize(size)
        if let target { snapPanelFrame(target) }
        panel.invalidateShadow()   // recompute the drop shadow from the new (masked, rounded) shape
        if pendingHideTuck {       // a hide whose collapse degraded to a cut still finishes hiding
            pendingHideTuck = false
            runHideTuck()
        }
    }

    /// Set the panel frame through a zero-duration animation group — this SUPERSEDES any
    /// in-flight window frame animation (morph/settle/tuck) so a hard render can never
    /// fight a running animator; without one active it is just an immediate set.
    private func snapPanelFrame(_ frame: NSRect) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().setFrame(frame, display: true)
        }
    }

    /// Set the panel alpha through a zero-duration animation group — the alpha twin of
    /// `snapPanelFrame`: this SUPERSEDES an in-flight window alpha animation (a running hide
    /// tuck / show settle) so a re-assertion of visibility can never be out-driven by it. A
    /// direct `panel.alphaValue = …` does NOT retarget a live NSWindow animator (same AppKit
    /// contract the frame twin exists for); without one active it is just an immediate set.
    private func snapPanelAlpha(_ alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = alpha
        }
    }

    // MARK: - WP-3d — the container morph (ratified `morph-hand-off-header`)

    /// Pin a content view to the surface's TOP-CENTER at a fixed size, with flexible
    /// left/right/bottom margins: as the window frame animates, autoresizing re-solves the
    /// margins on every step, keeping the view glued to its on-screen position (top edge
    /// pinned under the menu bar, horizontal center fixed) while the glass slides around
    /// it — the "one continuous surface" reading. Equal flexible margins split the width
    /// delta evenly, so the center cannot drift.
    private func pinTopCenter(_ view: NSView, size: NSSize, in container: NSSize) {
        view.autoresizingMask = [.minXMargin, .maxXMargin, .minYMargin]
        view.frame = NSRect(x: (container.width - size.width) / 2,
                            y: container.height - size.height,
                            width: size.width, height: size.height)
    }

    /// The morph: ONE `NSAnimationContext.runAnimationGroup` drives the panel frame
    /// (width + height simultaneously, cubic-bezier(0.2,0,0,1), radius constant at 14 via
    /// the surface's stretchable mask); the ink crossfades ride staggered one-shot layer
    /// fades (see `InkFade`). EXPAND 220ms: pill ink out 0–100ms, header in 80–200ms
    /// (the top-band hand-off), body+footer in 120–220ms. COLLAPSE 180ms: body out
    /// 0–70ms, header out 0–100ms, pill ink in 100–180ms. Interruptible: a re-toggle
    /// mid-flight starts a fresh group — the window frame retargets from its current
    /// (presentation) frame and every fade starts from its layer's presentation opacity.
    /// `invalidateShadow()` fires ONCE, in the completion handler (spec).
    private func runMorph(_ kind: MorphKind, from outgoing: NSView, to incoming: NSView,
                          size: NSSize, target: NSRect) {
        morphGeneration += 1
        let generation = morphGeneration
        pillFadeInFlight = false   // a container morph supersedes any in-flight pill fade
        // A retargeted morph: the PREVIOUS flight's outgoing ghost retires immediately —
        // the interrupted incoming (now `outgoing`) is the one that reverses.
        if let stale = outgoingMorphView, stale !== outgoing { stale.removeFromSuperview() }

        let container = surface.bounds.size
        pinTopCenter(outgoing, size: outgoing.frame.size, in: container)
        pinTopCenter(incoming, size: size, in: container)
        surface.addSubview(incoming)          // above the outgoing — the hand-off overlap
        contentView = incoming
        outgoingMorphView = outgoing

        let easeIn = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
        let easeOut = CAMediaTimingFunction(controlPoints: 0, 0, 0.2, 1)
        switch kind {
        case .expand:
            // The pill's top band crossfades into the header IN PLACE — no traveling
            // glyph, no empty-glass beat. All fades are opacity-only ink.
            InkFade.run(outgoing, to: 0, delay: 0, duration: 0.10, curve: easeIn)
            if let island = incoming as? IslandContentView {
                InkFade.run(island.morphHeader, from: 0, to: 1, delay: 0.08, duration: 0.12, curve: easeOut)
                for ink in island.morphBody {
                    InkFade.run(ink, from: 0, to: 1, delay: 0.12, duration: 0.10, curve: easeOut)
                }
            } else {
                InkFade.run(incoming, from: 0, to: 1, delay: 0.12, duration: 0.10, curve: easeOut)
            }
        case .collapse:
            if let island = outgoing as? IslandContentView {
                for ink in island.morphBody {
                    InkFade.run(ink, to: 0, delay: 0, duration: 0.07, curve: easeIn)
                }
                InkFade.run(island.morphHeader, to: 0, delay: 0, duration: 0.10, curve: easeIn)
            } else {
                InkFade.run(outgoing, to: 0, delay: 0, duration: 0.10, curve: easeIn)
            }
            InkFade.run(incoming, from: 0, to: 1, delay: 0.10, duration: 0.08, curve: easeOut)
        }

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = kind == .expand ? 0.22 : 0.18
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            outgoing.removeFromSuperview()
            self.outgoingMorphView = nil
            // Normalize the survivor to the standard present() arrangement.
            incoming.autoresizingMask = [.width, .height]
            incoming.frame = self.surface.bounds
            self.panel.invalidateShadow()   // once, in the completion (spec)
            if self.pendingHideTuck {       // hide's second beat: collapse done → tuck away
                self.pendingHideTuck = false
                self.runHideTuck()
            }
        })
    }

    // MARK: - WP-3d′ — the peek reflow (island height eases on the morph machinery)

    /// A chevron peek toggled: the island's content height changed, so re-measure and move
    /// the panel frame — the product's first DATA-SURFACE frame animation, a deliberate,
    /// ratified first (D-reveal). It rides the WP-3d machinery, never a second system: the
    /// same `NSAnimationContext` + cubic-bezier(0.2,0,0,1) family, the same `pinTopCenter`
    /// trick (content held at its FINAL size while the glass sweeps, so mid-flight Auto
    /// Layout never fights the animating frame), the same `morphGeneration` guard, and the
    /// same gates — Reduce Motion / hidden panel → instant; a container morph or window fx
    /// in flight keeps sole ownership of the window (this degrades to the hard snap, whose
    /// zero-duration group supersedes cleanly). 140ms: the ratified peek beat, matching the
    /// chevron's own rotation. Motion maps 1:1 to the user's click (attention-non-theft);
    /// one-shot, nothing repeats (idle-footprint).
    private func animatePeekReflow() {
        guard expanded, let island = contentView as? IslandContentView else { return }
        let screenCap = (resolvedScreen()?.visibleFrame.height ?? 1000) - IslandGeometry.menuBarGap - 12
        let size = NSSize(width: IslandContentView.width, height: min(island.fittingHeight(), screenCap))
        guard let target = resolvedScreen().map({ IslandGeometry.frame(size: size, in: $0.visibleFrame) })
        else { return }
        if reduceMotion || !panel.isVisible || outgoingMorphView != nil || windowFxInFlight {
            island.autoresizingMask = [.width, .height]
            snapPanelFrame(target)
            island.frame = surface.bounds
            panel.invalidateShadow()
            return
        }
        morphGeneration += 1   // a later hard render / container morph silences this completion
        let generation = morphGeneration
        pinTopCenter(island, size: size, in: surface.bounds.size)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            island.autoresizingMask = [.width, .height]
            island.frame = self.surface.bounds
            self.panel.invalidateShadow()   // once, in the completion — the morph's own contract
        })
    }

    /// Animate the panel to a card's new IN-PLACE size (a toggle changed the card's
    /// height) — the peek-reflow grammar verbatim: 140ms, bezier(0.2,0,0,1), content
    /// pinned top-center through flight; Reduce Motion / hidden / mid-morph → snap.
    /// Pane SWITCHES don't come here — they ride the container morph in present().
    private func animateCardResize(_ view: NSView, to size: NSSize) {
        guard let target = resolvedScreen().map({ IslandGeometry.frame(size: size, in: $0.visibleFrame) })
        else { return }
        // A container morph is mid-flight to this same pane (navigation renders twice:
        // show-new, then clear-old) — the morph owns the frame; snapping here would
        // supersede and kill it. Its completion settles the final frame + shadow.
        if outgoingMorphView != nil { return }
        if abs(panel.frame.height - target.height) < 0.5, abs(panel.frame.width - target.width) < 0.5 {
            panel.invalidateShadow()
            return
        }
        if reduceMotion || !panel.isVisible || windowFxInFlight {
            view.autoresizingMask = [.width, .height]
            panel.setContentSize(size)
            snapPanelFrame(target)
            view.frame = surface.bounds
            panel.invalidateShadow()
            return
        }
        morphGeneration += 1   // a later hard render / container morph silences this completion
        let generation = morphGeneration
        pinTopCenter(view, size: size, in: surface.bounds.size)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0, 0, 1)
            panel.animator().setFrame(target, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            view.autoresizingMask = [.width, .height]
            view.frame = self.surface.bounds
            self.panel.invalidateShadow()
        })
    }

    // MARK: - WP-3d — hide tuck / show settle (whole-window, maps 1:1 to the menu action)

    /// The pill tucks 8px upward (the menu-bar gap — under the bar it hangs from) while
    /// fading out over 140ms, then orders out. Alpha/frame are restored after orderOut so
    /// the next `show()` opens coherent.
    private func runHideTuck() {
        windowFxGeneration += 1
        // Reduce Motion gate — SECOND-LEVEL: hide() checks RM at entry, but the tuck can be
        // reached a beat later (chained in the collapse morph's completion, or via present()'s
        // pendingHideTuck consumption), so a mid-hide RM toggle would otherwise still play a
        // 140ms animation. Gate it like every other group here → plain orderOut, the reduced
        // contract ("hide = plain orderOut").
        guard !reduceMotion else {
            windowFxInFlight = false
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        let generation = windowFxGeneration
        windowFxInFlight = true
        let resting = panel.frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.4, 0, 1, 1)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(resting.offsetBy(dx: 0, dy: IslandGeometry.menuBarGap), display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.windowFxGeneration == generation else { return }
            self.windowFxInFlight = false
            self.panel.orderOut(nil)
            self.panel.alphaValue = 1
            self.panel.setFrame(resting, display: false)   // coherent next show
        })
    }

    /// The reverse: the panel is already front (at its final frame, opacity forced to 0
    /// first), then fades in with an 8px downward settle over 140ms.
    private func runShowSettle() {
        windowFxGeneration += 1
        let generation = windowFxGeneration
        windowFxInFlight = true
        let final = panel.frame
        panel.alphaValue = 0
        panel.setFrame(final.offsetBy(dx: 0, dy: IslandGeometry.menuBarGap), display: false)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.2, 1)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(final, display: true)
        }, completionHandler: { [weak self] in
            guard let self, self.windowFxGeneration == generation else { return }
            self.windowFxInFlight = false
            self.panel.invalidateShadow()
        })
    }

    // MARK: - WP-3x — the slot-morph width settle

    /// Run an in-place pill transition: the changed cells crossfade 120ms inside the pill
    /// (see `CollapsedPillView.applyTransition`), while the panel width eases 150ms on
    /// cubic-bezier(0.32,0.72,0,1) with the frame re-centered — origin and size interpolate
    /// together, so the pill's midX is constant at every step (the drift proof's pure half
    /// lives in the core test suite; the runtime half is asserted in the completion).
    private func animateSlotMorph(pill: CollapsedPillView, to fingerprint: PillMorph.Fingerprint,
                                  plan: PillMorph.Plan, size: NSSize, accessibilityValue: String) {
        guard let screen = resolvedScreen() else {   // no screen → nothing to animate on
            lastPillFingerprint = nil                 // force the hard path next render
            setNeedsRender()
            return
        }
        pillFadeInFlight = true
        morphGeneration += 1
        let generation = morphGeneration
        pill.applyTransition(to: fingerprint, plan: plan, accessibilityValue: accessibilityValue)
        let target = IslandGeometry.frame(size: size, in: screen.visibleFrame)
        let midXBefore = panel.frame.midX
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.72, 0, 1)
            pill.beginWidthSettle()
            if panel.frame != target {
                panel.animator().setFrame(target, display: true)
            }
        }, completionHandler: { [weak self] in
            guard let self, self.morphGeneration == generation else { return }
            self.pillFadeInFlight = false
            self.panel.invalidateShadow()
            // DRIFT PROOF (runtime half): the pill was centered before and must be centered
            // after — and because origin+size interpolate on one curve, midX held throughout.
            let drift = abs(self.panel.frame.midX - midXBefore)
            if abs(midXBefore - target.midX) <= 0.5 {
                assert(drift <= 0.5, "slot-morph drift: pill midX moved \(drift)px during the width settle")
                if drift > 0.5 { NSLog("githud: slot-morph drift proof FAILED — midX moved %.2fpx", drift) }
            }
        })
    }
}
