# Seed: the pill redesign (D-pill session)

*Pre-compact distillation, 2026-07-09. The next session picks this up when the user says
go on "the new pill design".*

## Why now

The collapsed pill's vocabulary grew organically to a FOUR-fact tier ladder, and the
newest tier was an expedient fix, not a design: loading dot > radar glyph+count >
pulse gauge (✓ready·⚠blocked segments) > **inbound tray+count (added 9012859 as the
fix-round BLOCKER remedy, reusing the radar-count cell)** > check. Stale caution-clock
prefix composes over all.

## The design question

One-fact-at-a-time is now lossy three ways: a radar count HIDES both the gauge and the
queue; the gauge HIDES the queue. Is the pill (a) a priority ladder showing the single
most-actionable fact (today), (b) a composed multi-segment strip (the gauge already
composes segments — extend that grammar to lanes), or (c) something else? Subordinate:
does the inbound tier keep the tray glyph, and does the check need any redesign now that
it means "all three lanes confirmed-empty-ish"?

## Constraints that bind (doctrine + ratified)

- Slot-morph chassis (WP-3x, ratified): prefix/glyph/value cells; equal-digit ticks 0ms;
  changed cell fades 120ms; width settles 150ms; "no motion where no fact changed".
- Color doctrine: gauge's success/danger are RATIFIED uses; inbound is ink; no new color
  without a changed-next-move argument. A11y law: gray-swap must survive.
- Spoken parity: `PillAccessibilityPresenter` must speak what is drawn (it already
  speaks the FULL stack incl. "N waiting at your door" — the drawn pill is the lossy one).
- The pill's all-clear check is the ratified WEAKER count-gated claim (agenda item f as
  corrected); the island affirmation holds the strong `inboundConfirmed` gate.
- The BAR glyph stays radar-only (ratified, distinct surface — not in scope).
- Calm: the pill is the always-visible surface; attention-non-theft binds hardest here.

## Process (the pattern the user ratified last time)

Designer-session shape: N designer agents propose named pill-vocabulary variants with
full parameter specs, N adversarial refuters attack them against doctrine, survivors
render as an interactive HTML mock gallery (artifact), user ratifies in one line, then
the build runs the standard gauntlet. Subagents on OPUS (standing user directive;
ultracode is OFF — use parallel Agent spawns, not Workflow, unless the user re-opts-in).

## Facts a designer needs

- Pill geometry: height fixed; width formulas in `CollapsedPillView.size(for:)`
  (radar/inbound count: 18+6+digits*10+26; gauge: 24 + per-segment 16+4+digits*9 + 6 gaps;
  bare: 52; stale pad +19). Fixed 12/13pt glyphs, monospacedDigit counts.
- Current live user state (for honest mocks): radar usually 0-6, pulse ~7 active
  (blocked+ready), inbound 5 human + 3 held-back.
- Code homes: `Sources/GithudCore/PillMorph.swift` (fingerprint/plan),
  `Sources/GithudApp/CollapsedPillView.swift` (drawing/size),
  `PillAccessibilityPresenter.swift` (spoken), `StatusGlyphPresenter` (bar — out of scope),
  `HUDPanelController` collapsed-render (call sites).
- Mock precedent: docs/design/2026-07-06-designer-session-mocks.html (the gallery
  pattern + its CSS/pill renderings to match).

## Session record (2026-07-09/10 — ran to the ratification gate)

The session ran: 3 Opus designers (ladder / composed / third-way) → 6 named variants →
3 Opus refuters (calm+color / honesty+trust / mechanics), all structural claims
code-verified. Output: **docs/design/2026-07-09-dpill-session-mocks.html** (interactive
gallery; also published as a claude.ai artifact). Both composed variants KILLED
(F2 double-count + F4 two-reds breaking the PAID blind-read + misrepresented mechanics).
Runner recommendation: **ladder-strict amended** — D1 per-fact stale clock + D2
inbound-above-gauge reorder + D3 strict vocabulary + tray.fill.

Findings that outlive the session regardless of the pick (F-numbers in the gallery):
- **F1** today's inbound pill tier is dead code for this user (gauge branch precedes it).
- **F2** radar∩inbound can double-count one fresh PR — bites only dual-count designs.
- **F3 (open honesty exposure, pre-existing):** the pill's stale prefix keys off
  radar/pulse freshness only; the sweep never feeds it and the adopt rule holds items
  through failed sweeps — any chronic inbound COUNT can render adopted-stale under
  fresh chrome. Close via per-fact stale clock, or keep elevated inbound count-free.
- **F4** shield ⊥ gauge colors today — the PAID lone-red blind-read rests on it.
- **F5** the ladder order lives unpinned in 3 files (fingerprint/size/bodyValue); any
  reorder owes a lockstep edit ×3 + a new order-pinning test.

RESOLVED 2026-07-10: the user ratified a CONFIG, not a single vocabulary ("allow
config with actual visual preview… provide a default but user can switch it up"),
after holding both truths (supersede reads calmer / a superseding queue walls off
the gauge — a ladder tier must be self-clearing). Built + landed through the full
gauntlet as WP 2026-07-10-001 (acadf99 + c5226a4, 1153 checks): PillStyle
(queueLeads default / standingMarked / standingCounted), the gear "Pill style…"
chooser card with live previews, and the D1 per-fact stale clock incl. the F-1
crossing emission. See docs/plans/2026-07-10-001-dpill-config-wp.md (landing
record) and the gallery's Decide rev. 3.
