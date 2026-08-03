---
title: WP-B — reviews owed: a standing source inside "Needs you"
objective: A review you owe can never silently vanish from the radar just because you once glanced at its notification — the miss class that hid two live teammate PRs for four days
type: feat
status: completed
date: 2026-07-17
origin: dogfood 2026-07-17 (acme/core #551/#513 open + review-requested, invisible because their notifications were read) — user ratified "both WPs", holistic redesign licensed
---

## Background (read cold)

"Needs you" mirrors the *unread* notification inbox. Opening a PR page marks its notification read, and read notifications leave `GET /notifications` forever — while the review request stays formally pending until a review is submitted or the PR closes. Result: the user's two genuinely-owed reviews were invisible; the lane affirmed states it had no right to affirm. Review-owed is a **standing fact** (like the inbound sweep), not an event, so it needs a standing source: `GET /search/issues?q=is:open is:pr review-requested:{login}`.

Reconnaissance (2026-07-17) settled the shape: the pill count (`PillMorph.resolve` acute path), the menu-bar glyph (`StatusGlyphPresenter`, H1-only), the caught-up affirmation (`CaughtUpPresenter.display`'s `rows.isEmpty` gate), and the island lane all consume **one array** — `rows: [RadarRow]` from the ranked-thread set. Merging reviews into that set is the single join point where all four surfaces stay in lockstep with zero extra plumbing. A fourth lane (byte-clean inbound clone) was rejected: it contradicts "review-owed IS needs-you," needs four new seams, and reopens the composed-pill-tier problem `PillMorph` explicitly closed (PillMorph.swift:78-82).

**Depends on WP-A** (`docs/plans/2026-07-17-001`): the merge, adopt baseline, and dedup live in the tested `RadarReading` Core model.

## Architecture Decision

**Approach:** Clone the inbound sweep's *standing discipline* — search fetch, `InboundReading.adopt` (incomplete never removes), confirmation stamped only on complete readings — but **synthesize minimal `NotificationThread`s from the search items and merge them into the thread set inside `RadarReading`**, deduped against real threads by html URL, *before* `SignalClassifier.radar/suppressed` runs. Everything downstream (classification, urgency 95, surfaces(), changeKey, rows, pill, glyph, affirmation count, ⌃⌥G walk, snapshot rows) works unchanged because a review-owed row *is* a ranked thread.

**Rationale (why synthesis over alternatives):** (1) Merging at the row level would bypass `RadarRefresh.radar: [RankedThread]` and force spine surgery on `PollReducer` — rejected; the spine stays byte-untouched. (2) A separate lane — rejected above. (3) Synthetic threads are honest here: every populated field is a real fact from the search item (title, html url via subject.url shape, updated_at, repo, PR-ness, `reason: "review_requested"` — which is literally true); `unread` is set true as "standing = unhandled," the one semantic stretch, disclosed in the type's doc. The id is prefixed (`review-owed:owner/repo#N`) so it is structurally disjoint from real thread ids, inbound ids, and pulse ids by construction.

**Dedup contract:** a PR appearing as BOTH an unread `review_requested` thread and a search item keeps the **thread** (richer: enrichment, excerpt, latest-comment author) and drops the synthetic. Match key: normalized html URL (thread side via `RadarPresenter.htmlURL`; search side `item.url`) — no string parsing. Cross-LANE overlap with the inbound sweep (an outside PR on your own repo that requests your review) is allowed and recorded: different asks (triage at your door vs review owed), same as the existing radar-event/inbound-standing coexistence.

**Confirmation is separate and fail-closed:** `rows.isEmpty` covers the *count* under the merge, but "confirmed empty" additionally requires the reviews search to have completed — a failed search must never let the island affirm. `reviewsConfirmed` joins `CaughtUpPresenter.display`'s guard with a fail-closed `= false` default (the `inboundConfirmed` precedent, verbatim).

**Toggle:** review-owed rows carry raw reason `review_requested` and are governed by the existing "review requested" surface toggle — it *is* a review request in standing tense. A separate toggle (and the `legacyAutoReasonsV2` migration it would force) is deferred; recorded below.

**Trade-offs:** one more search per tick (~2/30 of the search bucket — comfortable); synthetic `unread: true` is a modeled convention, pinned by tests and a doc comment. Interim counted-line dropped: under this design real rows cost barely more than the caption would have.

**Representation ledger (one-way doors):**
- **Synthetic id prefix** `review-owed:` — persisted inside `Snapshot.radar` rows; the prefix IS the provenance marker. Never reuse it elsewhere.
- **`Snapshot.lastReviewsSuccessAt: Date?`** — new optional field, tolerant decode (the `lastInboundSuccessAt` precedent).
- Match-key authority: html URL as emitted by GitHub (search `html_url`; thread via the one existing converter `RadarPresenter.htmlURL`). No second parser.

## High-Level Technical Design

```
tick: refresh() ─ GET /notifications ──> threads
        └────── GET search review-requested:{login} ──> ReviewsReading (= InboundReading shape)
RadarReading:
    reviewsBaseline = InboundReading.adopt(previous, new)        // flaky search never erases standing truth
    synthetic = reviewsBaseline.items
        .filter { no real thread with same html URL }            // dedup, thread wins
        .map(NotificationThread.reviewOwed(from:))               // id "review-owed:owner/repo#N", reason review_requested
    radar()/suppressed() run over (threads + synthetic)          // classification/urgency/surfaces unchanged
Result gains: reviewsComplete: Bool                              // !incomplete on THIS tick's reading
scheduler: onReviewsConfirmed?() when complete  ──> AppDelegate ──> model.confirmReviews()
CaughtUpPresenter.display(..., reviewsConfirmed: Bool = false)   // fail-closed; island call site passes model fact
Snapshot: + lastReviewsSuccessAt (optional) ── cold-launch seed mirrors inbound (confirm only on real provenance)
```

A review lands / PR closes → the item leaves the next COMPLETE reading → synthetic thread gone → row leaves radar. The user reviews via GitHub; githud needs no write path.

## Implementation Units

### U1. Core: the reviews search fetch + fixture decode

- **Goal:** `GitHubClient.fetchReviewRequestedSearch(login:)` returning the `InboundReading` shape, plus a committed real-response fixture test.
- **Dependencies:** WP-A landed
- **Files:** Modify `Sources/GithudCore/GitHubClient.swift`; Create `Tests/Fixtures/reviews-search.json`; Test `Tests/GithudCoreTests/main.swift`.
- **Approach:** Sibling of `fetchInboundSearch` (same endpoint, headers, rate handling, per_page 50, oldest-first so the debt head survives the cap): `q = "is:open is:pr review-requested:{login}"`. Reuse `InboundItem.reading(fromSearchData:)` decode. Capture the fixture from a real (redacted) response for #551/#513-era data.
- **Test scenarios:** *Happy path:* fixture decodes; totalCount/incomplete ride through. *Edge:* every item `isPR == true` under `is:pr`.
- **Verification:** decode suite green; query string unit-pinned (no `-author` clause — the requester may be anyone, including bots via CODEOWNERS; deliberate-routing doctrine applies).

### U2. Core: synthesis + dedup + adopt inside `RadarReading`

- **Goal:** The merge — standing review facts become ranked threads, honestly and exactly once.
- **Dependencies:** U1
- **Files:** Modify `Sources/GithudCore/RadarReading.swift`, `Sources/GithudCore/NotificationThread.swift` (the `reviewOwed(from:)` factory + doc for the `unread: true` convention); Test `Tests/GithudCoreTests/main.swift`.
- **Approach:** `adoptReviews(reading)` transition (delegates to `InboundReading.adopt`); synthesis factory; dedup by html URL preferring real threads; merged set feeds the existing `radar()/suppressed()`.
- **Test scenarios (contract rows):**
  - *Dedup:* same PR as unread thread + search item → one row, the thread's (assert enrichment fields survive).
  - *Fold-not-drop:* incomplete reading + prior baseline → prior kept whole (standing truth survives a flaky search).
  - *Departure:* item absent from a COMPLETE reading → synthetic gone next compute.
  - *Read-notification case (THE bug):* no thread + search item → synthetic surfaces at urgency 95, `id == "review-owed:o/r#551"`.
  - *Disjointness:* synthetic id never collides with thread/inbound/pulse id spaces (prefix asserted).
  - *Suppression interplay:* a synthetic row is never subject-resolved (state nil; `is:open` guarantees it) and never bot-demoted (deliberate routing — already pinned).
  - *changeKey:* review row joins `RadarPresenter.changeKey` → renders on arrival/departure only.
- **Verification:** with a fixture reproducing 2026-07-17 (#551/#513 read-notifications), the radar computes exactly two review-owed rows.

### U3. Confirmation + persistence + seeds

- **Goal:** The affirmation can never claim caught-up over an unread reviews search; cold launch stays honest.
- **Dependencies:** U2
- **Files:** Modify `Sources/GithudCore/RadarPipeline.swift` (`Result.reviewsComplete`), `Sources/GithudCore/CaughtUpPresenter.swift` (guard param, fail-closed), `Sources/GithudCore/SnapshotStore.swift` (`lastReviewsSuccessAt`), `Sources/GithudApp/PollScheduler.swift` (`onReviewsConfirmed`, snapshot save + seed), `Sources/GithudApp/AppDelegate.swift` (wire + cold-launch/fixture seeds), `Sources/GithudApp/AppModel.swift` (`reviewsConfirmed` + guarded confirm, `.radar`-style notify), `Sources/GithudApp/IslandContentView.swift` + `Sources/GithudApp/HUDPanelController.swift` (pass the fact to `CaughtUpPresenter.display`).
- **Approach:** Mirror `inboundConfirmed` end-to-end, including the fixture path's simulated confirm. Snapshot field optional + tolerant decode; seed confirms only on non-nil provenance.
- **Test scenarios:** *Fail-closed:* `display(...)` without the new argument never affirms when reviews unknown; *Happy:* confirmed + zero rows affirms; *Edge:* old snapshot JSON decodes (nil → unconfirmed).
- **Verification:** Core gate tests green; probe on live data shows the affirmation withheld until the first complete reviews search.

### U4. Probe + evidence + dogfood closure

- **Goal:** Observability and the real-world check against #551/#513.
- **Dependencies:** U3
- **Files:** Modify `Sources/GithudApp/ProbeCommand.swift` (reviews line + EVIDENCE_JSON fields).
- **Approach:** Print `reviews: owed=N complete=bool` and the owed items under `--show-items`; extend evidence JSON additively (existing fields untouched).
- **Test scenarios:** `Test expectation: none — probe is App-side output; verified by live run.`
- **Verification:** Live probe lists #551 and #513 as owed; the island shows both rows; marking a review submitted on GitHub removes the row on the next complete sweep (dogfood step, recorded in PR).

## Scope Boundaries

- **No separate surface toggle for review-owed** — governed by the existing `review_requested` reason. Separate toggle + `legacyAutoReasonsV2` migration deferred.
- **No reviews-specific stale prefix on the pill** — confirmation gates the affirmation only; a sweep-freshness-style clock for reviews is deferred.
- **Inbound lane untouched**; cross-lane coexistence (own-repo PR that's both at-your-door and review-owed) is accepted and documented, mirroring the event/standing coexistence precedent.
- **No write path** (no "mark reviewed" in-app).

### Deferred to Follow-Up Work

- Reviews sweep-freshness clock + pill prefix (if dogfood shows stale-search confusion).
  When this lands, take the clock relocation as its U1 (refactor pass 2026-07-17,
  reported-not-moved): `lastReviewsSuccessAt` lives as an untested PollScheduler field
  while its inbound twin rides pure reducer state — the freshness cue wants the reducer
  home anyway (crossing emissions), and that WP owns the spine touch.
- Confirmation-gate the collapsed pill's `.check` tier (Codex P1 round 4 — DEFER,
  non-blocking, pre-existing): `PillMorph.resolve` takes NO confirmation facts, so the
  checkmark can draw while `CaughtUpPresenter` refuses to affirm — true for radar,
  inbound, AND reviews alike (`loading = !hasData`, and hasData flips on any row paint
  incl. snapshots — the exact trap the island's gate was built to avoid, AppModel:112).
  This WP narrowed the false-green (owed reviews now populate rows) and touched no pill
  code. Complete fix spans all three facts and needs a pill-grammar design decision
  (what draws in unconfirmed-empty: gray check? loading? nothing?) + fingerprint/width/
  a11y/VO parity — a designer-session unit, not a patch.
- Separate settings toggle for standing review rows.
- ~~Team review requests (`team-review-requested:`)~~ — RESOLVED 2026-07-17, no work
  needed (Codex P1 rounds 3+6, refuted by GitHub's own docs): the search-syntax docs
  state for `review-requested:USERNAME` — "If the requested person is on a team that is
  requested for review, then review requests for that team will also appear in the
  search results" (docs.github.com/en/search-github/searching-on-github/
  searching-issues-and-pull-requests). Plain `review-requested:` already expands team
  membership; `user-review-requested:@me` exists precisely as the DIRECT-only variant.
  The sweep's one query therefore covers CODEOWNERS/team requests as-is, and it matches
  the kill-condition reference page's qualifier family by construction. No read:org
  scope, no team enumeration, no fan-out.

## System-Wide Impact

- **Interaction graph:** one new Result field + one scheduler callback + one AppModel fact; the render spine, reducer events/effects, pill/glyph/a11y presenters, KeySession, and the island lane are all **byte-untouched** — that is the design's central claim, and U2's tests hold it.
- **Error propagation:** a failed search behaves like a failed sweep — last-good baseline kept, confirmation withheld, nothing removed, nothing affirmed.
- **State lifecycle:** Snapshot gains one optional field (tolerant decode locked); synthetic rows persist inside `Snapshot.radar` and repaint on cold launch like any radar row, then the first live tick re-derives them.
- **API surface parity / unchanged invariants:** `PollReducer` untouched; `RadarRefresh` untouched; effect ordering untouched; auth-stop invariant untouched (reviews fetch rides `refresh()`, which the auth-stop precedes).

## Risks & Dependencies

| Risk | Mitigation |
|------|------------|
| Search bucket pressure (2 searches/tick) | 30/min bucket, ~2 used; shared rate-pause already fails fast; recorded |
| Synthetic `unread: true` leaks into a surface that means literal unread | grep-audit of `unread` consumers in U2; the only consumers are radar/suppressed filters — asserted in plan review |
| Dedup misses on URL normalization edge (trailing slash, case) | match on exact GitHub-emitted forms both sides; one normalizer, tested with fixture URLs |
| A dismissed/declined review request lingers until PR close | GitHub removes the reviewer from `review-requested:` on re-request-cycle/dismiss — the search is the authority; dogfood watch item |
| Affirmation regression via forgotten call site | fail-closed default: an un-updated caller can never affirm (the CaughtUp precedent, verbatim) |

## Disconfirming Evidence

- **Kill condition:** if the live probe's owed set disagrees with `github.com/pulls/review-requested` for the account, the query or decode is wrong — stop, fix, re-verify before shipping rows to the glass.
- **Dogfood probe:** after landing, #551/#513 must appear within one tick and disappear on review submission — recorded in the PR as the acceptance fact.

## Bug-trace cross-check

| Requirement (from the 2026-07-17 diagnosis) | Discharged by |
|---|---|
| Read-but-owed reviews visible | U2 read-notification contract row |
| Flaky search never erases standing truth | U2 fold-not-drop (adopt) |
| Never affirm over unknown reviews state | U3 fail-closed gate |
| Pill/glyph/island/affirmation counts agree | Shape decision (one array) + U2 changeKey row |
| No duplicate rows for thread+search PR | U2 dedup row |
| #551/#513 concretely surface | U4 live verification |
