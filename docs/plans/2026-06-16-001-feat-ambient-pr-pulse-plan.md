---
title: Ambient PR Pulse (H2 — second lane)
type: feat
status: active
date: 2026-06-16
origin: loop/INTENT.md (H2 ambient-skin) + session decision iter 25 ("ambient", "build it")
---

# Ambient PR Pulse — H2 second lane

The island answers a second question — **"how's my work doing?"** — alongside H1's
"does GitHub need me?". A glanceable, always-on read on the state of *your open PRs*
(CI · review · merge), so the island stays a living gauge even when the inbox is clear.
User decided (iter 25): time-to-awareness = **ambient** (no push); build H2 as a lane.

## Architecture Decision

**Approach:** A **second, independent data lane** sourced from a single GitHub
**GraphQL** query (`viewer.pullRequests(states: OPEN)`), modeled as a *composed*
`PullRequestPulse` (CI × review × merge) with a derived **priority-lattice** verdict
(`PulseState`). Rendered as a "Your PRs" section in the expanded island and as a
caught-up gauge in the collapsed pill. Read-only; Open-on-GitHub only.

**Rationale (priority criterion: Consistency, then Simplicity):**
- The pulse mirrors the proven H1 spine seam-for-seam — pure `*Pulse` model in
  GithudCore (like `NotificationThread`), a `PulsePresenter` (like `RadarPresenter`),
  a client method (like `fetchNotifications`), a pipeline/scheduler/controller pass.
  New *lane*, zero new *architecture*.
- One GraphQL query returns CI rollup + review decision + mergeability for all open
  PRs in ~1 rate point. REST would need N+1 calls; rejected for cost + complexity.

**Rejected alternative — merge H2 into H1's notification radar.** Notifications are
*event*-driven ("alice requested changes" arrives once); PR pulse is *state*-driven
("this PR has changes requested" is a standing fact after you've read the notice, and
"CI just went green" emits *no* notification at all). They are different lanes by
nature — folding them would lose exactly the standing-state awareness H2 exists for.

**Trade-offs we accept:**
- GraphQL has **no conditional 304** — every poll tick costs ~1 point (≈60/hr vs the
  5000/hr GraphQL bucket; the REST notifications 304-discipline is untouched, separate
  bucket). Worth it: the pulse changes *without* a notification, so it must be polled.
- PRs only (issues deferred); rollup only (no per-check drill-down).

### The honesty contract (this IS the moat — a wrong pulse erodes trust like a miss)
GraphQL fields are *partial*. The model must never invent a green state:
- `statusCheckRollup == null` → `CIState.none` ("no checks") — **never** `.passing`.
- `mergeable == UNKNOWN` → `MergeState.unknown` ("checking…") — **never** "ready".
- `reviewDecision == null` → `ReviewState.none` ("no review required") — not "approved".
- A PR is **`.ready`** only when CI ∈ {passing, none} **and** review ∈ {approved, none}
  **and** merge == mergeable (UNKNOWN is *not* ready). Drafts are never ready.
- The pulse is "as of last poll" — no faked realtime, reuse on-change redraw only.

### PulseState priority lattice (worst-first; documented, tested per cell)
```
blocked : CI==failing  OR merge==conflicting OR review==changesRequested   (red — your move)
draft   : isDraft       (and not blocked)                                   (gray — by design)
waiting : review==reviewRequired OR CI==pending OR merge==unknown (& not ↑) (yellow — in flight)
ready   : else  → CI∈{passing,none} ∧ review∈{approved,none} ∧ merge==mergeable (green — merge it)
```
Sort order (glanceability): blocked > ready > waiting > draft, then updatedAt desc.

## High-Level Technical Design

```
GraphQL: viewer.pullRequests(first:25, states:OPEN, orderBy:{UPDATED_AT,DESC}) {
  number title url isDraft updatedAt reviewDecision mergeable
  repository{nameWithOwner}
  commits(last:1){nodes{commit{statusCheckRollup{state}}}}
}
   │  POST https://api.github.com/graphql  (Bearer classic PAT; repo scope → private PRs)
   ▼
PullRequestPulse.list(fromGraphQLData:)  →  [PullRequestPulse]  (pure, fixture-tested)
   │   each: ci/review/merge members + derived PulseState (lattice above)
   ▼
PulsePresenter.rows(for:now:)  →  [PulseRow]  (repo, title, "CI · review · merge · age", state, symbol, url)
   │
   ▼  RadarPipeline.fetchPulse()  (blocking-semaphore, off-main, like blockingFetch)
   ▼  PollScheduler: every tick (even on a notifications-304) fetch pulse, diff key, onPulse
   ▼  HUDPanelController.setPulse → render: "Your PRs" section (expanded) + pill gauge (caught-up)
```
*Directional guidance for review, not implementation spec.*

## Implementation Units

### U1. Pulse domain model + state lattice + GraphQL decode  (GithudCore)
- **Goal:** `PullRequestPulse` (+ `CIState`/`ReviewState`/`MergeState` enums + derived
  `PulseState`) and a pure `list(fromGraphQLData:)` decoder + the query string constant.
- **Dependencies:** None
- **Files:** Create `Sources/GithudCore/PullRequestPulse.swift`; Test `Tests/GithudCoreTests/main.swift`
- **Approach:** Internal Decodable DTOs mapping the nested GraphQL JSON → public value
  type. Map raw enum strings with the honesty contract (null→`.none`/`.unknown`).
  `PulseState` is a computed property over the three members + `isDraft`. On a GraphQL
  `{"errors":[…]}` body with no `data`, throw `.decode(firstMessage)`.
- **Patterns to follow:** `NotificationThread.swift:74` (`list(from:)` static + nested
  Decodable structs + CodingKeys); `SignalClassifier.swift:62` (pure switch mapping).
- **Composition matrix (CI × review × merge → PulseState):**
  | Mixed case | Visible contract | Typed verdict | Test |
  |---|---|---|---|
  | passing · approved · mergeable | "ready to merge" green | `.ready` | `pulse_ready` |
  | failing · approved · mergeable | failing named, not "ready" | `.blocked` | `pulse_blocked_ci` |
  | passing · changesRequested · mergeable | changes named | `.blocked` | `pulse_blocked_review` |
  | passing · approved · conflicting | conflict named | `.blocked` | `pulse_blocked_merge` |
  | passing · reviewRequired · mergeable | waiting on review | `.waiting` | `pulse_waiting_review` |
  | pending · approved · mergeable | CI in flight | `.waiting` | `pulse_waiting_ci` |
  | passing · approved · **unknown** | not claimed ready | `.waiting` | `pulse_waiting_merge_unknown` |
  | **null-checks** · approved · mergeable | "no checks", not green-CI | `.ready`, CI=`.none` | `pulse_ci_none` |
  | passing · **null-review** · mergeable | "no review required" | `.ready`, review=`.none` | `pulse_review_none` |
  | draft, passing · approved · mergeable | never "ready" | `.draft` | `pulse_draft` |
  | draft + failing | blocked beats draft | `.blocked` | `pulse_draft_blocked` |
- **Test scenarios:** *Happy:* decode `pulls.json` → N pulses, fields populated. *Each
  lattice cell above.* *Edge:* empty `nodes` → `[]`; `commits.nodes` empty → CI `.none`.
  *Error:* `{"errors":[{"message":"Bad credentials"}]}` → throws `.decode`.
- **Verification:** Every lattice cell returns its documented `PulseState`; null/UNKNOWN
  never produce a green/ready verdict.

### U2. PulsePresenter + PulseRow  (GithudCore)
- **Goal:** `PulseRow` (pure display data) + `PulsePresenter.rows(for:now:)` →
  repo, title, subtitle `"CI passing · approved · mergeable · 2h"`, state, symbol, url.
- **Dependencies:** U1
- **Files:** Create `Sources/GithudCore/PulsePresenter.swift`; Test `Tests/GithudCoreTests/main.swift`
- **Approach:** Mirror `RadarPresenter`: member→label maps, `symbolName(for: PulseState)`,
  sort blocked>ready>waiting>draft then `updatedAt` desc. Reuse `RadarPresenter.age`.
- **Patterns to follow:** `RadarPresenter.swift:91` (`row(for:now:)` + `rows`).
- **Test scenarios:** *Happy:* a ready PR → subtitle contains "ready to merge"/"mergeable";
  symbol = checkmark. *Edge:* CI `.none` → subtitle says "no checks" not "passing".
  *Ordering:* blocked sorts above ready above waiting above draft.
- **Verification:** Rows are deterministic for a fixed `now`; labels honor the contract.

### U3. GraphQL fetch  (GitHubClient)
- **Goal:** `fetchOpenPullRequests(completion:)` — POST `/graphql`, decode via
  `PullRequestPulse.list(fromGraphQLData:)`, completion on the session bg queue.
- **Dependencies:** U1
- **Files:** Modify `Sources/GithudCore/GitHubClient.swift`
- **Approach:** Mirror `fetchAuthenticatedUserLogin`: Bearer + UA, but POST with
  `Content-Type: application/json` body `{"query": PullRequestPulse.openPRsQuery}`,
  `Accept: application/json` (GraphQL, not vnd.github+json). 401→`.http(401,…)` so the
  scheduler's existing auth-failure path fires. 200 → decode (which itself surfaces a
  GraphQL `errors[]` body as `.decode`).
- **Patterns to follow:** `GitHubClient.swift:176` (`fetchAuthenticatedUserLogin`).
- **Test scenarios:** Test expectation: decode is covered by U1; the network round-trip
  is proven live by U7's probe (no URLProtocol mock in this zero-dep harness).
- **Verification:** Live probe (U7) returns ≥0 PRs without error on the real PAT.

### U4. Pipeline + scheduler + controller wiring
- **Goal:** Fetch the pulse every poll tick (incl. on a notifications-304), diff, and
  push to the island as a second lane.
- **Dependencies:** U2, U3
- **Files:** Modify `Sources/GithudApp/RadarPipeline.swift`, `PollScheduler.swift`,
  `HUDPanelController.swift`, `AppDelegate.swift`
- **Approach:** `RadarPipeline.fetchPulse() -> Result<[PullRequestPulse], …>` via a
  blocking semaphore (same deadlock-safe note as `blockingFetch`). `PollScheduler.poll()`
  after handling notifications also fetches the pulse, computes a `lastPulseKey`
  (`"\(number)@\(repo):\(state)"` joined), and calls a new `onPulse([PulseRow])` only on
  change. `HUDPanelController.setPulse(_:)` stores `currentPulse` + re-renders.
  `AppDelegate` wires `onPulse → hud.setPulse`. A pulse fetch failure is **non-fatal**
  (log + keep last pulse); only a notifications 401 stops the loop (unchanged).
- **Patterns to follow:** `RadarPipeline.swift:120` (`blockingFetch`); `PollScheduler.swift:74`
  (the `lastKey` diff); `HUDPanelController.swift:77` (`setRadar`).
- **State-Action contract (pulse lane):**
  | Action × state | Caller obs. | Durable | Side effect | Race/dup | Test |
  |---|---|---|---|---|---|
  | fetch ok, key changed | onPulse(rows) | `currentPulse`,`lastPulseKey` set | island redraw | serial on poll queue — no race | manual/live |
  | fetch ok, key same | none | unchanged | none | — | manual/live |
  | fetch fails (transport) | none | `lastPulseKey` unchanged | log only | keeps last good pulse | manual/live |
  | notifications 401 | (existing) stop+auth msg | — | — | — | unchanged |
  - **Invariant:** `currentPulse` reflects the last *successful* pulse fetch; a failed
    fetch never clears it (no flicker-to-empty). Pulse failure never stops the poll loop.
- **Test scenarios:** *Edge:* pulse fetch error → island keeps prior pulse, loop continues.
  (Pure diff-key logic is exercised via U7 fixture; live behavior via probe.)
- **Verification:** Live app shows the "Your PRs" section; a 304 notifications tick still
  refreshes the pulse; a pulse error leaves the radar + last pulse intact.

### U5. "Your PRs" section + PulseRowView  (UI)
- **Goal:** Render the pulse lane in the expanded island: a section header + one row per
  PR (state-tinted leading glyph, title, `CI · review · merge · age` subtitle, clickable).
- **Dependencies:** U4
- **Files:** Modify `Sources/GithudApp/IslandContentView.swift`
- **Approach:** After the radar rows + before `InboxLinkView`, when pulse non-empty add a
  `"Your PRs"` caption header and `PulseRowView`s (mirror `RadarRowView`: hover fill,
  click→Open-on-GitHub, state color via a `PulseRowView.stateColor`). Cap at maxRows with
  "+N more". `IslandContentView.init` gains a `pulse: [PulseRow]` param (default `[]`).
- **Patterns to follow:** `IslandContentView.swift:222` (`RadarRowView`); section caption
  via `captionLabel`.
- **Test scenarios:** Test expectation: none (view) — covered by `--fixture-pulse` render
  + visual proof; layout reuses the proven row constraints.
- **Verification:** Fixture render shows a labeled "Your PRs" section; rows open the PR URL.

### U6. Collapsed-pill caught-up gauge
- **Goal:** When H1 is all-clear but open PRs exist, the pill shows the pulse rollup
  (worst-state glyph + count) instead of a bare check — the "living gauge" thesis.
- **Dependencies:** U4
- **Files:** Modify `Sources/GithudApp/CollapsedPillView.swift`; Test `Tests/GithudCoreTests/main.swift`
- **Approach:** Add a pure `PulsePresenter.rollup(_ rows:) -> (symbol,count,urgency)?`
  (worst-state summary) in GithudCore (testable). `CollapsedPillView` takes `pulse:` and,
  when `rows.isEmpty && !pulse.isEmpty`, renders the rollup glyph + count. Reversible: if
  noisy, revert to the check by ignoring `pulse`.
- **Patterns to follow:** `CollapsedPillView.swift:35` (the rows.first glyph branch).
- **Test scenarios:** *Happy:* rollup of [blocked,ready,ready] → blocked symbol, count 3.
  *Edge:* empty pulse → nil (pill shows the existing check).
- **Verification:** Caught-up pill reflects PR health; never claims a state it lacks.

### U7. Probe + fixture + tests (the live-verification gate)
- **Goal:** Prove the lane on real data (described→proven) and lock the model with fixtures.
- **Dependencies:** U1–U6
- **Files:** Modify `Sources/GithudApp/ProbeCommand.swift`, `RadarPipeline.swift`(reuse),
  `Sources/GithudApp/main.swift`, `AppDelegate.swift`, `FixtureLoader.swift`;
  Create `Tests/Fixtures/pulls.json`; Modify `Tests/GithudCoreTests/main.swift`
- **Approach:** Probe calls `pipeline.fetchPulse()` and prints a **redacted** state
  histogram (`blocked=N waiting=N ready=N draft=N`, no titles/repos) + folds it into
  `EVIDENCE_JSON`. `--fixture-pulse <path>` loads `pulls.json` and renders the island
  populated+expanded (visual proof, no PAT). `pulls.json` = a captured GraphQL response
  with one PR per lattice cell.
- **Patterns to follow:** `ProbeCommand.swift:62` (redacted evidence); `main.swift:19`
  (`--fixture`); `FixtureLoader.swift`.
- **Test scenarios:** *Happy:* fixture decodes to the labeled set; redacted evidence
  contains the pulse histogram and **no** PR titles. *Privacy:* assert evidence JSON has
  no `title`/`nameWithOwner` substrings.
- **Verification:** `githud probe` prints a pulse histogram on live data with the real
  PAT; `--fixture-pulse` renders the section; evidence stays redacted.

## Scope Boundaries
- **Read-only** — no merge/approve/comment actions from the HUD (H3 guardrail holds).
- **PRs only** — issues you authored are out of scope for the pulse v1.
- **Rollup only** — no per-check list / per-reviewer breakdown drill-down.
- **No "N people viewing"** — GitHub exposes no such signal; explicitly excluded (the trap).
- **No GraphQL ETag/304** — not supported by the endpoint; accept ~1pt/tick.

### Deferred to Follow-Up Work
- Decoupled pulse cadence (slower than the notifications poll) — separate iteration.
- Issues-you-authored lane; per-check drill-down — future, if it earns its place.

## System-Wide Impact
- **Interaction graph:** new callback `PollScheduler.onPulse` parallels `onRadar`;
  `HUDPanelController` gains `currentPulse` alongside `currentRows`; render() composes both.
- **Error propagation:** pulse fetch failure is **isolated** — logged, non-fatal, keeps the
  last good pulse; it never touches the radar lane or stops polling. Only notifications-401
  stops the loop (unchanged).
- **State lifecycle:** `currentPulse` only advances on a successful fetch (no flicker-empty).
- **API surface parity:** GraphQL is a *separate* rate bucket — REST 304-discipline (#8) is
  unchanged and unaffected.
- **Unchanged invariants:** H1 radar pipeline, classifier, SurfacePreferences, conditional
  polling, focus-non-theft, idle-footprint (the pulse adds one bg request per existing tick,
  no new timer) — all explicitly unchanged.

## Risks & Dependencies
| Risk | Mitigation |
|------|------------|
| GraphQL faked-liveness erodes trust | Honesty contract: null/UNKNOWN never render as green/ready; "as of last poll", no fake realtime (tested per lattice cell) |
| Classic PAT can't reach `/graphql` for private PRs | User already added `repo` scope; U7 live probe is the gate — verify before claiming proven |
| `mergeable==UNKNOWN` right after a push | Mapped to `.waiting` ("checking…"), never "ready" |
| Extra request every tick | Separate 5000/hr GraphQL bucket; ~60/hr; REST 304-discipline untouched |
| Pulse fetch error flickers the lane empty | `currentPulse` advances only on success; failure keeps last good + logs |
