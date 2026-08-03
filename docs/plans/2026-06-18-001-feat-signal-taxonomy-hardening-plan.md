---
title: Signal Taxonomy Hardening v2
type: feat
status: completed
date: 2026-06-18
origin: 3-model second-opinion (GPT-5.2 + Gemini 3.1 Pro + Grok 4.3) on the two-lane signal taxonomy; user-approved decisions this session
---

# Signal Taxonomy Hardening v2

Refinements to githud's two lanes from the second-opinion consensus, all user-approved:
recalibrate the H1 reason taxonomy, close the H2 CI honesty hole, never suppress a
bot's direct `@you`, and move draft PRs into their own default-off subsection.

## Architecture Decision

**Approach:** Targeted recalibration of the existing pure classifiers (no new lane, no
new pipeline). Three threads:
1. **Lane-1 reason taxonomy** — recalibrate urgencies/classes + add the missing reasons,
   under a new *enumeration-awareness* principle: model the FULL reason set as a documented
   `knownReasons` reference + conservative `default`, but only custom-handle the reasons that
   earn it now (the rest refine via dogfooding).
2. **Lane-2 CI honesty** — distinguish "no checks" (null rollup) from "unknown rollup state"
   (API drift) so a novel CI value can never falsely certify green.
3. **Draft grouping** — drafts move to their own toggleable subsection, **grouped by the
   `isDraft` PR fact, not by `PulseState`**.

**Rationale (priority: Consistency, then Simplicity):**
- Every change lives in the existing pure `SignalClassifier` / `PullRequestPulse` /
  `PulsePresenter` and mirrors a proven pattern (`SurfacePreferences`/`SurfaceStore` →
  `PulsePreferences`/`PulseStore`). New *values + one toggle*, not new *architecture*.
- **Grouping drafts by `isDraft` (not `PulseState == .draft`) is the load-bearing call.** A
  draft with failing CI rolls up to `.blocked` (state), but it's still a draft (fact) — so
  grouping on the fact pulls *all* drafts out of the main lane regardless of their rollup.
  That dissolves the second-opinion's "failing draft bubbles to the top" inversion **without
  touching the priority lattice** (which is validated + tested). The `.draft` PulseState
  stays as the glyph for a non-blocked draft.

**Rejected alternative — reorder the lattice so `isDraft` evaluates before `blocked`.** It
would also stop the inversion, but it (a) mutates a tested, validated lattice, and (b) is
*unnecessary* once grouping is by `isDraft` — the grouping already removes drafts from the
main lane. Keep the lattice; group on the fact. (Consequence: a green+approved draft shows
the `.draft` pencil glyph inside the Drafts group, not a green check — the "ready to undraft"
glyph refinement is deferred to dogfooding, not lost.)

**Rejected alternative — full per-reason enum forcing exhaustive handling.** The user
explicitly chose *aware of all, handle the ones that earn it, dogfood the rest*. A
`switch`-must-be-exhaustive enum would force premature handling of `ci_activity`/`manual`/etc.
A documented `knownReasons` set + conservative `default` gives awareness without the burden.

**Trade-offs accepted:**
- Direct `@you` from a bot now surfaces (tiny false-alarm risk) — accepted under misses-fatal.
- Drafts delivered to the view then filtered there (toggle = re-render, no refetch), so the
  poll diff key still includes drafts (a hidden draft changing triggers a cheap re-render).
- Green+approved draft shows pencil, not green, inside the Drafts group (deferred refinement).

### Predicate semantics
Reason → class is **equality** on a string `reason` (no ordering/regression concern). The
pulse lattice composes three **enumerated** members; the honesty fix is about *unrecognized*
inputs mapping to the safe member, not about comparison.

## High-Level Technical Design

```
LANE 1 (classify, recalibrated):
  review_requested 95 · mention 90 (NEVER bot-demoted — direct @you) · invitation 85(new)
  · assign 85 · security_alert 92(↑ from 80) · team_mention 70 (bot→noise) · author 65/55
  comment 40 · ci_activity 20 · state_change 15 · manual 10 · your_activity 10(new) · subscribed 0
  UNKNOWN reason → fyi/60 (↑ from 10; surfaces() already lets it through — now visible, not buried)
  knownReasons = {all 13}  ← documented enumeration reference

LANE 2 (ciState honesty):
  statusCheckRollup == null  → CIState.none      ("no checks")
  SUCCESS→passing · FAILURE/ERROR→failing · PENDING/EXPECTED→pending
  non-null UNRECOGNIZED      → CIState.pending    (fails safe — NOT ready-eligible)   ← the fix

DRAFTS (grouped by isDraft fact):
  PulseRow gains isDraft.   main = rows.filter{!isDraft} (always)
  Drafts section = rows.filter{isDraft}  (only if PulsePreferences.showDrafts, default false)
  pill gauge rollup over rows.filter{!isDraft}  (drafts never in the caught-up gauge)
  toggle: PulsePreferences{showDrafts=false} ⟶ PulseStore (UserDefaults) ⟶ menu checkbox
```
*Directional guidance for review, not implementation spec.*

## Implementation Units

### U1. Lane-1 reason taxonomy: recalibrate + add reasons + enumeration
- **Goal:** Recalibrate `classify()` (security_alert↑, direct-mention never bot-demoted,
  unknown floor↑) and add `invitation` + `your_activity`, under a documented `knownReasons`.
- **Dependencies:** None
- **Files:** Modify `Sources/GithudCore/SignalClassifier.swift`,
  `Sources/GithudCore/SurfacePreferences.swift`, `Sources/GithudCore/RadarPresenter.swift`;
  Test `Tests/GithudCoreTests/main.swift`
- **Approach:**
  - `classify()`: `security_alert` 80→**92**; `mention` → drop the bot branch (always
    actionRequired/90 — a bot `@you` by name is deliberate, e.g. PagerDuty); `team_mention`
    keeps `bot ? noise`; add `invitation` → actionRequired/85; add `your_activity` →
    fyi/10; `default` (unknown) urgency 10→**60**, class stays `.fyi` (honest — we don't
    *know* it's action-required, but it ranks visibly, not buried).
  - Add `static let knownReasons: Set<String>` = the 13 GitHub reasons (documentation +
    a testable completeness anchor).
  - `SurfacePreferences`: `autoReasons` += `invitation` (default-on); `allReasons` +=
    `invitation`, `your_activity` (display order). `your_activity` is **not** in autoReasons
    (default-off).
  - `RadarPresenter.symbolName`/`reasonLabel`: `invitation` → `envelope` / "invitation";
    `your_activity` → `person.crop.circle` / "your activity".
- **Patterns to follow:** `SignalClassifier.swift:62` (the `classify` switch),
  `SurfacePreferences.swift:11` (autoReasons/allReasons), `RadarPresenter.swift:39` (symbol/label).
- **Test scenarios:**
  - *Happy:* `security_alert` urgency == 92; `invitation` → actionRequired AND in `.auto`;
    `your_activity` → fyi AND NOT in autoReasons (default-off) but in allReasons.
  - *Bot edge:* a **bot** `mention` (latestCommentAuthor `pagerduty[bot]`) → actionRequired
    (surfaces); a **bot** `team_mention` → noise (still demoted).
  - *Unknown:* a novel reason → fyi AND urgency 60 (visible) AND still surfaced by `radar`.
  - *Completeness:* every reason in `knownReasons` has a non-default `classify` case (asserts
    we don't silently rely on the `default` for a known reason).
- **Verification:** A bot alerting you by name is never suppressed; security alerts outrank
  assign/mention; a novel reason surfaces mid-list not bottom; invitation surfaces by default.

### U2. Lane-2 CI honesty hole + pulse-state enumeration
- **Goal:** `ciState(fromRollup:)` must distinguish null (no checks) from an unrecognized
  non-null rollup state (API drift), so the latter fails safe and can never be `ready`.
- **Dependencies:** None
- **Files:** Modify `Sources/GithudCore/PullRequestPulse.swift`; Test `Tests/GithudCoreTests/main.swift`
- **Approach:** Switch on the optional explicitly: `case nil → .none`; recognized strings as
  today; **`default` (non-nil unrecognized) → `.pending`** (blocks `ready`, sorts into
  `waiting`). Document the full GraphQL enum sets in comments (StatusState:
  EXPECTED/ERROR/FAILURE/PENDING/SUCCESS; MergeableState: MERGEABLE/CONFLICTING/UNKNOWN;
  reviewDecision: APPROVED/CHANGES_REQUESTED/REVIEW_REQUIRED/null).
- **Patterns to follow:** `PullRequestPulse.swift` `ciState(fromRollup:)` + the honesty mappers.
- **Composition matrix (CI honesty):**
  | Input | CIState | ready-eligible? | Test |
  |---|---|---|---|
  | `nil` (no rollup) | `.none` | yes (no checks) | `ci_null_none` |
  | `"SUCCESS"` | `.passing` | yes | (existing) |
  | `"FAILURE"`/`"ERROR"` | `.failing` | no (blocked) | (existing) |
  | `"NEUTRAL"`/`"SKIPPED"`/any non-nil unknown | `.pending` | **no (waiting)** | `ci_unknown_pending` |
- **Test scenarios:**
  - *Happy:* `nil` → `.none`; `"SUCCESS"` → `.passing` (unchanged).
  - *Drift (the fix):* `"NEUTRAL"` / `"SKIPPED"` / `"WAT"` → `.pending`, NOT `.none`; a PR with
    that CI + approved + mergeable rolls up to `.waiting`, **not `.ready`** (no false green).
- **Verification:** No unrecognized CI value can produce a `ready` verdict; `nil` still reads
  honestly as "no checks".

### U3. Draft model + PulsePreferences + PulseStore
- **Goal:** `PulseRow` carries `isDraft`; a persisted `PulsePreferences{showDrafts=false}`.
- **Dependencies:** None
- **Files:** Modify `Sources/GithudCore/PulsePresenter.swift`; Create
  `Sources/GithudCore/PulsePreferences.swift`, `Sources/GithudApp/PulseStore.swift`;
  Test `Tests/GithudCoreTests/main.swift`
- **Approach:** Add `isDraft: Bool` to `PulseRow`; `PulsePresenter.row` sets it from
  `pulse.isDraft`. `PulsePreferences` = a value type with `showDrafts: Bool` + `static let
  `default` = .init(showDrafts: false)` + a `togglingShowDrafts()`. `PulseStore` load/save a
  Bool under `githud.pulse.showDrafts` (mirror `SurfaceStore`).
- **Patterns to follow:** `PulsePresenter.swift` `row(for:now:)`; `SurfacePreferences.swift`
  (value+toggling shape); `SurfaceStore.swift` (UserDefaults load/save).
- **Test scenarios:**
  - *Happy:* `PulseRow.isDraft` reflects the PR; `PulsePreferences.default.showDrafts == false`;
    `togglingShowDrafts()` flips it.
  - *Edge:* a row built from a draft PR has `isDraft == true`; non-draft `false`.
- **Verification:** Draft-ness is carried on the display row; the default is drafts-hidden.

### U4. Draft grouping in UI + gauge exclusion + menu toggle
- **Goal:** Main lane shows non-drafts; a default-off "Drafts" subsection; the pill gauge
  excludes drafts; a "Show draft PRs" menu checkbox drives it (re-render, no refetch).
- **Dependencies:** U3
- **Files:** Modify `Sources/GithudApp/IslandContentView.swift`,
  `Sources/GithudApp/CollapsedPillView.swift`, `Sources/GithudApp/HUDPanelController.swift`,
  `Sources/GithudApp/AppDelegate.swift`, `Sources/GithudApp/StatusItemController.swift`
- **Approach:**
  - `IslandContentView(rows:pulse:showDrafts:onSurfaceTap:)`: render `pulse.filter{!$0.isDraft}`
    as the "Your PRs" section; if `showDrafts`, append a `sectionHeader("Drafts")` +
    `PulseRowView`s for `pulse.filter{$0.isDraft}` (cap + "+N more", like the main lane).
  - `CollapsedPillView`: rollup over `pulse.filter{!$0.isDraft}` (drafts never gauge).
  - `HUDPanelController`: hold `showDrafts` (default false) + `setPulsePreferences(_:)` →
    re-render; pass `showDrafts` to `IslandContentView`, filter drafts for the pill.
  - `AppDelegate`: `pulsePreferences = PulseStore.load()`; pass initial `showDrafts` to the
    HUD; wire `onToggleShowDrafts` → flip + `PulseStore.save` + `hud.setPulsePreferences`.
  - `StatusItemController`: in `menuNeedsUpdate(surfaceMenu)`, after the reason items add a
    `.separator()` + a "Show draft PRs" checkbox (state from `currentPulsePreferences()`),
    action → `onToggleShowDrafts`. Two new closures on `init`.
- **Patterns to follow:** `IslandContentView.swift` (the H2 "Your PRs" section +
  `sectionHeader`); `AppDelegate.swift:53` (`toggleReason` → store → re-render);
  `StatusItemController.swift:62` (`menuNeedsUpdate` rebuild + checkmarks).
- **State-Action contract (showDrafts toggle):**
  | Action × state | Caller obs. | Durable | Side effect | Test |
  |---|---|---|---|---|
  | toggle while drafts hidden | menu check flips on | `githud.pulse.showDrafts=true` | island re-renders WITH Drafts section | manual/visual |
  | toggle while drafts shown | check flips off | `=false` | Drafts section removed; main lane + gauge unchanged | manual/visual |
  | new pulse arrives, drafts hidden | — | unchanged | main lane + gauge over non-drafts only | live |
  - **Invariant:** the pill gauge reflects `!isDraft` PRs **regardless** of `showDrafts`
    (the toggle only affects the expanded Drafts section, never the calm glance).
- **Test scenarios:**
  - *Happy (pure-testable):* given rows incl. drafts, `rollup(rows: rows.filter{!$0.isDraft})`
    excludes draft states — extract/verify the non-draft filter feeds the gauge.
  - *Edge:* all-draft pulse + drafts hidden → main lane empty ("nothing"), gauge falls back to
    its non-draft/empty state.
  - *Integration:* `--fixture-pulse` render with `showDrafts` off then on (visual proof in U5).
- **Verification:** Drafts absent from the main lane + gauge by default; the toggle reveals a
  separate Drafts group and persists; the calm-glance pill never counts drafts.

### U5. Verification — tests, fixture, live probe, visual proof
- **Goal:** Prove the batch end-to-end and lock it.
- **Dependencies:** U1–U4
- **Files:** Modify `Tests/Fixtures/pulls.json` (ensure ≥2 drafts so the section is non-trivial),
  `Tests/GithudCoreTests/main.swift`, `Sources/GithudApp/ProbeCommand.swift` (note draft count
  in the redacted pulse histogram)
- **Approach:** Full suite green; `githud probe` unregressed (pulse histogram still redacted,
  drafts counted); two visual-proof manifests — `--fixture-pulse` with drafts OFF (default;
  no Drafts section) and ON (Drafts section present). Confirm evidence stays redacted.
- **Patterns to follow:** `ProbeCommand.swift` redacted histogram; `scripts/visual-proof.sh`
  (`GITHUD_ARGS`).
- **Test scenarios:** *Happy:* fixture decodes; the probe evidence histogram has no PR
  titles. *Privacy:* assert no title/repo substring in evidence (existing guard extends).
- **Verification:** `githud probe` runs on the live PAT; both draft states render; evidence redacted.

## Scope Boundaries
- **No lattice reorder** — the priority lattice (blocked>ready>waiting>draft) is unchanged;
  drafts are handled by *grouping on `isDraft`*, not by changing state precedence.
- **No new pulse data** — still the one `viewer.pullRequests` GraphQL query (no per-check drill-down).
- **No write actions** — read-only; Open-on-GitHub only (H3 guardrail).
- **`your_activity` stays minimally handled** — fyi/low, default-off; refine via dogfooding.

### Deferred to Follow-Up Work
- **Split `waiting` into waiting-on-human vs waiting-on-compute** — keep one bucket for now;
  the row subtitle already names the reason ("review required" / "CI running" / "checking…").
  Revisit after dogfooding shows whether the glance needs the distinction.
- **"Ready to undraft" glyph** — show a green+approved draft with its real state glyph inside
  the Drafts group (instead of the `.draft` pencil). Deferred refinement.
- **Per-reason handling of `ci_activity`/`state_change`/`manual`** beyond current defaults —
  dogfood-driven.

## System-Wide Impact
- **Interaction graph:** `onToggleShowDrafts` parallels `onToggleReason`; `HUDPanelController`
  gains `showDrafts` alongside `currentPulse`; `render()` filters/groups by `isDraft`.
- **Error propagation:** none new — all changes are pure mapping + view grouping; no new I/O.
- **State lifecycle:** `showDrafts` persists in UserDefaults; toggling is a re-render from the
  cached `currentPulse` (no refetch), exactly like `SurfacePreferences`.
- **API surface parity:** the H2 pulse lane is the only consumer of `PulseRow`; the probe also
  reads pulses (counts drafts) — both updated.
- **Unchanged invariants:** the H1 radar pipeline, the pulse priority lattice + sort, the
  honesty contract for review/merge, conditional polling, focus-non-theft, idle-footprint,
  the classic-PAT WALL — all explicitly unchanged. The pill gauge stays a non-draft glance.

## Risks & Dependencies
| Risk | Mitigation |
|------|------------|
| Direct bot `@you` adds false alarms | Rare in practice; misses-fatal bias accepts it; team_mention/author/comment still bot-demoted |
| `mergeable==UNKNOWN` never resolves → PR stuck "checking…" | Already mitigated by the ~60s repoll (querying `mergeable` triggers GitHub's lazy compute; next poll reads it). No change; noted not a deadlock |
| Unknown reason at urgency 60 could outrank a real FYI | Intentional under never-miss; it's a *novel* reason we can't classify — better seen than buried; dogfooding re-tunes |
| Draft grouping by `isDraft` vs lattice `.draft` confusion | Documented as the central decision; the lattice is untouched and tested; grouping is a view-layer filter on a model fact |
| Menu checkbox state drift | `menuNeedsUpdate` rebuilds `surfaceMenu` from `currentPulsePreferences()` on every open (same pattern as reasons) |

## Confidence cross-check — second-opinion findings → units
| Finding (motivating "bug") | Unit / clause | Resolution | Match? |
|---|---|---|---|
| Unrecognized CI → `none` false-certifies green | U2 | non-nil unknown → `.pending` (not ready) | ✓ |
| `security_alert` under-ranked (80 < assign/mention) | U1 | → 92 | ✓ |
| Unknown reason surfaced-but-buried (fyi/10) | U1 | urgency → 60, still fyi | ✓ |
| `invitation` unhandled | U1 | actionRequired/85, default-on | ✓ |
| Bot demotion suppresses direct alert pings | U1 | direct `mention` never bot-demoted | ✓ |
| Draft with failing CI bubbles to top (inversion) | U3+U4 | grouped by `isDraft`, default-off → leaves main lane | ✓ |
| `waiting` conflates human vs compute | Deferred | one bucket; subtitle disambiguates | deferred (noted) |
| `mergeable UNKNOWN` could deadlock | Risks | mitigated by 60s repoll; no change | ✓ (verified) |
