---
title: Radar monochrome glyphs (drop the urgency heat scale)
type: refactor
status: completed
date: 2026-06-20
completed: 2026-06-20 (iter 30)
origin: user insight ("the app IS urgency") + 3-model /second-opinion (GPT-5.2 + Gemini 3.1 Pro + Grok 4.3)
---

## Built — iter 30, with doctrine amendments (consult 008, GPT Pro)

Shipped as part of landing the **color doctrine** (`/agentify` GPT-Pro extended-pro,
consult 008, 9m56s). The doctrine *confirmed* this plan's direction (Option C: mono +
one critical override) and *upgraded* it on three points:

1. **Critical is a separate SORT dimension, not just a glyph color.** GPT caught a live
   coherence bug this plan missed: `review_requested` (urgency 95) outranks
   `security_alert` (urgency 92), so the lone red glyph would render *below* a calm mono
   row. Fix: `SignalClassifier.radar()` now sorts **critical-first, then urgency, then
   recency**; criticality is `SignalClassifier.criticalReasons` (single source of truth,
   reused by sort + glyph + pill). Proven on the real fixture (security_alert 1005 sorts
   above review_requested 1001 despite lower urgency; urgency stays 92 — salience, not a
   magic-100 bump).
2. **Ordinary radar glyph = `inkSecondary`, not `inkPrimary`.** Ink-by-default means the
   glyph recedes (shape carries kind); the red critical pops *harder* against a dim field.
3. **H2 yellow removed in the same pass (doctrine-coupled).** `waiting` → `inkSecondary`
   outline clock (ordinary in-flight is NOT caution); `draft` → `inkTertiary`. Yellow is
   gone from every state; `caution` is reserved for degraded *reading* confidence
   (freshness), `warn` deprecated. `green` stays narrowly = `ready` (merge unlocked), never
   "alive". This resolves the user's "green=alive?" question (no) + "yellow's fate" (gone).

API delta from the plan body: the method is `radarGlyphColor(critical:)` (as planned),
the ordinary tint is `inkSecondary` (plan said `inkPrimary`). Visual-proven iter 30
(manifests 300 Color / 301 GitHub / 302 Solarized-Light expanded + 303 collapsed critical
pill, all `pixel_live`); blind read confirmed the lone red security shield on top + zero
yellow. 254 checks. Doctrine recorded in `loop/creative-consults.md` (Consult 008) +
`loop/INTENT.md` (iter-30 reframe) + pressure row `color-doctrine`.

# Radar monochrome glyphs — drop the urgency heat scale

The H1 radar glyph color currently encodes a 4-level **urgency** heat scale. But urgency
is already encoded twice (the classifier FILTERS to action-required; the SORT orders by
urgency), so color is a redundant 3rd encoding that spends the scarce "salience budget"
on a solved problem. Drop the heat scale → **monochrome glyphs** (shape = kind), keeping
exactly ONE reserved color: a **critical/emergency flag** (`security_alert`) that still
pops pre-attentively. H2 pulse state-color is untouched.

## Architecture Decision

**Approach:** Replace `Theme.radarUrgencyColor(_ urgency: Int)` (the 4-level red/orange/
yellow/gray heat scale) with `Theme.radarGlyphColor(critical: Bool)` → `danger` when the
item is critical, else `inkPrimary` (monochrome). "Critical" is a global, reason-based
policy: `SignalClassifier.criticalReasons = ["security_alert"]` — a categorically
different *emergency* (a live vulnerability), not just a higher urgency number. The
collapsed pill mirrors it (danger glyph only when a critical item is present, else ink).
H2 `pulseGlyph` (state color) and the badge accent are unchanged.

**Rationale (priority: Simplicity, then Consistency):**
- **Urgency is doubly-encoded already** (filter + sort) — the 4-level gradient is
  redundant. All 3 second-opinion models agreed; the user's "the app IS urgency" is the
  same insight. Color is a scarce pre-attentive resource (Feature Integration Theory) —
  reserve it for non-redundant info.
- **But a `security_alert` is not "more urgent" — it's a different KIND of urgent**
  (act-now-or-risk). It earns the one reserved color so a genuine emergency still pops,
  *especially on the collapsed pill* (the entry point — a fully-mono pill can't recruit
  the eye for a fatal miss; the strongest second-opinion point). This is an **emergency
  flag (binary), not a heat scale (gradient)** — so it doesn't reintroduce the redundancy.
- **Color now reserved for non-redundant info:** H2 state + the H1 emergency. This mirrors
  the events-vs-state split (H1 = events that all need you; H2 = standing state) — color
  carries what shape/sort/filter can't.

**Rejected — full monochrome (no critical accent)** (Grok's position, 0.8): cleaner, but
the collapsed pill (the always-visible glance) loses its only "should I look?" cue for a
real emergency. Under "misses are fatal," the marginal extra calm isn't worth dropping the
security-alert pop. *Consequence:* `criticalReasons` is a one-element set — emptying it
yields full-mono, so this stays a one-line policy change if dogfooding says drop it.

**Rejected — keep the 4-level heat scale:** redundant + attention-theft; all 3 models +
the user reject it.

**API discipline:** the method drops the `urgency: Int` param it no longer uses — callers
stop threading urgency for color (the sort already owns urgency). `RadarRow` gains
`isCritical` (computed once in the presenter) so the view is dumb (`theme.radarGlyphColor(
critical: row.isCritical)`), and the criticality *policy* lives with the classifier, not
the view.

### Composition matrix (urgency-heat → mono + critical-flag)
**Old scalar:** glyph color = one of 4 urgency tiers (red/orange/yellow/gray), everywhere
the radar renders (rows + pill). **New:** glyph color = ink (default) | danger (critical).
**Consumer surfaces:** `RadarRowView` (row glyph), `CollapsedPillView` (pill glyph).
**Owner:** classifier defines `criticalReasons`; presenter stamps `RadarRow.isCritical`;
theme maps `critical → danger / else ink`; views render.

| Case | Visible contract | Source | Test |
|---|---|---|---|
| ordinary reason (review/mention/assign/author) | glyph = `inkPrimary` (mono) | `isCritical=false` | `glyph_mono_for_ordinary` |
| `security_alert` | glyph = `theme.danger` (the one reserved pop) | `isCritical=true` | `glyph_danger_for_critical` |
| pill, no critical present | pill glyph = ink (calm) | no row `isCritical` | `pill_mono_when_no_critical` |
| pill, a critical present | pill glyph = danger (recruit the eye) | any row `isCritical` | `pill_danger_when_critical` |
| H2 pulse (unchanged) | state color preserved (blocked/ready/waiting) | `pulseGlyph` untouched | (existing pulse tests) |

**Red flag check:** after this, no radar surface renders a *gradient*; the only radar
color is the binary emergency flag (grep: `radarUrgencyColor` is gone).

## Implementation Units

### U1. Critical-reason policy + `RadarRow.isCritical` + `Theme.radarGlyphColor`
- **Goal:** Define the emergency policy, carry it on the row, and map it to a color.
- **Dependencies:** None
- **Files:** Modify `Sources/GithudCore/SignalClassifier.swift` (add `criticalReasons`),
  `Sources/GithudCore/RadarPresenter.swift` (`RadarRow.isCritical` + set it),
  `Sources/GithudApp/Theme.swift` (`radarGlyphColor(critical:)`, drop `radarUrgencyColor`);
  Test `Tests/GithudCoreTests/main.swift`
- **Approach:** `SignalClassifier.criticalReasons: Set<String> = ["security_alert"]`.
  `RadarRow` gains `isCritical: Bool`; `RadarPresenter.row` sets it via
  `SignalClassifier.criticalReasons.contains(thread.reason)`. `Theme.radarGlyphColor(critical:
  Bool) -> NSColor` returns `critical ? danger : inkPrimary`; delete the urgency-tier method.
  (Keep `RadarRow.urgency` — still used by the sort upstream; it just no longer drives color.)
- **Patterns to follow:** `SignalClassifier.knownReasons` (a reason set), `RadarPresenter.row`
  (sets row fields), `Theme.pulseGlyph` (the themed-glyph shape).
- **Test scenarios:**
  - *Happy:* a `security_alert` thread → `RadarRow.isCritical == true`; a `review_requested`/
    `mention`/`author` thread → `false`.
  - *Edge:* `criticalReasons` contains exactly `security_alert` (the one emergency reason).
  - *(Theme color mapping is GithudApp — verified by visual proof in U3; the `isCritical`
    flag is the pure-testable part.)*
- **Verification:** Only `security_alert` is critical; the row carries it; the urgency-heat
  method is gone.

### U2. View call sites → monochrome glyphs + critical pill
- **Goal:** Radar row glyphs render mono (ink) except critical (danger); the collapsed pill
  glyph is danger only when a critical item is present.
- **Dependencies:** U1
- **Files:** Modify `Sources/GithudApp/IslandContentView.swift` (`RadarRowView`),
  `Sources/GithudApp/CollapsedPillView.swift`
- **Approach:** `RadarRowView`: `icon.contentTintColor = theme.radarGlyphColor(critical:
  row.isCritical)`. `CollapsedPillView` radar branch: tint = `theme.radarGlyphColor(critical:
  rows.contains { $0.isCritical })` (any critical → danger pill; else ink) — so the pill
  recruits the eye only for a real emergency.
- **Patterns to follow:** `IslandContentView` RadarRowView icon tint (the line being changed),
  `CollapsedPillView` radar-glyph branch.
- **Test scenarios:** Test expectation: view code — covered by U3 visual proof (mono radar,
  red `security_alert`, mono/red pill).
- **Verification:** Radar reads monochrome with one red security glyph; pill mono unless a
  critical is present.

### U3. Verify — visual proof + tests
- **Goal:** Prove the radar is monochrome-with-one-critical, the pill is critical-aware, H2
  is unchanged, across themes.
- **Dependencies:** U1, U2
- **Files:** Modify `Tests/GithudCoreTests/main.swift`
- **Approach:** Visual proof (expanded) in 2–3 themes (Color + a dark + Solarized Light)
  showing mono radar glyphs + the lone red `security_alert` + unchanged H2 state colors;
  collapsed-pill proof with and without a critical present (`--collapsed`). Pure tests for
  `isCritical` (U1). Confirm idle_cpu unchanged.
- **Patterns to follow:** `scripts/visual-proof.sh` (`GITHUD_ARGS` + `--theme`/`--collapsed`).
- **Test scenarios:** *Happy:* fixture renders mono radar + one red shield; H2 colors intact.
  *Pill:* critical-present → red pill; none → ink pill.
- **Verification:** Visual proof across themes; `isCritical` tests green; full suite passes.

## Scope Boundaries
- **No change to H2 pulse** — state color (blocked/ready/waiting) stays; it's non-redundant info.
- **No change to sort or filter** — urgency still drives the radar's order + inclusion.
- **`criticalReasons` = {security_alert} only** — not a tunable threshold; the one categorical
  emergency. (Reviewer/blocking-review is "needs you" but can sequence — not an emergency.)

### Deferred to Follow-Up Work
- An accessibility shape-cue for the critical glyph (outline ring) so it doesn't rely on
  color alone — the second-opinion's a11y note; defer unless dogfooding needs it.
- If H2's color is found to invert the visual hierarchy (eye → H2 over H1), tone H2
  saturation. Watch, don't pre-build.

## System-Wide Impact
- **Interaction graph:** `criticalReasons` (classifier) → `RadarRow.isCritical` (presenter) →
  `radarGlyphColor` (theme) → `RadarRowView`/`CollapsedPillView` (render). One-directional.
- **State lifecycle:** none — pure presentation; no persistence, no I/O.
- **Unchanged invariants:** the classifier's action-class/urgency, the sort order, H2 pulse
  state color, the gauge, all 9 themes' other tokens, idle-footprint, focus-non-theft,
  the classic-PAT WALL. Only the radar GLYPH TINT changes.

## Risks & Dependencies
| Risk | Mitigation |
|------|------------|
| Hierarchy inversion (eye → colored H2 over mono H1) | H1 is on top + has the accent badge + critical-red when present; watch, tone H2 if it manifests (deferred) |
| Mono radar loses "is the top a drop-everything?" glance | The one reserved critical flag (security_alert) covers the genuine emergency; ordinary urgency was already redundant with sort |
| Pill goes red too often | `criticalReasons` = only security_alert (rare); not a 90+ threshold (which would catch review/mention) |
| Color-only critical fails a11y | Shape-cue deferred; security_alert already has a distinct shield SHAPE, so it's not color-only |

## Confidence cross-check
| Requirement (from the insight + 2nd opinion) | Unit | Match? |
|---|---|---|
| Drop the 4-level urgency heat (redundant) | U1, U2 | ✓ |
| Radar glyphs monochrome (shape=kind) | U1, U2 | ✓ |
| Keep ONE critical accent (security_alert) | U1, U2 | ✓ |
| Pill recruits the eye only for an emergency | U2 | ✓ |
| H2 state color unchanged | Scope | ✓ |
| `criticalReasons` empty → full-mono (one-line) | U1 | ✓ (knob) |
