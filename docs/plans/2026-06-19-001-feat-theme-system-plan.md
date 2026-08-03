---
title: Theme System (5 themes)
type: feat
status: completed
date: 2026-06-19
origin: session design — monotone exploration reframed as a theme system; research sweep on native macOS theming
---

# Theme System — 5 themes

A runtime, user-selectable theme system for githud: **Geist Mono · GitHub · Color
(default) · Dracula · Nord**. A "theme" is a token bundle (surface · ink tiers ·
accent · state colors · glyph treatment · material · grain). Switching rides the
island's existing rebuild-on-render path — no new propagation machinery.

## Architecture Decision

**Approach:** Replace hardcoded colors/material in the view layer with a **`Theme`
token bundle** (one active at a time). A pure **`ThemeID` enum + registry lives in
GithudCore** (testable); the **`Theme` value type with NSColor/Material/glyph tokens
lives in GithudApp** (AppKit). The current theme is held by `AppDelegate` and applied
via `HUDPanelController.setTheme(_:)` → `render()` — the *exact* pattern already used
for `SurfacePreferences`/`PulsePreferences`. The theme threads into view constructors
as a `theme:` parameter.

**Rationale (priority: Consistency, then Simplicity):**
- **No singleton `ThemeManager` + NotificationCenter fan-out.** The research's
  ThemeKit/FluentUI pattern (post a notification, every long-lived view re-pulls tokens)
  exists for apps that *don't* rebuild. githud **already rebuilds its whole island on
  every data change** (`render()`), so a theme switch is just `setTheme → render` —
  byte-for-byte the `setPulsePreferences` flow. Adding an observer bus would be
  unjustified machinery.
- **Pure `ThemeID` in GithudCore, AppKit `Theme` in GithudApp.** Tokens are
  `NSColor`/`NSVisualEffectView.Material`/SF-Symbol configs — all AppKit. Putting them
  in GithudCore would drag AppKit into the pure, zero-dep-tested module. So the *registry*
  (ids, names, ordering — testable) is pure; the *mapping* to AppKit is in the app.

**Rejected alternative — a `ThemeManager` singleton with `themeDidChange` notification.**
Cleaner-sounding, and the canonical native pattern — but it solves a propagation problem
githud doesn't have (it rebuilds anyway). It would add an observer registration to every
view for zero benefit here. Consequence of choosing the rebuild path: a theme that ONLY
affected a long-lived, non-rebuilt view would need wiring — but no such surface exists
(everything is under `render()`).

**Rejected alternative — full SymbolConfiguration rendering-mode per theme
(monochrome/hierarchical/palette/multicolor).** The research lists it, but a single-tint
SF Symbol renders ~identically across monochrome/palette when there's one color. v1's
visible glyph axis is **{tint color} + {mono ⇒ fill-for-blocked / outline-for-calm}**.
True multicolor/hierarchical is deferred (see Scope Boundaries) — low visual payoff, real
complexity.

**Trade-offs accepted:**
- v1 themes are **dark-only**; light/dark adaptivity (via `NSColor(name:dynamicProvider:)`)
  is deferred. The system-appearance axis stays on `NSAppearance` and is untouched.
- Geist's grain pairs only with its solid surface (grain muddies vibrancy).
- The default **Color** theme must reproduce today's look *exactly* (backward-compat).

### Composition Matrix (hardcoded colors → composed Theme bundle)

**Old scalar assumptions:** views call `NSColor.systemRed/.systemGreen/.systemYellow`
(`urgencyColor`/`stateColor`), `.labelColor/.secondaryLabelColor/.tertiaryLabelColor`,
`.controlAccentColor` (badge), `NSColor.white.withAlphaComponent(0.07)` (hover), and
`NSVisualEffectView(material: .popover)` + `white 0.12` border (HUDPanelController).
**New model:** a single active `Theme` providing every one of those as a token.
**Ownership:** `Theme` owns values; views *render* from tokens; `ThemeStore` persists;
`AppDelegate`+`HUDPanelController` switch. **No priority lattice** (one theme active).

| Case | Visible contract | Token source | Test |
|---|---|---|---|
| default = Color | island looks **exactly** as iter-26 (no regression) | `Theme.color` tokens == today's hardcoded values | visual proof: Color render == prior manifest geometry; `theme_color_parity` |
| switch to Geist | solid surface, mono glyphs (blocked filled / ready outline), grain | `Theme.geistMono` | visual proof drafts-off/on under `--theme geist` |
| switch to Dracula/Nord/GitHub | solid surface, themed palette glyphs + ink | each theme's tokens | visual proof per `--theme` |
| every view themed | **no hardcoded NSColor remains** in the view layer | grep gate | `no_hardcoded_color` check (U5) |
| Reduce Transparency on | vibrant Color theme forced to solid | material → solid | manual/visual a11y |

**Red flag check:** no surface still renders "the color" directly after this — U5's grep
gate enforces it (every tint sourced from `theme`).

## High-Level Technical Design

```
ThemeID (GithudCore, pure)         Theme (GithudApp, AppKit)
  .geistMono .github .color          surface: .vibrant(Material) | .solid(NSColor)
  .dracula   .nord                   border, ink/ink2/ink3, accent, badgeInk
  .all (ordered)  .displayName       danger/success/warn (state colors)
       │                             monochrome: Bool        // Geist
       │                             grainOpacity: CGFloat
       ▼                             radarUrgencyColor(Int)->NSColor
  ThemeStore (UserDefaults)          pulseGlyph(PulseState)->(name,NSColor)  // name swaps fill↔outline when mono
  load()->ThemeID  save(_)           hoverFill: NSColor
       │                             makeSurfaceView()->NSView  // NSVisualEffectView or solid layer view
       ▼
  AppDelegate.currentTheme ──setTheme──▶ HUDPanelController
       (Theme submenu picker)              builds surface from theme + grain overlay,
                                           passes `theme` into IslandContentView/CollapsedPillView,
                                           render() (the existing rebuild path)
```
*Directional guidance for review, not implementation spec.*

## Implementation Units

### U1. Theme model — `ThemeID` (Core) + `Theme` + 5 themes + `ThemeStore`
- **Goal:** The theme definition layer: a pure id/registry + the AppKit token bundle + 5
  concrete themes + persistence.
- **Dependencies:** None
- **Files:** Create `Sources/GithudCore/ThemeID.swift`, `Sources/GithudApp/Theme.swift`,
  `Sources/GithudApp/ThemeStore.swift`; Test `Tests/GithudCoreTests/main.swift`
- **Approach:** `ThemeID: String, CaseIterable` (`geistMono/github/color/dracula/nord`) +
  `displayName` + `all` (display order, Color default). `Theme` = a struct of tokens (see
  HLD) with a `static func named(_ id: ThemeID) -> Theme` factory holding the 5 palettes;
  `surface` is an enum `ThemeSurface { case vibrant(NSVisualEffectView.Material); case solid(NSColor) }`.
  `pulseGlyph(state)` returns the SF Symbol name (swapping `.fill`→outline for calm states
  when `monochrome`) + the state color. `ThemeStore` mirrors `SurfaceStore` (UserDefaults
  key `githud.theme`, default `.color`).
- **Patterns to follow:** `SurfacePreferences.swift` (value + factory), `SurfaceStore.swift`
  (UserDefaults load/save), `PulsePresenter.symbolName` (the glyph names to swap).
- **Test scenarios:**
  - *Happy:* `ThemeID.all.count == 5`; ids stable (`rawValue`s: geistMono/github/color/dracula/nord);
    `.color` is the default; `displayName` non-empty for each.
  - *Edge:* `ThemeID(rawValue:)` round-trips; an unknown stored string → `.color` (ThemeStore default).
  - *Registry:* every `ThemeID` resolves via `Theme.named` (no missing case) — guarded by
    `CaseIterable` exhaustiveness (a Theme.named switch over all cases).
- **Verification:** All 5 ids enumerated + stable; ThemeStore round-trips; `Theme.named` total.

### U2. Themed surface — material (vibrant↔solid) + border + grain overlay
- **Goal:** `HUDPanelController` builds the island background from the theme (vibrant
  `NSVisualEffectView` or solid layer-backed view), themed border, and a static grain
  overlay; `setTheme(_:)` rebuilds + re-renders.
- **Dependencies:** U1
- **Files:** Modify `Sources/GithudApp/HUDPanelController.swift`; Create
  `Sources/GithudApp/GrainTexture.swift`
- **Approach:** Extract surface construction into `applyTheme()`: build `theme.surface`
  (`.vibrant` → `NSVisualEffectView` with that material + `.behindWindow`; `.solid` → a
  layer-backed `NSView` with `backgroundColor`), set border = `theme.border`, keep
  cornerRadius 14. `GrainTexture.shared` lazily generates ONE seeded ~128×128 noise
  `NSImage` (deterministic LCG fill — NO `Date`/`Math.random`) cached; when
  `theme.grainOpacity > 0`, add a static overlay layer above the content with that opacity
  (no animation, no CIFilter). `setTheme(_:)` stores the theme, rebuilds the surface view,
  re-renders content. `present()` keeps the "size empty panel first" fix.
- **Patterns to follow:** `HUDPanelController.swift:41` (the current `NSVisualEffectView`
  setup), `present()` (the width-bug fix), `setPulsePreferences` (the setter+re-render shape).
- **Test scenarios:** *Edge:* a vibrant theme builds an `NSVisualEffectView`; a solid theme
  builds a layer-backed view with the surface color. *Idle:* grain is a static layer (no
  timer/CADisplayLink added). (Surface construction is view code → verified by visual proof
  + the idle_cpu manifest in U5; `GrainTexture` determinism is unit-checkable: same bytes twice.)
- **Verification:** Vibrant + solid surfaces both render; grain shows only when opacity>0;
  **idle_cpu stays ~0** with grain on (the idle-footprint pressure holds — no animation).

### U3. Themed tokens in the views
- **Goal:** Every color in the island comes from `theme` — ink tiers, badge accent, radar
  urgency tint, pulse state glyph+color (incl. mono fill/outline), hover fill.
- **Dependencies:** U1
- **Files:** Modify `Sources/GithudApp/IslandContentView.swift`,
  `Sources/GithudApp/CollapsedPillView.swift`
- **Approach:** Thread `theme: Theme` into `IslandContentView.init` and
  `CollapsedPillView.init`. Replace: header/title/caption/section colors →
  `theme.ink*`; count badge bg → `theme.accent`, label → `theme.badgeInk`;
  `RadarRowView.urgencyColor(_)` → `theme.radarUrgencyColor(_)`; `PulseRowView` glyph
  name+tint → `theme.pulseGlyph(state)` (so Geist gets outline-for-calm); hover fill →
  `theme.hoverFill`. `RadarRowView`/`PulseRowView` gain a `theme` arg. Keep
  `MessageView` (auth/setup) on `systemOrange` — it's a system-state warning, theme-agnostic
  (note in Scope).
- **Patterns to follow:** `IslandContentView.swift` (RadarRowView/PulseRowView icon tint),
  `PulseRowView.stateColor` + `RadarRowView.urgencyColor` (the maps being replaced).
- **Test scenarios:** *Happy:* the **Color** theme's `radarUrgencyColor`/`pulseGlyph`
  return the SAME values as today's hardcoded maps (parity — so the default render is
  unchanged). *Edge:* Geist `pulseGlyph(.ready)` returns an OUTLINE name; `.blocked` a FILL
  name; non-mono themes always return FILL. (Color-equality is pure-checkable if the maps
  live on `Theme`; see U5 parity test.)
- **Verification:** No hardcoded `NSColor.system*`/`label*`/`controlAccent` left in the two
  view files (grep gate, U5); Color theme renders identically to iter-26.

### U4. Theme picker + wiring + accessibility
- **Goal:** A "Theme" menu picker; load/persist/apply on launch; force solid under Reduce
  Transparency; a `--theme <id>` arg for visual proof.
- **Dependencies:** U2, U3
- **Files:** Modify `Sources/GithudApp/StatusItemController.swift`,
  `Sources/GithudApp/AppDelegate.swift`, `Sources/GithudApp/main.swift`
- **Approach:** `StatusItemController`: a "Theme" submenu (mirror `Surface…`) listing
  `ThemeID.all` by `displayName` with a checkmark on the current; `onSelectTheme(ThemeID)`.
  `AppDelegate`: `currentTheme = ThemeStore.load()`, pass to the HUD on launch
  (`hud.setTheme`), wire `onSelectTheme` → save + `hud.setTheme` (re-render, no refetch).
  **A11y:** observe `NSWorkspace.accessibilityDisplayOptionsDidChangeNotification`; when
  `accessibilityDisplayShouldReduceTransparency`, the HUD coerces any `.vibrant` surface to
  `.solid` (a theme method `effectiveSurface(reduceTransparency:)`). `main.swift`: parse
  `--theme <id>` → `delegate.initialThemeID` (overrides the store, for `--fixture` visual proof).
- **Patterns to follow:** `StatusItemController.menuNeedsUpdate` (the Surface submenu +
  checkmarks), `AppDelegate.toggleReason`/`toggleShowDrafts` (save + re-render), `main.swift`
  `--show-drafts` (the arg-override shape).
- **State-Action contract (theme selection):**
  | Action × state | Caller obs. | Durable | Side effect | Test |
  |---|---|---|---|---|
  | select theme X | menu check moves to X | `githud.theme=X` | island rebuilds in X | visual/manual |
  | relaunch | — | reads X | island opens in X | manual |
  | Reduce Transparency on (vibrant active) | — | theme unchanged | surface coerced solid | a11y manual |
  - **Invariant:** the persisted `ThemeID` is the *user's choice*; Reduce-Transparency
    coercion affects only the *rendered surface*, never the stored id (toggling a11y back
    restores vibrancy).
- **Test scenarios:** *Edge:* `--theme bogus` → falls back to `.color` (no crash).
  *Integration:* picker→save→render verified by visual proof (U5).
- **Verification:** Picker switches live + persists; Reduce-Transparency forces solid
  without changing the stored choice; `--theme` renders the chosen theme.

### U5. Verify — visual proof (5 themes), idle, a11y, parity, grep gate
- **Goal:** Prove every theme renders, grain stays 0-idle, Color is unchanged, and no
  hardcoded color survives.
- **Dependencies:** U1–U4
- **Files:** Modify `Tests/GithudCoreTests/main.swift`; add `scripts/` usage (no new script
  needed — `GITHUD_ARGS="--fixture … --theme <id>"`)
- **Approach:** Visual-proof manifest per theme (`--theme geist|github|color|dracula|nord`
  over the fixtures), each asserting `pixel_live` + capturing `idle_cpu` (grain-on Geist must
  stay ~0). A **parity** test: `Theme.color`'s urgency/state maps equal the pre-refactor
  values (lock the no-regression invariant). A **grep gate** (shell, in U5 or a tiny script):
  no `NSColor.system`/`.labelColor`/`.secondaryLabelColor`/`.tertiaryLabelColor`/`.controlAccentColor`
  in `IslandContentView.swift`/`CollapsedPillView.swift`/`HUDPanelController.swift` (all via
  `theme`). `ThemeID`/`ThemeStore` pure tests (U1).
- **Patterns to follow:** `scripts/visual-proof.sh` (`GITHUD_ARGS`), the iter-26 dual-state
  proof, the privacy-redaction discipline.
- **Test scenarios:** *Happy:* 5 theme manifests captured, all `pixel_live`. *Idle:* Geist
  (grain on) `idle_cpu ~0`. *Parity:* Color tokens == legacy values. *Gate:* grep finds no
  hardcoded color in the 3 view files.
- **Verification:** All 5 themes render (manifests); grain 0-idle; Color unchanged; grep clean;
  full suite green.

## Scope Boundaries
- **Dark-only v1** — no light-mode token variants yet.
- **No `ThemeManager` singleton / notification bus** — AppDelegate+setTheme rebuild path only.
- **Glyph rendering-mode (hierarchical/palette/multicolor) deferred** — v1 glyph axis is
  tint + mono fill/outline.
- **`MessageView` (auth/no-token) stays system-orange** — a system warning, not themed.
- **Status-item menu-bar glyph stays template (auto light/dark)** — not themed (it lives in
  the system menu bar, not the island).

### Deferred to Follow-Up Work
- Light/dark adaptive token sets via `NSColor(name:dynamicProvider:)`.
- True SF Symbol palette/hierarchical/multicolor per theme.
- More themes (Tokyo Night / Catppuccin / Gruvbox) — each is one `Theme.named` case + a
  `ThemeID`.
- "Mono + one earned accent" hybrid; per-theme grain on non-Geist.

## System-Wide Impact
- **Interaction graph:** `theme` threads `AppDelegate → HUDPanelController → IslandContentView/
  CollapsedPillView → RadarRowView/PulseRowView`; `onSelectTheme` parallels `onToggleReason`/
  `onToggleShowDrafts`; the a11y observer is new.
- **Error propagation:** none new — pure presentation; a bad `--theme`/stored id → `.color`.
- **State lifecycle:** `currentTheme` persists in UserDefaults; switching re-renders from
  cached data (no refetch); Reduce-Transparency coercion never mutates the stored id.
- **API surface parity:** both island surfaces (expanded + collapsed pill) + the probe-free
  render path consume `theme`; the probe/data spine is untouched.
- **Unchanged invariants:** classifier, pulse lattice, polling, enrichment, classic-PAT WALL,
  focus-non-theft, **idle-footprint** (grain is static; re-proven), the Color theme's exact look.

## Risks & Dependencies
| Risk | Mitigation |
|------|------------|
| Grain animates / costs idle CPU | Static seeded tile, one cached image, overlay layer, no timer/CIFilter — re-prove idle_cpu (U5) |
| Color theme drifts from today's look | Parity test: `Theme.color` maps == legacy values; visual proof vs iter-26 geometry |
| A hardcoded color slips through | Grep gate (U5) over the 3 view files |
| Solid↔vibrant surface swap breaks the width/position fix | `applyTheme` reuses `present()`'s "size empty panel first" sequence |
| Reduce-Transparency loses the user's choice | Invariant: coercion affects render only, not the stored id |
| GrainTexture uses Date/random (non-deterministic) | Seeded LCG, no Date/Math.random — same bytes twice (unit-checkable) |

## Confidence cross-check
| Requirement | Unit | Resolution | Match? |
|---|---|---|---|
| 5 themes selectable + persisted | U1, U4 | ThemeID registry + ThemeStore + picker | ✓ |
| Geist solid + mono + grain | U1,U2,U3 | solid surface, mono glyph fill/outline, grain overlay | ✓ |
| Color unchanged (default) | U3,U5 | parity test + visual proof | ✓ |
| 0-idle grain | U2,U5 | static tile, idle_cpu re-proven | ✓ |
| no hardcoded color after | U3,U5 | grep gate | ✓ |
| a11y reduce-transparency | U4 | force solid, keep stored id | ✓ |
