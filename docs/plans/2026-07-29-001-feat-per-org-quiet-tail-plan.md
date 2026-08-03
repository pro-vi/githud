---
title: Per-org quiet tail — the owner lens takes the last org-blind region
objective: Folding an owner in the lens finally hides everything it owns. Its gone-quiet rows stop rendering in an org-blind region below and become a second tail under the org they belong to, with the fold's ledger line admitting all three counts.
type: feat
status: completed
date: 2026-07-29
origin: docs/design/2026-07-29-per-org-quiet-program.html
predecessor: docs/plans/2026-07-26-001-feat-per-org-draft-tails-plan.md
---

## Background (read cold)

The "Your PRs" lane splits into three regions — `active`, `stale`, `drafts` — computed by
`PulsePresenter.sections(for:)`. The owner lens (WP 2026-07-14-001) governed only `active`;
WP 2026-07-26-001 widened it to `active` + `drafts`, giving every owner group a draft tail. One
region is still org-blind: **stale** ("gone quiet"), which renders as a flat lane-level family
below everything.

2026-07-28 dogfood, on the reporting lane: folding "yours" hid its live rows and counted them on a
ledger line, but its gone-quiet rows kept rendering below, unaffected by the fold. Every stale PR on
that lane belonged to the folded owner — so folding emptied the live glance and left the quiet
section as the only populated thing on screen.

**Vocabulary settled with the user (2026-07-28):** the verb is **tail** (not nest); the copy is
**"gone quiet"** (not "stale"); tail order within a group is **rows → drafts → quiet**.

## Architecture Decision

**Approach:** `LensEntry.group` gains a third payload (`quiet`), and `lensLayout` starts returning a
`LensLayout` value instead of a bare `[LensEntry]`.

**The load-bearing correction.** The predecessor plan said V3 would simply add `showStale:` beside
`showDrafts:` on `lensRegions`. That is wrong, and the reason is doctrine:

- **`showDrafts` gates the lens's INPUT.** Drafts have no collapsed caption — the ratified asymmetry
  is that hidden drafts stay *fully* invisible. "Hidden" and "absent" mean the same thing, so passing
  `[]` is exactly right; it also stops a folded ledger from claiming drafts the pref hides lane-wide.
- **`showStale` gates the group's RENDERING.** Quiet's whole grammar is that it *leaves a count
  behind* — "2 gone quiet (show)" is both the honesty and the affordance. Gate its input and a
  stale-only owner disappears along with its count, which breaks fold-not-filter.

Therefore `lensRegions(showDrafts:)` keeps its **current signature**; `stale` is passed separately
and is never gated. The view chooses caption-versus-rows.

**Rejected alternative:** a general `[Region: [PulseRow]]` map on the group — attractive because a
fourth region would be free. It loses because the three regions are *not* interchangeable at the
view: drafts carry a count label and no control, quiet carries a collapsed caption that *is* its
affordance, live rows carry neither. A uniform map still needs a hand-written branch per region for
its chrome, so it buys no consumer collapse — and it invites summing regions uniformly, which is
exactly the mistake the live-only `fresh` rule was written to avoid.

## Invariants

- **Fold, not filter (three regions).** Every input row — live, draft, or quiet — appears exactly
  once: a visible row, a tail row, a flat terminal row, or inside a ledger count. In both shapes,
  under every pref combination.
- **The tails are positional.** Within a group, `drafts` then `quiet` render after `rows` and never
  join their state sort. The 2026-06-18 inversion guard, restated for two tails.
- **Walk order == render order.** Extended to the quiet tail and to the flat terminal reorder.
- **Ledger honesty.** A folded owner's line counts live, drafts and quiet — clause suppressed at
  zero, never `· 0`.
- **Four surfaces, one truth.** Lane groups, ledger lines, the Owners card and the lane eye agree on
  the owner set and its order — now over three regions.

## Program obligations

| ID | Obligation | Discharged at |
|---|---|---|
| **O1** | The per-owner partition takes three regions, and `OwnerBucket` is the one place their per-owner split is expressed | `PulsePresenter.OwnerBucket` / `ownerBuckets` (U1) |
| **O2** | `lensLayout` returns the whole layout — entries plus *both* terminal sets plus the shape — so no consumer can compute one and forget the other. The free functions that exist to rebuild that answer go private | `PulsePresenter.LensLayout` (U1) |
| **O3** | Row de-emphasis is derived from the row, never passed: one predicate meaning "not in the live glance", covering both tails and both shapes | `PulseRowView.init` (U3) |

## Declarations

### `Sources/GithudCore/PulsePresenter.swift` (U1)

```swift
// UNCHANGED signature — deliberately. `showStale` is NOT a parameter here:
// quiet must reach the lens even when hidden, or its count dies with it.
func lensRegions(showDrafts: Bool) -> (live: [PulseRow], drafts: [PulseRow])
// hides: that `stale` is passed separately by the caller.

~ public struct OwnerBucket                      // discharges O1
    let key: String                              // lowercased identity
    let owner: String                            // first-seen display casing
    var live: [PulseRow]
    var drafts: [PulseRow]
+   var quiet: [PulseRow]
// post: all three arrays preserve input order — this type partitions, never sorts.
// hides: which region a row came from beyond these three names; no Region enum leaks.

~ static func ownerBuckets(live:, drafts:, quiet:) -> [OwnerBucket]
// pre:  caller has already applied `showDrafts` to `drafts` (see lensRegions).
// post: discovery order = live owners by lead-row rank, then draft-only, then quiet-only.
//       Every returned bucket has >=1 row in some region.
// errors: none — a malformed repo string degrades to a whole-string owner, never throws.

+ public struct LensLayout                       // discharges O2
+   let entries: [LensEntry]
+   let terminalDrafts: [PulseRow]               // flat shape only; [] when grouped
+   let terminalQuiet: [PulseRow]                // flat shape only; [] when grouped
+   var isGrouped: Bool                          // from the shape decision, not re-inferred
// post: terminalDrafts and terminalQuiet are BOTH [] iff isGrouped — a row can never have
//       two homes, and neither set can be forgotten independently.

~ static func lensLayout(live:, drafts:, quiet:, prefs:, selfLogin:, lastOpened:) -> LensLayout
// pre:  `drafts` already gated on showDrafts; `quiet` is NEVER gated.
// post: every input row is reachable exactly once across entries + both terminal sets +
//       ledger counts. Tails follow rows positionally, never sorted in.
// errors: none — total function over any row set, including all-empty.

- public static func isGrouped(_ entries: [LensEntry]) -> Bool
- public static func terminalDrafts(after:drafts:prefs:) -> [PulseRow]
// Both existed to REBUILD an answer lensLayout already had. With two terminal regions they
// double the forget-hazard at the exact seam that has bitten this WP twice.

~ static func leadingRows(_ rows:, prefs:) -> [PulseRow]     // now internal, not public

~ public enum LensEntry
    case rows([PulseRow])
~   case group(owner: String, title: String, rows: [PulseRow],
~              drafts: [PulseRow], quiet: [PulseRow])
~   case ledger(owner: String?, title: String,
~              count: Int, draftCount: Int, quietCount: Int, fresh: Int)
// post(group): drafts and quiet render AFTER rows, in that order (descending relevance,
//              ratified). Payload order mirrors render order.
// post(ledger): counts sum exactly the rows the fold hides in all three regions.
//               `fresh` stays LIVE-only — a draft or a rotting PR is not arrival.
// hides: the chrome each tail wears — the view's business, and it differs per region.
```

### `Sources/GithudCore/PlainWords.swift` (U2)

```swift
~ static func lensLedger(_ title:, count:, draftCount:, quietCount:, fresh:) -> String
//   "acme · 4, 5 drafts, 2 gone quiet, 1 new"
//   "facebook · 1 draft"           (zero live → the noun carries the line)
//   "helios-oss · 3 gone quiet"    (zero live, zero drafts → same rule)
// post: clause order is live · drafts · quiet · new; each suppressed at zero. Never "· 0".
//       Pre-V3 call sites stay byte-identical.
~ static func lensLedgerSpoken(...) -> String    // mirrors, via spokenLedger
~ static func lensCardRowSpoken(...) -> String   // card row; no "open" verb

+ static func quietTailLabel(_ count: Int) -> String    // "2 gone quiet"
// The REVEALED tail's label — sibling of draftTailLabel, no verb token.
// NOTE: the COLLAPSED form reuses staleCaption(_:) unchanged — "2 gone quiet (show)".
```

### `Sources/GithudCore/LensChooser.swift` (U2)

```swift
~ public struct OwnerEntry
    let owner, title: String
    let leads: Bool
    let count: Int            // live
    let draftCount: Int
+   let quietCount: Int
~ static func make(live:, drafts:, quiet:, prefs:, selfLogin:) -> LensChooser
// pre:  same gating as the lane — drafts pre-gated, quiet never.
// post: owner SET and ORDER equal the lane's, now across three regions; a folded owner with
//       no rows anywhere still lists (the remnant rule) so it stays releasable.
```

### `Sources/GithudApp/IslandContentView.swift` (U3)

```swift
+ private func quietTailLabel(count: Int) -> NSView       // sibling of draftTailLabel
~ private func lensLedgerLine(owner:, title:, count:, draftCount:, quietCount:, fresh:)
~ PulseRowView.init(row:, theme:, peeked:, elideOwner:, emphasizeOwner:, onPeekToggle:)
// discharges O3 — de-emphasis stays DERIVED, rule widens:
//     let subdued = row.isDraft || row.isStale     // "not in the live glance"
// post: ink and weight only. Focus bar, hover band, click target and spoken form untouched
//       (an alphaValue on the row would composite the ⌃⌥G cursor).
// VISIBLE CHANGE: flat-shape quiet rows dim too. Deliberate — one rule, both shapes.
```

### Composition root (U3)

No DI container; the graph is assembled per render pass, the same expression at every site:

```swift
let sections = PulsePresenter.sections(for: model.pulseRows)
let regions  = sections.lensRegions(showDrafts: model.pulsePreferences.showDrafts)
let layout   = PulsePresenter.lensLayout(live: regions.live,
                                         drafts: regions.drafts,
                                         quiet: sections.stale,       // never gated
                                         prefs: model.lensPreferences,
                                         selfLogin: model.selfLogin,
                                         lastOpened: model.lensLastOpened)
```

Bindings: prefs ← `LensStore` (UserDefaults) · rows ← the poll spine's last-good snapshot ·
`showStale` ← `PulseStore`, read by the **view**, not by the lens.

## Call stacks

### Island render — grouped shape

```
IslandContentView.init
  PulsePresenter.sections(for: pulse)
  sections.lensRegions(showDrafts:)                    → (live, drafts)
~ PulsePresenter.lensLayout(…, quiet: sections.stale)  → LensLayout
    for entry in layout.entries
      case .group(owner, title, rows, drafts, quiet)
        ownerSubHeader(title)
        rows.map(pulseRowView)                         // full emphasis
        if !drafts.isEmpty
          draftTailLabel(drafts.count); drafts.map(pulseRowView)   // dimmed, derived
+       if !quiet.isEmpty
+         if showStale → quietTailLabel(quiet.count); quiet.map(pulseRowView)
+         else         → captionButton(staleCaption(quiet.count), onClick: onToggleStale)
            // ONE lane-wide pref: any group's (show) reveals every group's quiet.
~     case .ledger(owner, title, count, draftCount, quietCount, fresh)
- if showStale { stale region }              // lane-level, retired in grouped shape
- if showDrafts { terminal drafts region }   // ditto
+ if !layout.terminalDrafts.isEmpty → revealedHeader(draftsHeader) + rows
+ if !layout.terminalQuiet.isEmpty  → showStale ? revealedHeader(staleHeader) + rows
+                                              : captionButton(staleCaption(…))
  // ORDER FLIPPED in flat shape: drafts now precede quiet, matching the ratified group order.
```

### Keyboard walk — must equal the render, id for id

```
KeySession.actionableIDs(radar:, pulse:, showDrafts:, showStale:, …)
  sections = PulsePresenter.sections(for: pulse)
  regions  = sections.lensRegions(showDrafts:)
~ layout   = PulsePresenter.lensLayout(…, quiet: sections.stale, …)
    for entry in layout.entries
      case .rows(rows)                  → ids += rows
~     case .group(_, _, rows, drafts, quiet)
~       ids += rows + drafts + (showStale ? quiet : [])
        // A COLLAPSED quiet tail contributes NOTHING: its caption is structure, not a row.
      case .ledger                      → break
~   ids += layout.terminalDrafts
+   ids += showStale ? layout.terminalQuiet : []
```

## File-tree diff

```
Sources/GithudCore/
~ PulsePresenter.swift    MODIFIED  three-region partition, LensLayout,           U1
                                    LensEntry payloads, retire 2 publics
~ PlainWords.swift        MODIFIED  quiet clause + quietTailLabel                 U2
~ LensChooser.swift       MODIFIED  quietCount on OwnerEntry, make(quiet:)        U2
~ KeySession.swift        MODIFIED  walk the quiet tail, flat reorder             U4
  LensPreferences.swift   (context — read, not modified) fold predicate home

Sources/GithudApp/
~ IslandContentView.swift MODIFIED  quiet tail render, subdued rule,              U3
                                    flat terminal reorder, ledger line
~ AppDelegate.swift       MODIFIED  makeLensChooser passes quiet                  U3
~ HUDPanelController.swift MODIFIED render-pass chooser passes quiet              U3
~ LensChooserView.swift   MODIFIED  card row shows the quiet clause               U3
~ ProbeCommand.swift      MODIFIED  three-way split in line + JSON                U5
  PulseStore.swift        (context) showStale lives here, read by the view

Tests/GithudCoreTests/
~ main.swift              MODIFIED  three-region fold-not-filter, tail order,  U1 U2 U4
                                    ledger clauses, walk equality
```

## Seams & enabling points

This repo's test runner links `GithudCore` **only** — the App target has no test seam by
construction. Every rule worth pinning lives in Core; view units say "live rehearsal" rather than
inventing a double that cannot exist.

| Seam | Enabling point | Double | Proves |
|---|---|---|---|
| `lensLayout` | pure function — all state is arguments | fixture `[PulseRow]` + `LensPreferences` | every `post:` on `LensLayout` / `LensEntry`; fold-not-filter; positional tails |
| `now` (age → isStale) | injected `now:` on `sections(for:now:)` | frozen `Date` | quiet membership is deterministic; a 14-day boundary row is testable |
| `PlainWords` | pure string functions | none needed | clause order, zero-suppression, never-`· 0`, spoken parity |
| `LensChooser.make` | pure — rows + prefs in, descriptor out | fixture rows | card owner set/order == lane's, across three regions |
| `actionableIDs` | `lens:` / `showStale:` parameters | fixture rows + prefs | walk == render; no id twice; collapsed quiet unreachable |
| island render | none — `--fixture-pulse` at the process boundary | **none — live rehearsal** | chrome per tail, the dim treatment, the caption's click |
| probe split | `githud probe` CLI | **none — live rehearsal** (needs a classic PAT) | per-owner three-way counts equal `gh` truth |

## Implementation Units

Build order: **U1 → U2 → U4 → U3 → U5.** Contract first, then the copy it needs, then the surface
whose correctness is *provable* (the walk), then the surface that can only be rehearsed (the view)
against an order already pinned, then the evidence instrument. Not stack order — the view lands
fourth deliberately so it matches a fixed contract rather than defining one.

### U1. Core: the lens takes three regions

- **Establishes:** A group carries live rows, its drafts and its quiet; a folded owner's ledger
  counts all three; `lensLayout` hands back one value that cannot be half-consumed.
  Discharges **O1**, **O2**.
- **Dependencies:** None
- **Files:**
  - Modify: `Sources/GithudCore/PulsePresenter.swift`
  - Modify (mechanical, to compile): `Sources/GithudCore/KeySession.swift`,
    `Sources/GithudCore/LensChooser.swift`, `Sources/GithudApp/IslandContentView.swift`,
    `Sources/GithudApp/ProbeCommand.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** `OwnerBucket` gains `quiet`; `ownerBuckets` takes a third array and appends
  quiet-only owners after draft-only ones. The shape guard stays `leading.count >= 2` — every bucket
  has content by construction, so quiet-only owners count too. `isGrouped` and `terminalDrafts` stop
  being public functions and become `LensLayout` fields.
- **Patterns to follow:** `PulsePresenter.swift:373` `ownerBuckets` — same discovery skeleton;
  `:464` `ledgerEntry` — same per-region accumulate.
- **Test scenarios:**
  - *Happy:* three owners × three regions → each group's tails hold only its own rows, in order
    rows → drafts → quiet.
  - *Inversion guard ×2:* a group with a blocked draft AND a conflicted 16-week row → both render
    after the ready live row, drafts before quiet.
  - *Edge:* quiet-only owner → group with empty rows and empty drafts, sunk below draft-only owners.
  - *Edge:* `quiet: []` → entries byte-identical to the V2 layout.
  - *Edge:* `isGrouped` true ⟹ both terminal sets empty (the post-condition, asserted directly).
  - *Integration:* fold-not-filter over three regions × both shapes × folded/unfolded — visible ids
    unique, visible set == un-folded rows, ledger counts == exactly what folds hide.
- **Verification:** All five invariants hold; no public API exists to rebuild the shape decision.
- **Runtime evidence:** Pure Core — the suite *is* the runtime evidence; no integration claim to
  execute.
- **Rollback:** Revert the commit — no persisted shape changed, no stored pref added.

### U2. Core: the ledger and the card admit the quiet

- **Establishes:** A folded owner's line says all three counts, and the Owners card row reads
  identically to the ledger line it produces.
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudCore/PlainWords.swift`, `Sources/GithudCore/LensChooser.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** Clause order live · drafts · quiet · new, each suppressed at zero, via the existing
  `draftsNoun`-style single home. Zero-live keeps its rule and extends: `"helios-oss · 3 gone quiet"`
  when live and drafts are both zero. `quietTailLabel` joins as the revealed label; the collapsed
  form reuses `staleCaption` untouched.
- **Patterns to follow:** `PlainWords.swift` — the existing `fresh > 0` clause suppression and
  `draftsNoun(_:)` plural home.
- **Test scenarios:**
  - *Happy:* all four clauses print in order; spoken form mirrors.
  - *Edge:* zero live + drafts + quiet > 0 → the quiet noun carries the line; never `· 0`.
  - *Edge:* singular/plural on both nouns; `quietCount: 0` → V2 strings byte-identical.
  - *Integration:* the `elsewhere` valve sums all three across every folded owner.
- **Verification:** No ledger or card string can print a zero count; every pre-V3 string unchanged.

### U4. Core: the walk follows the quiet tail

- **Establishes:** Keyboard order equals render order over three regions, and a collapsed quiet tail
  is unreachable.
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudCore/KeySession.swift`
  - Test: `Tests/GithudCoreTests/main.swift`
- **Approach:** Per group: rows + drafts + quiet-when-shown. Flat: terminal drafts then terminal
  quiet, both from `LensLayout`. Deliberately placed before the view unit — it is the surface whose
  agreement is *provable*, so it defines the order the view must match.
- **Patterns to follow:** `KeySession.swift:48-62` — the existing ledger-contributes-nothing rule.
- **Test scenarios:**
  - *Happy:* id sequence == the documented render order, both shapes.
  - *Edge:* `showStale` off → no quiet id reachable, in either shape.
  - *Edge:* folded owner → neither its drafts nor its quiet enter the walk.
  - *Invariant:* no id appears twice, under every pref × shape combination.
- **Verification:** Selection can never land on a row the lane does not draw.

### U3. App: the island renders the quiet tail

- **Establishes:** Each group ends with its drafts then its quiet; quiet collapses to its ratified
  caption and expands to a label plus dimmed rows; the flat shape reorders to match.
  Discharges **O3**.
- **Dependencies:** U1, U2, U4
- **Files:**
  - Modify: `Sources/GithudApp/IslandContentView.swift`, `Sources/GithudApp/LensChooserView.swift`,
    `Sources/GithudApp/AppDelegate.swift`, `Sources/GithudApp/HUDPanelController.swift`
- **Approach:** Mirror `draftTailLabel`'s indent and ink for the revealed label; reuse
  `captionButton` for the collapsed form so the click keeps flipping the one pref. Widen the derived
  predicate to `isDraft || isStale`. The lane eye's owner set already derives from the shared
  partition, so it picks up quiet-only owners with no edit.
- **Test expectation:** none in Core — App has no test target. Proven by live rehearsal.
- **Runtime evidence:** `unverified until built` — settled by `--fixture-pulse` with a three-region
  fixture, captured per-window by id, under `showStale` both ways and a fold applied.

### U5. Probe: the three-way split

- **Establishes:** The per-owner live/draft/quiet split is observable on live data without opening
  the panel, and diffable against `gh`.
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudApp/ProbeCommand.swift`
- **Approach:** Extend the existing `ownerBuckets` call to three regions; the human line stays
  shape-only by default (owner logins remain behind `--show-items`, per the redaction contract), JSON
  gains a third field on the anonymous-by-index split.
- **Test expectation:** none — diagnostic surface.
- **Runtime evidence:** `unverified — needs GITHUD_PAT`; the V2 probe's kill condition is still
  unrun for the same reason.

## Scope Boundaries

- **No per-owner reveal state.** One lane-wide `showStale`; any group's caption flips it for all. A
  second persisted set is not in scope.
- **No change to the stale rule.** `staleAfter` stays 14 days; the threshold stays in the gear
  tooltip.
- **The pill, the radar, the H1 queue, polling, persistence** are untouched.

### Deferred to Follow-Up Work

- **Scroll-to-reveal on a pref flip** — still open from 2026-07-26, and a third tail makes the 240pt
  pane cap bite harder, not less.
- **Whether tail rows keep GitHub's CI badge or take the ratified mock's neutral WIP glyph** —
  unanswered from V2, and now it would apply to two tails.

## Disconfirming Evidence

| Claim | What would falsify it | Gate |
|---|---|---|
| Tails never re-admit the inversion | a blocked draft or conflicted stale row rendering above a ready live row | U1 regression test, two tails |
| Fold-not-filter over three regions | any row appearing zero times or twice | U1 identity-multiset assertion |
| A row can never have two homes | `isGrouped` true with a non-empty terminal set | U1 post-condition test |
| Walk == render | an id resolving to an unrendered row, or a collapsed quiet row reachable | U4 |
| Pre-V3 output unchanged | `quiet: []` producing different entries or strings | U1 + U2 byte-identity tests |
| The fold now means what it says | a folded owner's quiet row still on screen | live rehearsal, the reported case |

## Risks & Dependencies

| Risk | Mitigation |
|---|---|
| Four-clause ledger stops scanning | Flagged Open in the brief; clause order fixed, each suppresses at zero, so the common line stays two clauses. Copy-only revert. |
| Quiet-only orgs clutter the Owners card | Consistent with the draft-only precedent and foldable on arrival; watch in dogfood. Reversible by requiring live-or-draft content for discovery. |
| Dimming quiet rows reads as broken | One-line predicate; revert to `isDraft` alone without touching structure. |
| Flat-shape reorder surprises | Deliberate and stated; it buys one mental model across shapes. |
| Three tails × 240pt pane cap | Does not regress — collapsed quiet is one line per org. Strengthens the case for the deferred scroll-to-reveal. |
| App layer stays untestable | Structural, pre-existing, named in Seams. Every rule that *can* live in Core does. |

## Build record (2026-07-29)

All five units landed on `feat/per-org-quiet-tail`, stacked on
`feat/per-org-draft-tails`. 1700 checks (1550 → 1700), clean build, nothing pushed.

| Unit | Commit | Note |
|---|---|---|
| U1 | `f6498b0` | Two mutation probes run and caught: dropping the quiet payload → 13 failures; dropping `terminalQuiet`'s fold filter → 4 failures. Both reverted by exact string, never by `git checkout`. |
| U2 | `e5566b5` | `quietNoun` and `tailNouns` became the single homes; every pre-V3 string byte-identical. |
| U4 | `c023fd7` | Two intended behaviour changes: the flat-shape reorder, and quiet ids becoming fold-filtered (the reported defect's keyboard half). |
| U3 | `933c3a2` | **Defect found in rehearsal:** the per-group collapsed caption rendered at the lane margin, reading as a lane-level section between two groups. Fixed via `CaptionButtonView(indent:)` + the shared `IslandContentView.tailIndent`. |
| U5 | `eaff810` | **Correctness fix:** the probe's `lens_shape` still passed `quiet: []`, so it would report "flat" on a desk the island draws grouped. |

**Runtime evidence (U3), captured under `--fixture-pulse Tests/Fixtures/pulls-three-region.json`:**

- Grouped + `showStale` off → each owner's quiet collapses to `"1 gone quiet (show)"`, indented
  under its title, flush with the `"1 draft"` tail label.
- Grouped + `showStale` on → `rows → 1 draft → 1 gone quiet`, tail rows dimmed.
- Two owners folded → `helios-oss` (quiet-only) gets a real title and tail; the folded lines read
  `acme · 1, 1 gone quiet` and `pro-vi · 1, 1 draft`, and **the folded owner's quiet row is
  nowhere on screen** — the reported defect, fixed.
- **O3 measured, not eyeballed** (one frame, luminance): live title `0.9373`, quiet title `0.4863`,
  draft title `0.4863`, group title `0.3964`; state badge `1.000 → 0.8314`. Both tails demote
  identically, so a conflicted 16-week PR no longer shouts like the live blocked row above it.

**Unrun:** U5's kill condition (probe counts vs `gh` truth) — the probe blocks resolving a classic
PAT. V2's probe kill condition is unrun for the same reason.

**Gate:** `/invariance` 0 findings (all five invariants attacked; disjointness of the three regions
holds because `isStale` requires `!isDraft`). `/perf` 1 finding, Acceptable-with-note and
pre-existing: `freshCount`'s ISO re-parse is 97% of the lens's cost (286µs vs 8.9µs with an empty
clock at n=25; 2073 vs 148 at n=500), untouched by V3, which itself adds ~4µs per render.

## Open questions (deliberately unresolved at plan time)

- Whether an org whose *only* rows are 16 weeks old deserves a title and a fold — this design says
  yes, for consistency with the draft-only precedent, and names it as the thing to watch.
- Whether a four-clause ledger line still scans.
