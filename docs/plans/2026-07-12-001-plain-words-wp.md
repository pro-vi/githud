# WP 2026-07-12-001 — Plain words: caption copy C + expand-in-place + footer link

*Ratified 2026-07-12 ("yeah i like C and the after view is much better"). Session
gallery: docs/design/2026-07-12-plain-words-mocks.html (artifact a872c8ab…). The
dogfood feedback verbatim: the collapsed captions "feel very AI"; wanted "more
human wording from like earlier web"; "there should be a button to expand on
those"; "I don't like check for yourself … please only leave the link for
github inbox"; "the clickable area needs to be higher".*

## Scope — three pieces, one WP

### 1. Caption copy, flavor C (old-web parenthetical)

Exact strings (counts interpolate; the parenthesized verb is the link affordance):

- Stale pulse caption (`IslandContentView.swift:153`, was `"N stale · untouched 14d+"`):
  **`N gone quiet (show)`**
- Held-back inbound caption (`IslandContentView.swift:126`, was `"N held back · bots/drafts"`):
  **`N from bots & drafts (show)`**
- Revealed section headers gain a trailing hide control on the right edge:
  - Pulse stale section header (was `"Stale"`): **`Gone quiet`** + **`(hide)`**
  - Inbound held-back rows (today: appended with NO header when revealed) gain a
    header: **`Bots & drafts`** + **`(hide)`**
- Gear menu items (`StatusItemController.swift:315/324`):
  - `"Show stale PRs (untouched 14d+)"` → **`Show PRs gone quiet`**, with the
    threshold moving to the item's TOOLTIP (e.g. "untouched for 14 days or more") —
    off the glass, not out of the app.
  - `"Show held-back inbound (bots/drafts)"` → **`Show bots & drafts`**, tooltip
    naming what's held back (bot and draft arrivals kept out of the queue).
- String home: caption/header strings move to a testable GithudCore presenter home
  (the CaughtUpPresenter precedent — strings decided in Core, tense/count-pinned in
  the CLT suite). The App layer renders what Core decides.
- NOT in scope (recorded in the gallery's Decide section): row subtitle compressed
  forms ("waiting 28w"); the Drafts section (no caption exists today; header stays
  `"Drafts"`).

### 2. Captions become buttons — expand in place, one truth

- The caption is ONE full-width click target (island-row convention), not just the
  verb. Clicking flips the SAME preference the gear item flips (`showStale` /
  `showHeldBackInbound`) — two handles, one state; the gear checkmark stays honest.
- The revealed header's `(hide)` flips the same preference back — two-way from the
  island, no trip to the gear.
- Motion: the reveal rides the island's EXISTING grammar — the pref flip re-renders
  (`Change.pulsePreferences` path) and the island height change eases on the same
  machinery peeks use; no new animation vocabulary, no timers; Reduce Motion 0ms
  (caller-owned, unchanged).
- Accessibility: the caption is a button (spoken e.g. "3 gone quiet, show"); the
  hide control likewise ("hide"). Key session: captions/hide are NOT added to the
  ⌃⌥G actionable ring in this WP (recorded — additive later if dogfood wants it).

### 3. The footer link — drop the preamble, raise the target

- `InboxLinkView` label (`IslandContentView.swift:774`):
  `"Check for yourself — GitHub inbox ↗"` → **`GitHub inbox ↗`**.
- The audit-invitation intent survives where it is SPOKEN: the accessibility label
  stays `"Audit the full GitHub inbox"`.
- Click band grows from text-height (~15px) to a comfortable ~30px by padding
  INSIDE the existing full-width target (the label's top/bottom constraints gain
  ~8pt constants; the base hitTest already flattens the footer to one target).
- The ⌃⌥G session hint keeps riding the same line's right edge, unchanged
  (centerY-tied to the label, so it moves with the padding automatically).

## Proof obligations (definition of done)

- Full headless suite green (1153 baseline + new): count-interpolated caption/header
  string pins in Core (1 and N); preference round-trip unchanged; any existing pins
  on the old strings updated, never deleted without replacement.
- `scripts/test.sh` exit 0 (CLT-only runner — no XCTest reach).
- Grep: no new timers/animation (idle-footprint row); no new key-window paths
  (focus-non-theft — captions are plain clickable ink like rows).
- CI green on push; app bundle rebuilt (`bash scripts/build-app.sh`) + relaunched.

## Recorded decisions + watches

- Flavor C ratified over A/B (user's one-line pick); footer "after" ratified.
- The 14d threshold leaves the glass for the gear tooltip — a deliberate
  information demotion, revisable one-line if dogfood misses it.
- "Check for yourself" copy retired from print; intent kept in the VO label.
- Dogfood watches: the caption-click reveal easing on glass; whether the
  (show)/(hide) verbs read as clickable without hover; whether the taller footer
  band crowds the island's bottom edge.

## Addendum — Drafts joins the family (ratified 2026-07-12, same day)

*User, on seeing the landed build: gear-revealed draft PRs "should also have the
hide button … say for draft PRs … make them the same path maybe /refactor too."*

- The Drafts section migrates onto the SAME revealed-header path: header
  **`Draft PRs`** (user's words; was the bare `Drafts`) + right-edge **`(hide)`**
  flipping `showDrafts` — wired through the identical callback chain to the exact
  func the gear uses (one truth, third instance).
- Header renders only WITH rows (the deviation-4 guard, applied to the third
  sibling — kills the latent lone-`Drafts`-header-over-zero-drafts case).
- Strings move to `PlainWords`: `draftsHeader`, `draftsGearItem` (title stays
  `Show draft PRs` — already plain), and a family-symmetric tooltip
  `Your works-in-progress, kept out of the glance`.
- PRESERVED ASYMMETRY (recorded, deliberate): drafts get NO collapsed caption —
  hidden drafts stay invisible ("ignore me, WIP" doctrine). The shared path is
  parameterized by caption-presence; it does not homogenize the sections.
- Proof: PlainWords pins for the new strings; suite ≥ 1172 + additions; grep — no
  remaining `sectionHeader("Drafts")` (the old pattern must not survive).

## Landing record (2026-07-12)

LANDED at `8f2019a`, fast-forwarded to main after rebase over the docs commit;
**1172 checks** (1153 → +19 Core pins), CI green. Gauntlet: Opus builder
(worktree) → 3-lens Opus panel → **MERGE ×3, zero mandatory fixes** (the second
zero-fix first-review after WP-6k). All lenses re-ran the suite themselves.

**Builder's disclosed choices, panel-verified:** verbs underlined via the
LedgerCardView attributed-label precedent (the mock mandates it); threshold
demoted to the gear tooltip; "Check for yourself" retired from print, VO label
kept verbatim; revealed headers render only WITH rows (kills the pre-existing
lone-"Stale"-header-over-zero-rows case — an improvement the mock implies).

**Strings home:** `GithudCore/PlainWords.swift` — captions (1/N), spoken forms,
headers, verbs, gear titles + tooltips; App renders only what Core decides; the
underline range is located via `PlainWords.showVerb` with a structural
`hasSuffix` pin so it can never silently no-op.

**Panel nits, recorded not fixed:** inner NSTextFields of the new caption/hide
buttons stay AX-visible (matches every shipped row + the footer — watch VO
dogfood; the one-line fix is `setAccessibilityElement(false)` on the labels if a
double read surfaces); footer string is the one decidable string still owned by
the App (within spec — no count interpolation, low pin value); with a pref ON
and zero matching rows the island renders nothing for that section (honest — the
gear remains the only off-switch in that state, same as pre-WP); caption
vertical padding 5pt vs the mock's 6px.

**Dogfood watches:** VO read of the caption buttons; (show)/(hide) affordance
readability without hover; the taller footer band vs the island's bottom edge;
reveal easing on glass at real data sizes.

### Addendum landing (2026-07-12, same day)

LANDED at `1fec282`; **1175 checks** (+3 PlainWords pins); focused Opus
re-verify **LAND** (proportional review — the mechanism carried MERGE ×3 from
the morning panel; this migrated the third sibling). Verified in code: the
(hide) and the gear flip the identical `AppDelegate.toggleShowDrafts()`;
zero-drafts renders nothing (flat-guard shape, behavior-identical to stale's
nested form); `sectionHeader("Drafts")` extinct in Sources+Tests (ProbeCommand's
diagnostic dump label is uncoupled); KeySession untouched and already correct.
Builder deviations: none.
