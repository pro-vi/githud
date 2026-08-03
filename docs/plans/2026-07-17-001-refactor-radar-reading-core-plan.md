---
title: WP-A — the radar reading moves into Core (ThreadCache, holistically)
objective: The lane the user trusts most stops being the only lane the test suite cannot see — cache policy, enrichment lifetimes, and re-verify throttles become tested transitions
type: refactor
status: completed
date: 2026-07-17
origin: dogfood 2026-07-16/17 (304 staleness, key-session gate — every real bug on the owner-lens branch lived in App-side seams outside the Core-only runner) + user: "redesign holistically if needed"
---

## Background (read cold)

githud's radar ("Needs you") is fed by `RadarPipeline` (App target): conditional `GET /notifications` via `PollValidators`, two budget-bounded enrichment passes (subject state, comment author), a 304-path re-verify throttle, two one-shot re-projection latches, and the inbound sweep's adopt baseline. The repo's test runner (`Tests/GithudCoreTests`, executable, 1280 checks) can only import Core — so **all of that policy ships untested**, and the branch's real bugs (terminal-vs-perishable verdict caching, the 304 staleness hole, latch ordering) lived exactly there, caught by dogfood and review bots instead of the suite.

Reconnaissance (2 Explore agents, 2026-07-17) established: `GitHubClient` already lives in Core with an injectable `URLSession`; the runner already has a `StubURLProtocol` + `stubClient()` harness driving all five endpoints with canned HTTP (main.swift:1868–1993) including blocking wrappers; `RadarPipeline.Result` is Foundation-only; the scheduler couples through exactly the `RadarSource` seams (`refresh/fetchPulse/fetchInbound/recomputeRadar/consumeSelfResolution/consumeSubjectResolution` + `currentSelfLogin`/`preferences`). Nothing technical pins the pipeline to App.

## Architecture Decision

**Approach:** Relocate the whole pipeline to Core **and** split it internally: a pure value type `RadarReading` (Sources/GithudCore) owns every piece of reading state and its transitions with an injected clock — `RadarPipeline` (also Core after the move) shrinks to the six blocking I/O wrappers plus orchestration that calls the pure transitions. `RadarSource` and `Result` move intact. Tests land at BOTH grains: unit tests on `RadarReading` transitions (the PollReducer idiom — `(state, input, now) → state`), and end-to-end pipeline tests over the existing stub-HTTP harness (200/304 sequences exercising the real loop scaffolding).

**Rationale:** Consistency — `PollReducer` is this repo's proven shape for exactly this kind of state (pure, injected `now`, effects asserted structurally); `RadarReading` is its sibling for the reading side. Testability decided the "relocate AND split" over either half alone: the value type makes policy cheap to pin, but three of the shipped bugs lived in *loop scaffolding* (pass ordering, deadline interaction, latch consumption order) that only end-to-end stub-HTTP tests can see — and that harness already exists. Rejected alternative: **pure-value-type-only with the pipeline staying in App** (the original "ThreadCache" sketch) — it would leave the enrichment loop, the 12s budget interplay, and the latch choreography untested, which is where the bugs actually were.

**Trade-offs:** Bigger diff than a pure extraction; `ProbeCommand` and `PollScheduler` keep working only if `Result`'s field set survives intact (pinned by a probe-identical gate below). The move is a two-way door (module location can be reverted); the `RadarReading` API is the one surface worth designing carefully.

**Representation ledger:** No new persisted vocabulary. `PollValidators` stay per-process (never persisted — unchanged). `Snapshot` untouched. The reading state is memory-only; its authority is the value type; the pipeline holds exactly one instance.

## High-Level Technical Design

```
GithudCore/
  RadarReading.swift        // NEW — pure value type
    state: threads, validators, preferences, selfLogin+selfResolved+selfJustResolved,
           subjectJustResolved, lastSubjectVerify, lastRepoScope, lastInboundBaseline
    transitions (all pure, injected now):
      adoptFetch(response, now)          -> (Self, EnrichmentTargets)   // validators, 304 vs 200
      cacheSubjectVerdict(index, state)  -> Self      // TERMINAL-ONLY: merged/closed cache, "open" discarded
      cacheCommentAuthor(index, login, excerpt) -> Self
      resolvedSelf(login?)               -> Self      // only a NON-NIL login marks resolved (F9)
      consumeSelfResolution()            -> (Self, Bool)   // declines on empty thread cache
      consumeSubjectResolution()         -> (Self, Bool)
      reverifyDue(now)                   -> Bool      // 600s throttle; stamping on ATTEMPT is adoptReverifyStamp(now)
      reverifyTargets()                  -> [Int]     // unread ∧ (nil|"open") ∧ PR/Issue ∧ url ∧ surfaces ∧ scope
      flipSubjectResolved(index, state)  -> Self      // sets the one-shot on terminal flips
      adoptInbound(reading)              -> Self      // InboundReading.adopt semantics
      radar()/suppressed()               -> [RankedThread]  // delegate to SignalClassifier
  RadarPipeline.swift       // MOVED from App — I/O shell: blocking wrappers + the deadline loops,
                            // every decision routed through RadarReading transitions
  (RadarSource protocol + Result struct move with it, field-for-field)
```

The 12s enrichment deadline and 6s per-fetch caps stay in the shell (they are wall-clock I/O), but *which indices to enrich, in which pass order, and what to store* are pure targets/transitions and therefore tested.

## Implementation Units

### U1. Relocate pipeline + protocol + Result to Core, byte-compatible

- **Goal:** `RadarPipeline`, `RadarSource`, `Result` live in `Sources/GithudCore/`; App target compiles with imports only.
- **Dependencies:** None
- **Files:** Move `Sources/GithudApp/RadarPipeline.swift` → `Sources/GithudCore/RadarPipeline.swift`; Modify `Sources/GithudApp/PollScheduler.swift`, `Sources/GithudApp/ProbeCommand.swift` (imports/visibility only — types gain `public` where the module boundary now requires it).
- **Approach:** Mechanical move first, zero logic changes; `public` annotations added minimally. The protocol doc comment claiming it "necessarily lives in the App target" is rewritten to record the move and why.
- **Patterns to follow:** `GitHubClient` (Core, `public final class`, injectable session) is the precedent for I/O-in-Core.
- **Test scenarios:** *Happy path:* suite still 1280 green; app builds. *Integration:* `githud probe` runs.
- **Verification:** **Probe-identical gate** — `githud probe` `EVIDENCE_JSON` (minus `rate_remaining`/counts that vary with live data: compare structure + same-tick fields on back-to-back runs) matches pre-move; all 1280 checks green with zero test edits.

### U2. Extract `RadarReading` — every transition pure, every invariant a test

- **Goal:** The ten reconnaissance invariants become named, clock-injected transitions with locking tests.
- **Dependencies:** U1
- **Files:** Create `Sources/GithudCore/RadarReading.swift`; Modify `Sources/GithudCore/RadarPipeline.swift` (delegate all state); Test `Tests/GithudCoreTests/main.swift`.
- **Approach:** State-Action Contract rows (each cell → one test):
  1. `cacheSubjectVerdict` stores **only** merged/closed; "open" leaves state nil (the #416 rule).
  2. `consumeSelfResolution`/`consumeSubjectResolution` clear their latch on every call and **decline when the thread cache is empty** (snapshot-paint protection).
  3. Latch consumption is per-tick unconditional — the pipeline API makes it impossible to short-circuit (single `consumeResolutions()` returning both, if that reads cleaner at the call site; scheduler updated accordingly).
  4. `resolvedSelf(nil)` never marks resolved (F9 — a failed `GET /user` retries).
  5. `reverifyDue` honors 600s; the stamp happens on **attempt**, not on flip.
  6. `reverifyTargets` = unread ∧ (nil|"open") ∧ PR/Issue ∧ has-url ∧ `surfaces()` ∧ repo-scope — each conjunct has a counterexample test.
  7. Enrichment **pass order** (subject-state before comment-author) is a returned-targets ordering fact, tested.
  8. `adoptFetch` on 304 keeps prior validators when the server omits them (`PollPlan.from` already covers; the reading's adoption is asserted).
  9. `adoptInbound` = `InboundReading.adopt` semantics (delegation asserted).
  10. `lastRepoScope` is set by `adoptFetch(200)` and read by `reverifyTargets` — co-located at last.
- **Patterns to follow:** `PollReducer` suites (main.swift:1281–1660): injected `now`, structural effect assertions.
- **Test scenarios:** the matrix above; *Error path:* malformed/empty thread sets never crash transitions.
- **Verification:** New `RadarReading` suites green; pipeline diff shows state fields deleted (single `var reading: RadarReading` remains); probe-identical gate again.

### U3. End-to-end pipeline tests over the stub-HTTP harness

- **Goal:** The loop scaffolding — the part unit tests can't see — under canned HTTP.
- **Dependencies:** U2
- **Files:** Test `Tests/GithudCoreTests/main.swift` (extend the `StubURLProtocol` section).
- **Approach:** Scripted sequences against a real `GitHubClient(stub session)` + real `RadarPipeline`:
  - 200 (open PR review_requested) → verdict fetched, **not cached** → second 200 re-fetches (stub call-count asserted).
  - 200 (open) → 304 ticks under 600s → no subject GETs; move clock past 600s (inject via reading's stamp — or drive with a stubbed `now` seam on the pipeline) → re-verify fetches, PR now closed → flip + `consumeSubjectResolution() == true` → `recomputeRadar()` drops the row to suppressed.
  - Auth-stop tick: 401 → failure propagates, reading untouched.
  - Deadline starvation: N slow subject fetches → comment pass still runs after the low-volume pass (ordering), un-enriched threads still surface (never-miss).
- **Test scenarios:** as above; *Edge:* 304 with empty prior cache → re-verify declines (nothing to verify), no fetches.
- **Verification:** The #416 bug class and the latch-choreography class are now failing-test-reproducible; suite total rises accordingly.

## Scope Boundaries

- No behavior change anywhere — probe-identical is the gate; any intentional divergence is a plan violation.
- `PollScheduler` stays App (AppKit/NWPathMonitor pins it) — only its imports/type references adjust.
- Pulse/inbound fetch methods move with the pipeline but their logic is untouched (WP-B builds on this).
- No persistence changes; no new prefs.

### Deferred to Follow-Up Work

- WP-B (reviews owed) lands its source *inside* `RadarReading` — this WP prepares that seam but does not open it.
- Background/async enrichment (the F6 review note) stays deferred.

## System-Wide Impact

- **Interaction graph:** scheduler → pipeline seam unchanged (RadarSource signatures preserved, modulo the possible `consumeResolutions()` consolidation — if taken, PollScheduler's two-call site collapses to one and the fixed-order footgun disappears).
- **Unchanged invariants:** `Result` field set (ProbeCommand's ~15 reads + EVIDENCE_JSON), effect ordering out of the reducer, snapshot semantics, all 1280 existing checks unmodified except where a suite name says otherwise in U2/U3.
- **Error propagation:** unchanged — failures still return `.failure` through the same seams.

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Silent behavior drift during the split | Probe-identical gate after U1 **and** U2; zero edits to existing tests in U1 |
| `public` surface creep in Core | Only types the App actually references gain `public`; reviewed in the diff |
| Clock injection changes re-verify timing | `now` threads from the shell's single `Date()` per tick; U3 asserts the 600s window end-to-end |
| Latch-order regression during consolidation | U2 row 3: the API shape itself removes the ordering requirement, and a test locks both latches clearing per tick |

## Disconfirming Evidence

- **Probe gate (kill condition):** if `githud probe` structure/fields differ pre/post at any unit boundary, stop and reconcile before proceeding — no "close enough".
- **Stub-harness gate:** U3's #416 reproduction must FAIL when the terminal-only rule is reverted (mutation check run once, manually, during U3).

## Bug-trace cross-check

| Known failure | Contract row | Locked by |
|---|---|---|
| 304 staleness (open cached forever) | U2 row 1 + U3 seq 1–2 | unit + stub-HTTP tests |
| Latch survives a tick / short-circuit | U2 rows 2–3 | unit test + API shape |
| F9 (failed /user marks resolved) | U2 row 4 | unit test |
| F6 (enrichment starvation) | U2 row 7 + U3 seq 4 | ordering tests |
| Snapshot-paint wiped by empty re-projection | U2 row 2 (decline-on-empty) | unit test |
