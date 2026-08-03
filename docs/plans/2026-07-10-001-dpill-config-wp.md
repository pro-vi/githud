# WP 2026-07-10-001 — D-pill: pill styles + honest previews (the config resolution)

*Ratified 2026-07-10. The D-pill session (seed 2026-07-09-002, gallery
docs/design/2026-07-09-dpill-session-mocks.html) ended with the user ratifying a
CONFIG, not a single vocabulary: "the best approach is to allow config with actual
visual preview therefore we may provide a default but user can switch it up."
Context: they leaned supersede on aesthetics ("looking at green and red on the
island, not sure") but had objected on utility that a superseding queue "blocks the
PRs underneath" — both truths held; that is a preference, so it ships as one.*

## Scope — four pieces, one WP

### 1. D1 — the per-fact stale clock (F3 closure; unconditional, style-independent)

The pill's stale prefix must cover the fact it is DISPLAYING:

- Radar / gauge / check states → poll `freshness` (today's behavior, unchanged).
- Any **inbound-count-bearing** state (queueLeads primary, standingCounted segment,
  queue-only standing state) → a **sweep freshness** computed from
  `lastInboundSuccessAt` with the same `FreshnessModel` thresholds.
- Rule of degradation for the composed standing state: the prefix shows if EITHER
  displayed fact's clock is degraded (a composed claim is only as fresh as its
  stalest member).
- Never-swept (nil date) with a non-zero painted count → degraded (a count whose
  clock never ticked is exactly the "adopted-stale under fresh chrome" F3 case).
  Never-swept with count 0 → moot (no count-bearing state renders).
- Seams: thread `lastInboundSuccessAt` into AppModel (snapshot already carries it;
  PollState stamps it) → HUDPanelController computes `sweepFreshness` → fingerprint/
  size/a11y take the pair (pollFreshness, sweepFreshness) and pick per fact.

### 2. PillStyle — the preference (Core, pure)

```swift
public enum PillStyle: String, CaseIterable {  // stored raw, default .queueLeads
    case queueLeads       // DEFAULT — ladder: loading > radar > inbound > gauge > check
    case standingMarked   // ladder for acute; standing tier composes gauge + dim count-free tray
    case standingCounted  // standing tier composes gauge + tray+count segment
}
```

- Default **queueLeads** (the user's stated aesthetic lean: ink, pinned 60pt,
  chronic color retired). One-click revisable in the chooser — that is the point.
- `PillMorph.fingerprint(...)`, `CollapsedPillView.size(for:)`, and
  `PillAccessibilityPresenter` all gain the style parameter and MUST encode it in
  lockstep (F5). A style-matrix test pins all three per style (the missing
  order-pinning test, generalized).
- Persistence: UserDefaults raw string via the existing preferences pattern; absent
  key → default. No migration needed (new pref).

### 3. The three styles — exact semantics (from the ratified gallery specs)

**queueLeads** = ladder-strict as amended: inbound above gauge; glyph `tray.fill`
13pt medium (still-life tense — the standing queue); width = the radar-count
formula (60 @ 1 digit); spoken "N waiting at your door" above the gauge clause;
D1 covers the chronic count. The struck sentence stays struck: gauge surfacing
proves nothing about the queue pre-confirmation.

**standingMarked** = hybrid, marked: standing tier renders gauge + an 11pt
`tray.fill` inkTertiary count-free mark (+20pt) iff inboundActive > 0; queue-only
standing state (zero live PRs, queue > 0) renders tray 13pt medium + count at the
radar-cell formula (the F1 dead tier, now reachable); spoken (strict count-free
parity): "…; people waiting at your door." Mark absence means only "no one at the
door BY COUNT" — never confirmed-empty (the island's inboundConfirmed gate keeps
the strong claim).

**standingCounted** = hybrid, counted: the queue rides as a glyph+count segment on
the gauge's own atoms (16+4+d·9, gap 6; chronic 123pt for ✓3⚠4+5); digit ticks ride
the same-structure zip (0ms); segment arrival/departure fades the VALUE CELL WHOLE
(today's gauge grammar — NO per-segment engine; the composed-lanes mechanics kill
does not transfer); spoken: gauge clause + ". N waiting at your door."

Shared invariants, all styles: radar tier stays EXCLUSIVE (shield never co-renders
with badges — F4 preserved); loading/check ends unchanged; stale prefix composes
per D1; Reduce Motion zeroes durations (caller-owned, unchanged); no idle motion.

Fingerprint shape: `Value` gains ONE case
`.standing(gauge: [GaugeSegmentPrint], queue: QueuePrint)` with
`enum QueuePrint: Equatable { case mark; case count(String) }`.
`isEqualDigitTick` extends: standing↔standing with identical gauge structure,
identical queue-print case, and equal digit counts → instant tick. Everything else
cross-state → whole value-cell fade. `Glyph` and `Plan` shapes are UNTOUCHED (the
ratified WP-3x contract stands; rule c — isCritical lives on the glyph fact — is
not moved).

### 4. The chooser card — config with actual visual preview (App)

- Entry: gear menu item "Pill style…" → island expands (if collapsed) and shows a
  chooser card (LedgerCardView pattern precedent: cards ride render() presence).
- Content: three rows, each = a radio + a LIVE PREVIEW rendered by
  **CollapsedPillView itself** (the real view class, not a facsimile) fed the
  CURRENT model data with **radar suppressed**, captioned plainly
  ("when nothing acute needs you — previews use your live data"). Rationale:
  radar states are identical across styles, so the preview shows the one state
  where styles differ, from real data — never a fabricated specimen.
- Honesty edge: if inboundActive == 0 right now, the three previews legitimately
  coincide — the card SAYS so ("your door is empty right now, so the styles look
  the same") rather than faking a queue.
- Selection applies instantly (the live pill morphs — motion maps 1:1 to the
  click) and persists. Dismiss: gear-again / collapse / click-away — the ordinary
  card lifecycle. The card takes NO key moment (no text field): `canBecomeKey`
  stays false throughout; headless assertion required (focus-non-theft row:
  panel-content changes owe non-interruption proof).
- Copy (D-copy plainspoken, panel may refine): title "Pill style"; options
  "Door first" (default) / "Side by side — quiet mark" / "Side by side — with the
  count".

## Proof obligations (definition of done)

- Full headless suite green (1010 baseline + new: style×state fingerprint matrix
  incl. F5 lockstep pins across fingerprint/size/spoken; standing tick/fade rules;
  QueuePrint equality; D1 per-fact prefix incl. never-swept and either-degraded
  rules; preference decode/default; spoken parity per style).
- `scripts/test.sh` exit 0 (CLT-only runner — no XCTest reach).
- Existing tray assert updates: `main.swift:923` (tray.and.arrow.down.fill →
  tray.fill where the standing/queue tier draws).
- CI green on push; app bundle rebuilt (`bash scripts/build-app.sh`) + relaunched.
- Headless: card presence never sets keySessionActive / canBecomeKey.
- Grep: no new timers/animation (idle-footprint row).

## Recorded decisions + watches

- Default = queueLeads (user's aesthetic lean; one-line revert = change the
  default case). The utility objection (queue walls off gauge) is ANSWERED BY THE
  CONFIG, not dismissed — recorded verbatim above.
- The user's "green and red on the island, not sure" extends to the ISLAND's pulse
  badges — ratified color, NOT touched by this WP; logged as a dogfood watch
  (color-doctrine row expiry note: "if dogfood shows…" — this is that signal's
  first flicker).
- Radar∩inbound dual-presence (F2) is the arrival-knock feature; radar keeps
  `tray.and.arrow.down.fill` (arriving tense, RadarPresenter.swift:64) while the
  pill's standing queue uses `tray.fill` (still-life) — tense split is deliberate.
- Composed-lanes/composed-reasons remain killed; the standing pair composes only
  the proven-disjoint gauge⊕queue.
- Follow-ups NOT in scope: pip/typed-marker add-ons (available later, additive);
  hover-slab respec; row-mechanics extraction; WP-6w.

## Landing record (2026-07-10)

LANDED at `acadf99` (build) + `c5226a4` (fix round), fast-forwarded to main;
**1153 checks** (1010 → +143 across both rounds), CI-bound push after ledger
updates. Gauntlet: Opus builder (worktree) → 3-lens Opus panel (architecture
MERGE, drift/ledger MERGE, trust FIX-FIRST) → fix round → focused Opus re-verify
(**LAND**, 8/8 claims confirmed, test diff purely additive 62/0).

**The panel's one mandatory catch (F-1):** the D1 sweep clock computed honestly
but had no render trigger — a failing/incomplete sweep under a healthy 304-ing
poll clock would hold "5 waiting" in fresh chrome indefinitely (the F3
fabrication, reintroduced one layer up). Fix: `PollState.lastSweepFreshness`
change-gated in `reducePoll` (runs every tick), `Effect.emitSweepFreshness`
appended last → `Change.sweepFreshness` → one coalesced repaint per fresh↔stale
crossing, both directions, timer-free. Two disclosed necessities verified: init
degraded (`sweepStatus(nil)`) so launch emits no fabricated crossing;
`seedFreshness(inboundSuccess:)` threads the snapshot's sweep date with the
model clock in lockstep. Known bound (in-code): a recovery's clearing crossing
lands on the next tick (~60s) — `.sweptInbound` reduces after `.polled`.

**Build-time amendments ratified:** width formulas moved to pure Core
(`PillMorph.width(for:)` — F5 lockstep by construction, `size(for:)` a wrapper);
queue-only tier shared across styles; count-free spoken parity scoped to the
composed mark (queue-only draws a count so it speaks one); 12pt inline tray in
standingCounted (optical balance vs 16pt badges); "people waiting" stays plural
at queue==1 (count-free copy must not leak count info the mark doesn't draw);
coincide note gated on a confirmed sweep (`unconfirmedNote` never claims empty).

**Proof-by-proxy note (DoD amendment):** the focus-non-theft headless pin is the
pure `PillStyleChooser.takesKeyMoment == false` + the render branch forcing
`keySessionActive = false` (inspection) — a controller-level integration assert
is not expressible in the CLT-only Core runner. Consistent with the ledger
card's own proof model.

**Dogfood watches recorded:** chooser re-presents after a must-see ledger
interlude (intended — restores interrupted intent — but unwitnessed); theme
switch while the chooser is open does not re-theme previews (pre-existing
init-time theme, observationally unchanged by the churn guard); the on-screen
repaint when a sweep crossing fires (wiring verified to the notification seam;
AppKit paint needs a live run); the user's green/red discomfort with the island
badges (color-doctrine row's first dogfood flicker — untouched, watched).
