---
title: Per-org draft tails — the owner lens takes drafts
objective: An owner group answers "what's happening here" completely — your WIP sits under the org it belongs to, and folding an org finally hides everything it owns.
type: feat
status: completed
date: 2026-07-26
origin: docs/design/2026-07-26-per-org-drafts-mocks.html
---

## Background (read cold)

The "Your PRs" lane splits into three regions — `active`, `stale`, `drafts` — computed by
`PulsePresenter.sections(for:)`. The owner lens (WP 2026-07-14-001) groups, orders, and folds
owners, but it governs **only** the active region. That was ratified deliberately, with an exit:

> "Two grammars coexist by scope: the eye is org-grouping's control; the stale / bots & drafts /
> drafts families keep their ratified word-captions. **Open mic: converge them later if dogfood
> wants one grammar.**"
> — `docs/design/2026-07-12-org-grouping-mocks.html`, spec line 4 of six

2026-07-26 dogfood exercised that exit: *"i realize draft PR is a separate section from orgs..
while I was expecting them to show at the bottom of each org section."* Variant V1 (draft tail
inside each group) was ratified, along with the call that a **draft-only owner is a first-class
lens org** — listed in the Owners card, foldable, draggable.

**The constraint the record hands us.** Drafts were pulled into their own region on 2026-06-18 and
grouped by the `isDraft` *fact*, not by `PulseState`, precisely because a draft with failing CI
rolls up to `.blocked` and bubbles to the top of the sort
(`docs/plans/2026-06-18-001-feat-signal-taxonomy-hardening-plan.md:33`). Reordering the priority
lattice so `isDraft` beats `blocked` was considered and rejected. Therefore: **a draft may never
rejoin its group's state sort.** The tail is positional.

**Two spec corrections made during architecture** (the ratified doc predates them):

1. **"Draft PRs as a region retires" is wrong.** `lensLayout` emits groups only when
   `groupByOwner && leading.count >= 2`; otherwise one flat run. A tail is a *group* affordance —
   the same logic the code already states for drag order (`PulsePresenter.swift:371`: "the drag
   order is a GROUP order; a flat list has no groups to order"). The terminal region **survives as
   the flat-shape form**.
2. **A draft-only owner must not change the lane's shape.** If facebook counted toward
   `leading.count >= 2`, flipping `showDrafts` could flip a one-live-owner lane from flat to
   grouped. The shape trigger keeps counting **live** owners only.

**Live shape at time of writing** (`viewer.pullRequests`, 2026-07-26): 25 open — 11 active,
5 stale, 9 draft. Active owners: acme (4), pro-vi (7). Draft owners:
acme (5), pro-vi (3), **facebook (1)** — an owner the lens has never seen.
Author's prefs: `groupByOwner=1`, `foldedOwners=()`, `ownerOrder=[pro-vi, acme]`,
`showDrafts=1`, `showStale=1`.

## Architecture Decision

**Approach:** Widen the lens's domain from `sections.active` to `(live, drafts)`, and give
`LensEntry.group` a `tail`. The lens remains the single home of owner partitioning;
`PulseSections` remains the single home of the live/stale/draft split.

**Rationale (Consistency, then Testability):** The credible alternative was building the tail in
the view — `IslandContentView` appends `sections.drafts.filter { owner == group.owner }` under each
group. Smaller diff, no Core change. Rejected: it puts the grouping rule in the App layer where the
Core-only test runner cannot see it, and this branch's history is explicit that every real bug on
the owner-lens WP lived in App-side seams the Core runner couldn't reach (key-session gate,
hitTest, stale `selfLogin`). Owner partitioning is exactly the pure, table-testable rule that
belongs in `PulsePresenter`.

**API-discipline check:** Two consumers walk lens entries — `IslandContentView.swift:219` and
`KeySession.swift:44`. Under the view-side alternative **both** write the same
`drafts.filter { owner(of:) == group.owner }` boilerplate, the tell that the API sits at the wrong
level. `tail` inside `.group` removes it from both.

**Trade-off accepted:** `LensEntry.group` gains an associated value, so every pattern match breaks
at compile time. That is desirable — the compiler enumerates the call sites — but U1 must
mechanically touch all of them to stay green.

## Integration-shape verification

`LensEntry` is a Core enum with three cases. Grepped call sites matching `.group`:

| Site | Current shape | After U1 |
|---|---|---|
| `Sources/GithudApp/IslandContentView.swift:229` | `case .group(_, let title, let groupRows)` | + `tail`, rendered (U4) |
| `Sources/GithudCore/KeySession.swift:48` | `case .group(_, _, let rows)` | + `tail`, ignored in U1, walked in U5 |
| `Tests/GithudCoreTests/main.swift:4639,4648` | `visibleIDs` / `ledgerTotal` helpers | + tail arm, else fold-not-filter test lies |

No adapter unit needed — direct enum widening, identical types, no bridge.

**Production failure mode found during this check:** the current implementation force-unwraps
`byOwner[key]!` at `PulsePresenter.swift:363,375,380,385`. With two partition maps (live owners,
draft owners), a draft-only key is absent from the live map and `byOwner[key]!` **crashes in
production**. U1 must use one merged partition holding both arrays; no force unwrap survives.

## Invariants

- `group.tail` is non-empty **iff** that owner has ≥1 row in the `drafts` input.
- `drafts == []` **iff** `showDrafts == false` — the pref gates at the **caller**, so the lens holds
  one rule and a folded ledger never claims drafts the pref is hiding lane-wide.
- shape is grouped **iff** `groupByOwner && liveLeadingOwners.count >= 2` — unchanged by drafts.
- **Fold-not-filter, extended:** every input row, live or draft, appears exactly once — as a visible
  row, a tail row, or inside a ledger count — in BOTH shapes.
- **Inversion guard:** within a group, `tail` renders after `rows` positionally and is never merged
  into the state sort.

## State–Action Contract Matrix

Axis: lane shape × owner composition. `showDrafts=on` throughout (off collapses to today's
behavior by the gating invariant above).

| Owner composition | Grouped shape | Flat shape | Ledger when folded | Key walk | Locking test |
|---|---|---|---|---|---|
| live only (4 live, 0 draft) | title + 4 rows, no tail | rows in flat run | `pro-vi · 4` | 4 ids | `lens: no drafts → no tail` |
| live + drafts (4 live, 5 draft) | title + 4 rows + `5 drafts` tail | rows flat; drafts to terminal region | `acme · 4, 5 drafts` | 4 + 5 ids, tail last | `lens: tail follows rows` |
| draft-only (0 live, 1 draft) | title + tail only, sinks below live owners | no group; draft to terminal region | `facebook · 1 draft` | 1 id | `lens: draft-only owner gets a group` |
| folded, live + drafts | ledger line only, tail hidden with it | ledger line only | `acme · 4, 5 drafts` | 0 ids | `lens: fold hides the tail too` |
| >2 folded | merged `elsewhere · N, M drafts` | same | merged | 0 ids | `lens: elsewhere sums both` |

**Fresh clock:** `N new` counts **live rows only**. A draft the author opened themselves is not
work that arrived; with 9 open drafts, counting them would make
`acme · 4, 5 drafts, 3 new` permanently noisy. Reversible one-liner.

**Omitted-state challenge:**
- *`selfLogin` nil during auth* — a draft-only owner that is actually yours renders its raw login
  until login resolves; identical to today's groups, no new cell.
- *An owner whose live rows all go stale* — becomes draft-only mid-session, its group sinks below
  live owners on next render. Covered by the draft-only row; the transition gets a pinned test.

## Implementation Units

### U1. Core: the lens takes drafts

- **Goal:** `lensLayout` partitions live + drafts per owner and emits groups carrying a tail.
- **Advances:** ratified spec S1, S3
- **Dependencies:** None
- **Files:**
  - Modify: `Sources/GithudCore/PulsePresenter.swift`
  - Modify: `Sources/GithudApp/IslandContentView.swift`, `Sources/GithudCore/KeySession.swift` (mechanical, to compile)
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** `lensLayout(live:drafts:prefs:selfLogin:lastOpened:)`; `.group` gains
  `tail: [PulseRow]`. One merged partition `[String: (live: [PulseRow], drafts: [PulseRow])]` —
  no force unwrap. Group rank still comes from the lead **live** row; draft-only owners rank after
  all live owners among **unplaced** keys, while `ownerOrder` continues to outrank everything (a
  placed draft-only owner can lead). Shape trigger counts live leading owners only.
- **Patterns to follow:** `Sources/GithudCore/PulsePresenter.swift:342` — same
  partition-then-`lensOrderedKeys` skeleton; `:265` `sections(for:)` for region vocabulary.
- **Test scenarios:**
  - *Happy path:* 2 live owners + drafts → each group's tail holds only its owner's drafts, after its rows.
  - *Inversion guard:* group with a `.blocked` draft + a `.ready` live row → blocked draft renders LAST (2026-06-18 regression pin).
  - *Edge case:* draft-only owner → group with empty rows, sunk below live owners; placed in `ownerOrder` → leads.
  - *Edge case:* 1 live owner + 1 draft-only owner + `groupByOwner=true` → FLAT, not grouped.
  - *Edge case:* `drafts: []` → entries byte-identical to today's `lensLayout(active:)`.
  - *Integration:* fold-not-filter — every live+draft row appears exactly once across rows/tails/ledger counts, both shapes.
- **Verification:** All five invariants hold; no force unwrap remains in `lensLayout`.

### U2. Core: the folded ledger tells both facts

- **Goal:** A folded owner's line admits its drafts, so fold-not-filter stays honest.
- **Advances:** S4
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudCore/PlainWords.swift`, `Sources/GithudCore/PulsePresenter.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** `.ledger` gains `draftCount`. `lensLedger` grows a drafts clause —
  `"acme · 4, 5 drafts"`; zero-live prints the tail alone `"facebook · 1 draft"`, never
  `· 0, 1 drafts`; singular/plural on the draft noun. Spoken forms mirror.
- **Patterns to follow:** `Sources/GithudCore/PlainWords.swift:96` — the existing `fresh > 0`
  clause-suppression is the exact template.
- **Test scenarios:**
  - *Happy path:* both counts print in lane and spoken forms.
  - *Edge case:* zero live → tail-only form.
  - *Edge case:* zero drafts → today's string byte-identical.
  - *Edge case:* `1 draft` vs `5 drafts`.
  - *Integration:* `elsewhere` merges both sums.
- **Verification:** No ledger string can print `· 0`; existing ledger tests pass unchanged when drafts absent.

### U3. Core + App: draft-only owners enter the Owners card

- **Goal:** facebook is a real lens org — listed, foldable, draggable.
- **Advances:** S3
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudCore/LensChooser.swift`, `Sources/GithudApp/AppDelegate.swift`, `Sources/GithudApp/LensChooserView.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** `LensChooser.make(live:drafts:prefs:selfLogin:)`; `OwnerEntry` gains `draftCount`.
  Three call sites pass `sections.drafts` gated by `showDrafts` (`AppDelegate.swift:581`, `:638`,
  and the settings-door twin). The existing folded-remnant rule at `LensChooser.swift:43` already
  keeps a folded draft-only owner releasable when `showDrafts` goes off — verify, don't duplicate.
- **Patterns to follow:** `Sources/GithudCore/LensChooser.swift:33` — same discover-then-order shape.
- **Test scenarios:**
  - *Happy path:* facebook appears with `count: 0, draftCount: 1`.
  - *Edge case:* `showDrafts=false` → facebook absent unless folded.
  - *Edge case:* folded + drafts hidden → still listed, releasable.
  - *Integration:* card order matches lane order for a mixed live/draft-only set.
- **Verification:** Card and lane never disagree on which owners exist, or their order.

### U4. App: the island renders the tail

- **Goal:** The tail reads as subordinate to its group, and flat shape is untouched.
- **Advances:** S1, S5
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudApp/IslandContentView.swift`
- **Approach:** In the `.group` arm, after `groupRows`, render a tail: quiet count label
  (`"5 drafts"`, lowercase, no `(hide)`) then rows at reduced emphasis with the owner elided (the
  group title said it). **Flat shape keeps the terminal `Draft PRs` region unchanged** — same
  revealed header, same `(hide)`, same no-caption asymmetry. Retire only the grouped-shape use.
- **Patterns to follow:** `Sources/GithudApp/IslandContentView.swift:745` `ownerSubHeader` for the
  label; `:255-262` for the existing region, which becomes the flat-shape branch.
- **Test expectation:** none — view assembly. Behavior is pinned by U1's entries and U5's walk;
  visual proof comes from dogfood.
- **Verification:** Grouped shape shows tails and no terminal region; flat shape shows the terminal
  region and no tails; `showDrafts=false` shows neither.

### U5. Core: the key walk includes tails

- **Goal:** Keyboard navigation agrees with what the lane renders.
- **Advances:** S1
- **Dependencies:** U1, U4
- **Files:**
  - Modify: `Sources/GithudCore/KeySession.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** `actionableIDs` walks `group.rows` then `group.tail`; folded owners contribute
  nothing (their tail is off-screen with them); flat shape keeps today's terminal
  `sections.drafts` append.
- **Patterns to follow:** `Sources/GithudCore/KeySession.swift:44-53` — the existing
  ledger-contributes-nothing rule is the precedent.
- **Test scenarios:**
  - *Happy path:* walk order matches render order in grouped shape.
  - *Edge case:* folded owner's drafts unreachable.
  - *Edge case:* `showDrafts=false` → no draft ids.
  - *Integration:* the walk never lands on a row the lane doesn't render (WP-6k selection-clamp contract).
- **Verification:** Walk order equals render order in both shapes; no id maps to an invisible row.

### U6. Probe + dogfood evidence

- **Goal:** Make U1's invariants observable on live data without opening the island.
- **Advances:** verification of S1–S5
- **Dependencies:** U1–U5
- **Files:**
  - Modify: `Sources/GithudApp/ProbeCommand.swift`
- **Approach:** Extend the pulse block to emit the per-owner live/draft split and the resolved lane
  shape, in both the human line and `EVIDENCE_JSON`.
- **Patterns to follow:** `Sources/GithudApp/ProbeCommand.swift:116` for the human `split:` line;
  `:167` for the machine form.
- **Test expectation:** none — diagnostic surface.
- **Verification:** Probe's per-owner draft counts equal GraphQL truth for the live account
  (2026-07-26: acme 5, pro-vi 3, facebook 1).

## Scope Boundaries

- Stale stays flat and org-blind — that asymmetry is V3's question, deliberately not opened here.
- No scroll-to-reveal; the "toggle looks dead" defect is improved, not closed (see bug trace).
- Pill, radar, H1 "Needs you" untouched. Pill gauge stays over non-draft rows.
- No new polling — drafts already arrive every tick.

### Deferred to Follow-Up Work

- **Scroll-to-reveal on the `showDrafts` flip** — separate small WP; still open from the 2026-07-26 diagnosis.
- **V3 (stale per-org)** — its own design round; note all 5 current stale PRs are pro-vi's, so V3 gives acme no quiet caption at all.
- **Retiring the `showDrafts` pref** if the tail proves quiet enough on its own — revisit after dogfood.

## System-Wide Impact

- **Interaction graph:** `PulsePresenter.lensLayout` → `IslandContentView` (render),
  `KeySession` (walk), `LensChooser` (card), `AppDelegate` (3 card call sites). All four must agree
  on owner set and order — the "four surfaces can never disagree" rule at `PulsePresenter.swift:325`,
  now spanning two regions instead of one.
- **State lifecycle:** `lastOpened` clocks now key on owners that may have no live rows. A
  draft-only owner folded and later drained to zero rows still lists via the folded-remnant rule.
- **Unchanged invariants:** `sections(for:)` output; `changeKey`; the priority lattice; pill gauge
  composition; `PulseSections.drafts` sort (state-then-updated); the flat-shape terminal region's
  copy and its no-caption asymmetry.
- **Error propagation:** none new — pure presentation over already-fetched rows.

## Disconfirming Evidence

| Claim | What would falsify it | Gate |
|---|---|---|
| Tails never re-admit the inversion | a `.blocked` draft rendering above a `.ready` live row in the same group | U1 regression test, pinned |
| Fold-not-filter survives | a live or draft row appearing zero times, or twice | U1 exhaustive-partition test |
| Shape is draft-independent | flipping `showDrafts` changing grouped↔flat | U1 shape test |
| The walk never lands on air | a key id resolving to an unrendered row | U5 walk-equals-render test |
| Per-org counts match reality | probe split ≠ `gh` GraphQL truth | U6, live account |

## Bug-trace cross-check

| Motivating item | Contract clause | Cell behavior | Expected | Match |
|---|---|---|---|---|
| "enabled drafts, nothing happened" | U4 tail placement | acme's 5 drafts move from row ~13 to row ~5 | visible on flip | **partial** |
| folding an org leaves its drafts printing | U1 fold + U2 ledger | tail folds with the group; ledger reads `· 4, 5 drafts` | fixed | yes |
| facebook invisible to the lens | U1 + U3 | first-class group + card entry | fixed | yes |

**On the partial:** V1 moves drafts much closer to the top but does not guarantee they clear the
240px cap — with pro-vi leading (7 live + 3 drafts) and acme second, acme's tail still sits
below the fold. If "flip the toggle and see something" is a requirement rather than a
nice-to-have, the deferred scroll-to-reveal is what closes it, and it composes cleanly with this.

## Risks & Dependencies

| Risk | Mitigation |
|---|---|
| `byOwner[key]!` crashes on a draft-only key | U1 uses one merged partition; no force unwrap survives — pinned by the draft-only test |
| Enum widening misses a call site | Compiler enumerates them; the three known sites are listed in Integration-shape verification |
| Ledger prints `· 0` for a zero-live owner | U2 tail-only form + explicit edge test |
| Key walk lands on a folded owner's tail | U5 excludes folded owners; walk-equals-render integration test |
| Tail reads as a peer, not subordinate | Visual doctrine in U4 (indent, hairline, dimmed ink); dogfood judgment, one-line revert |
| `showDrafts` flip changes lane shape | Shape trigger counts live owners only; pinned by U1 shape test |
