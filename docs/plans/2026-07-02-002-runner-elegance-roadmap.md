---
title: Runner contract — elegance roadmap DAG walk
type: runner
status: historical
date: 2026-07-02
origin: execution shape for 2026-07-02-001-roadmap-elegance-native-oss-plan.md; designed for a Fable session orchestrating subagents, stopping at user gates
---

# Runner contract — walk the elegance roadmap with subagents

You are a fresh session executing the checklist plan at
`docs/plans/2026-07-02-001-roadmap-elegance-native-oss-plan.md` ("the PLAN").
This document is your execution contract and your persistent state. **Update the
Runner State table below as you go** — it, not your context, is the source of
truth across compaction or a restart.

## Non-negotiables

1. **Doctrine binds.** Read `loop/INTENT.md` before touching product code. Ink by
   default; motion maps 1:1 to user action or real change; never fabricate a
   state; Open-on-GitHub is the action ceiling; calm, never busy. If a work
   package seems to require violating these, STOP — don't improvise.
2. **PRESSURE rows still owe their burdens** (`loop/PRESSURE.md`): focus-non-theft
   · idle-footprint · pulse-honesty · attention-non-theft. Any change to panel,
   polling, or motion must state in its commit how the burden is still met.
3. **Proofs are the definition of done.** Each PLAN row names its proof. A box is
   checked only when its proof ran. `scripts/test.sh` after every package;
   `scripts/build-app.sh` for app changes; visual-proof manifests for UI-visible
   changes (if the screen-rec harness is unavailable to you, say so in the stop
   report — never skip silently).
4. **Nothing leaves the machine without the user's OK.** Commit locally per
   package (conventional style, e.g. `feat(scheduler): …`). Do NOT `git push`,
   create GitHub releases, open PRs, or publish anything — those are STOP items.
5. **⛔ rows are the user's.** Never guess a gate. Never do Phase 2 design
   exploration yourself — it is human-participated by design.
6. **One writer per file.** Lanes below are cut on file ownership. Within a lane,
   packages run serially. Across lanes, run in parallel (worktree isolation for
   builder subagents; merge back per package).

## Subagent shape (suggested, adapt as needed)

Per work package: **(a)** a builder subagent (worktree isolation) implementing
only that package's rows, given the PLAN rows verbatim + the doctrine one-liner;
**(b)** for trust-critical packages (marked ⚠ below), an independent reviewer
subagent prompted to *refute* the change (miss risk, honesty violation, pressure
regression) before you merge — this repo's history: two deep reviews found real
bugs in code already treated as validated. Use Explore subagents for reading;
keep synthesis and merge decisions in the main loop.

## Lanes and work packages

### Lane A — repo/meta (owns: repo root, .github/, README.md; no Sources/)
- **WP-0** — PLAN Phase 0, all rows EXCEPT the release/push halves.
  Do locally: LICENSE (MIT — reversible default per PLAN), CI workflow file,
  CONTRIBUTING, issue templates, README orientation line + PAT reframe + badge.
  Tag `v0.1.0` locally. **Pushing the tag / creating the GitHub Release /
  bundle-id decision → gate ledger.**

### Lane B — core trust chain (owns: Sources/GithudCore/, PollScheduler.swift, RadarPipeline.swift, Tests/) ⚠
- **WP-1a** — reducer refactor: `RadarSource` protocol, injected clock, pure
  `(state, outcome) → (nextState, effects)` reducer for 401/403/rate-limit/
  retry/freshness; `dispatchPrecondition(.notOnQueue(.main))` in blocking
  methods. Full reducer test suite.
- **WP-1b** ← WP-1a — H2 pulse joins Freshness; poll-now triggers (wake,
  NWPathMonitor, panel-expand, debounced); rate-limit backoff at all five call
  sites; timer on `.common` mode.
- **WP-1c** ← WP-1b — live ages (timestamps in rows, format at render, re-render
  on bucket flip + expand); persisted last-known-good snapshot rendered stale via
  the freshness banner.
- **STOP after Lane B** for user review before treating Phase 1 as done — this is
  the trust moat's code.
- **WP-6w** ← WP-1a (optional, only if lanes are idle and user approved at a
  prior stop): async/await migration, Swift-6 language mode.

### Lane C — UI shell, serialized (owns: Sources/GithudApp/ minus Lane B files)
Order matters — these packages share HUDPanelController/AppDelegate/views:
- **WP-3e** ⚠ — render coalescing (one render per poll, not two) + per-lane
  scroll preservation; click-away collapse via passive global monitor; unified
  gear menu (Surface + Theme + Quit; Hide + Launch-at-login join when built);
  micro-polish: monospaced digits, hover-fill ease, Control-click = right-click.
- **WP-5i** — launch-at-login (SMAppService + menu item); screen anchoring
  (status item's screen, observe `didChangeScreenParametersNotification`);
  wire `hide()`/`show()` into the menu; `accessibilityValue` on the collapsed
  pill for every state; Increase Contrast; appearance-change CGColor repaint.
- **WP-4e** — token plumbing behind the existing MessageView: Keychain write
  path, classic-PAT shape validation, hot start (token stored → live scheduler,
  no relaunch), auth-error routing. Card visuals wait on design (WP-4d).
- **WP-6h** — global summon hotkey (toggle expand; no key status needed).
- **WP-6a** — AppModel (single observable state; controllers render from it),
  `IslandSurfaceFactory` extraction, dedupe the `!isDraft && !isStale` rule via
  presenter sections. Last in lane: it refactors what the others touched.

> **Runner scheduling note (post-WP-3e):** the remaining packages (1c, 5i, 4e,
> 6h, 6a) all touch shared GithudApp files (AppDelegate, views), so lanes B and C
> serialize from here: 1c runs EXCLUSIVE with extended ownership of
> IslandContentView/CollapsedPillView/AppDelegate (live ages format-at-render +
> snapshot launch-paint need them) and absorbs two stitches (panel-expand →
> pollNow wiring; it lands after 1b). Then 5i → 4e → 6h → 6a serially.

### Blocked until user input (do NOT start; list in every stop report)
- **WP-3d / WP-3d′** morph build, bottom fade, caught-up state, text reveal
  ← designer-loop records (D-morph, D-copy, D-reveal) + WP-3e landed.
- **WP-3x** pill crossfade ← ⛔ G-crossfade.
- **WP-4d** welcome card ← D-card + WP-4e.
- **WP-5g** status-item glyph ← D-glyph.
- **WP-6k** keyboard session ← ⛔ G-keyboard + WP-6h.
- **Launch package** (push, release, signing/notarization/Sparkle/cask, hero
  GIF, HN/PH) ← WP-3d + WP-4d + explicit user go.
- **Phase D** dogfood (suppressed-set audit, daily-driver) ← user only.

## Stop protocol

STOP means: finish in-flight packages, update the Runner State table and PLAN
checkboxes, commit, then **end your turn** with this report (no idle waiting):

```
STOP REPORT
Landed: <WP ids — one line each: what + proof + commit sha>
In progress / parked: <ids + why>
Blocked on you:
  1. <gate/decision, with the runner's recommendation and why>
  2. …
Next unlocks: <what each answer unblocks>
```

Mandatory stop points:
- **S1** — Lane B complete → trust-code review request.
- **S2** — all Lane A+C packages complete → the big one: request designer-loop
  sessions (D-morph, D-card, D-glyph, D-reveal, D-copy), gate calls
  (G-crossfade, G-keyboard), license/bundle-id confirmation, push/release
  permission, dogfood kickoff.
- **Any time**: a doctrine conflict, a destructive/outward-facing action, a
  package failing its proof twice, or file-ownership conflicts the lanes didn't
  predict.

S1 and S2 may collapse into one stop if lanes finish together. After the user
answers, resume: unlock the newly-unblocked packages, repeat.

## Runner State  ← runner: keep this current

| WP | Status | Commit | Notes |
|---|---|---|---|
| WP-0  | **landed + shipped** | 5be626f, 7caec5e, b525fef | 2026-07-06: pushed to private `pro-vi/githud`; CI green on first push (run 28838760847); v0.1.0 retagged at b525fef + Release live (zipped ad-hoc build, labeled unsigned); bundle-id → `me.provi.githud` |
| WP-1a | **landed** | 22577b8 + 1575300 (stitch) | 3-lens adversarial review: PASS ×3, 3 minors noted; 362 checks; probe off-main proven; precondition unconditional |
| WP-1b | **landed** | 8951d27 | review PASS ×3 (4 minors, none trust-breaking); 422 checks; scope-403 discrimination empirically probed correct; deferred minors → WP-1c |
| WP-1c | **landed** | d46b11d + 8ebf504 + eb928ff | review found 2 BLOCKERS (filter-revert on age-flip; stuck-stale banner) → all fixed; focused re-verify: MERGE, all 5 confirmed; 504 checks. **S1 signed off 2026-07-06 ("i trust your impl") — Phase 1 done.** |
| WP-3e | **landed** | aa7e25f + 8fca3dc | review 2 PASS + 1 MAJOR (hide() monitor leak) → fixed + live-proven; 362 checks + app build green on main; visual manifest honest-skipped (screen locked) |
| WP-5i | **landed** | b4dca46 + e2b0574 | review MERGE, zero defects; 523 checks; visual proof 347 CAPTURED (pixel_live, frontmost_unchanged, idle 0.5); VO value presenter unit-proven; real VO/multi-monitor/login-toggle proofs need a live session |
| WP-4e | **landed** | 688de4f | review MERGE zero defects (double-start refuted; keychain opt-in tests clean; dev aid stripped from release); 527 checks |
| WP-6h | **landed** | e86b10d | ⌃⌥G via Carbon RegisterEventHotKey (permissionless); OSStatus 0 live-proven; runner diff-review clean; 527 checks |
| WP-6a | **landed** | ebd501d + aec373a (+b386fe8) | 3-lens panel: zero behavior drift (PASS/PASS + 1 evidence-gap major: app target has no automated tests — CLT substrate); 543 checks; provenance-clean manifest 349 at merged HEAD. **All 9 packages done → S1+S2 STOP.** |
| WP-6w | blocked (user opt-in) | — | — |
| WP-3d + 3x | **landed** | 5e23095 + 910aa29 + fe00854 | hand-off morph shipped — NO fallback needed (frame-stepped live proof: band overlaps in time never position; zero drift). Panel: FIX ×3 (3 majors: message-vs-hide both doors, bottom fade pulsing on polls, alpha-strand on show-mid-tuck) → fix round → focused re-verify: MERGE, 7/7 closed. 659 checks; merged binary 0.0% CPU idle. Residuals for dogfood: ~370ms hide two-beat (fallback pre-registered), empty-glass tuck-tail (near-nil), fade-band pixel manifest |
| WP-5g | **landed** | f56ed1d + hardening | 3-lens panel: MERGE ×3, zero blockers/majors-requiring-fix; 599 checks; runner hardened false loading-comment + proof-command nil-context guard. Open for a live session: real-bar tint/gap eyeball (light+dark), critical+degraded shield geometry (builder's interpretation, flagged), "githud — githud, loading" tooltip → D-copy pass |
| WP-4d | **landed** | 7c70057 + 4cd0221 + f029cf9 + hardening | handshake-ledger card, MessageView retired. Panel: FIX ×3 incl. 2 BLOCKERS (⌘V had no dispatch route; click-back killed the field) → fix round rebuilt key mechanics on becomesKeyOnlyIfNeeded → re-verify: 12/12 closed + 1 new hole (selectable prose labels took key) → runner two-line fix, probe-verified. **Ratified before-merge key-routing proof CUT** (loop/evidence/wp4d-key-routing.manifest.json, synthesized-hands — human-hands re-cut optional at dogfood). 785 checks. Spec amendments recorded in the agenda (resignKey() error, eligibility gate, morph grammar) |
| WP-3d′ | **landed** | 0a01fbf + 3e0f3a5 + c942a4f + 6ea9160 + landing | caught-up affirmation (radar-confirmed gate, tense + age-0 rules), chevron inline peek (hitTest carve-out, stable row ids, recorded routing manifest wp3dprime-chevron-routing), plainspoken sweep. Panel FIX ×2 (affirm-unread-inbox; unrecorded proof) → round 1 → re-verify caught the recompute inlet → round 2 (radarConfirmed rides the radar-success seam) — 3 review passes, each drew blood. 884 checks. Hover-slab DEFERRED (recorded in agenda) + known-limitations for dogfood. **2026-07-09:** the deferral's "no bearing on peek correctness" rationale falsified by the first dogfood defect (chevron drift = the missing width pin); slab WIDTH half now BUILT via the lane-row fix (agenda correction entry + loop/evidence/lanerow-fullwidth.manifest.json), padding/spacing respec still the open micro-decision |
| WP-6k | **landed** | 3530040 + 04565e1 + 8009b80 + hardening | ⌃⌥G scoped key session, ink bar, Space→peek compose. Panel: MERGE ×2 + records-only FIX (drift) — zero fix-mandatory code defects on first review, a board first. Recorded proof: every ratified key leg witnessed incl. mouse-path never-key (loop/evidence/wp6k-key-session.manifest.json). Runner hardenings: isKeyWindow confirm after makeKey (chrome follows real key state), modifier-chord gate (plain keys only), IME + unwitnessed-end-path debts restored to PRESSURE, debugKeyLog data class + glyph swap recorded. 927 checks. **ALL RATIFIED PACKAGES LANDED.** |
| Lane-row fix | **landed** | 94e4461 | first dogfood defect (user screenshot): rows hugged fitting width → chevron drift + dead zones. Width pin = the hover-slab WIDTH half (deferral rationale falsified, corrected); glyph .top supersedes iter-041 centerY (recorded; 1-line revert offer stands). 3-lens panel: code clean, ledger fixes. Witness lanerow-fullwidth.manifest.json |
| Inbound | **landed** | (this commit) | user-directed 2026-07-09: derived `inbound` reason — PRs/issues others open on OWNED repos out of the `subscribed` firehose; own-repos scope, default ON, era-stamped store migration. 3-lens panel FIX-FIRST ×3 → fix round: ownership-gated enrichment (subject-state + comment-author), 304-tick self-resolution re-projection (never-miss), effectiveReason changeKey, knownReasons novelty gate, probe speaks effective taxonomy. 966 checks. Live no-op today (zero subscribed in 384 unread — see agenda record); first real arrival = the live proof (dogfood watch) |
| Inbound-sweep | **landed** | (this commit) | the STANDING "at your door" lane (distinct from the event-channel derived reason above): one search sweep/tick → third island section, waiting-longest-first queue, bots/drafts held back (gear reveal), peeks + ink-bar + snapshot + fixture path. Opus panel FIX-FIRST ×3 → fix round: inboundConfirmed gate (affirmation + PILL both — the pill's ✓/spoken "caught up" over a waiting queue was the BLOCKER; inbound tray+count tier added), running guard after auth-stop, updatedAt out of change key + peek signature, truncation/incomplete disclosure logs, -author-clause disjointness comment. 1010 checks; three-lane visual proof. Live sweep of the real account pre-build = the fixture (8 items, 5/3 human/bot split validated); close/merge departure live-witness owed to dogfood |
| Plain words | **landed** | 8f2019a | dogfood copy session (WP 2026-07-12-001): the collapsed captions read machine-made → live gallery (docs/design/2026-07-12-plain-words-mocks.html), user ratified flavor C (old-web parenthetical) + the padded footer. "N gone quiet (show)" / "N from bots & drafts (show)"; captions became full-lane buttons flipping the SAME pref the gear flips (one code path, persistence on it); revealed headers "Gone quiet"/"Bots & drafts" carry a right-edge "(hide)"; gear reworded with the 14d threshold demoted to tooltip; footer "GitHub inbox ↗" only (audit intent kept in the VO label) with a ~30px band. Strings live in Core (PlainWords.swift), 1/N pinned. Panel: MERGE ×3, zero mandatory fixes (second board-first). 1172 checks. Dogfood watches: VO read of the caption buttons (inner labels unsuppressed, matches shipped convention); (show)/(hide) affordance readability without hover; footer band vs island bottom edge; reveal easing on glass. SAME-DAY ADDENDUM landed 1fec282: Drafts joins the family (user: "make them the same path") — "Draft PRs" revealed header + (hide) on the shared helper, third instance of the one-truth pref path, zero-rows guard, strings + tooltip to PlainWords; PRESERVED asymmetry: no collapsed caption (hidden drafts stay invisible by doctrine). Focused re-verify LAND, 1175 checks |
| D-pill config | **landed** | acadf99 + c5226a4 | the pill-vocabulary session's resolution (WP 2026-07-10-001): 3 designers × 6 variants × 3 refuters (all claims code-verified; composed pair KILLED — F2 double-count, F4 two-reds vs the PAID blind-read) → user ratified CONFIG over doctrine-pick. PillStyle (queueLeads default / standingMarked / standingCounted) + gear "Pill style…" chooser card with live CollapsedPillView previews (radar suppressed, coincide/unconfirmed notes — never a fabricated queue) + D1 per-fact stale clock (sweep clock covers inbound-count states; F-1 fix: change-gated crossing emission rides the poll tick, both directions, timer-free). resolve() = one decision tree for fingerprint+width+spoken (F5 lockstep by construction; width moved to pure Core). Panel: MERGE ×2 + FIX-FIRST ×1 (the F-1 render-trigger hole) → fix round → focused re-verify LAND (8/8 claims confirmed, additive-only tests). 1153 checks. Recorded: 12pt inline tray ratified; plural count-free copy ratified; chooser-after-ledger re-present + open-chooser theme-switch = dogfood watches; recovery crossing clears next-tick (~60s bound, documented) |
| Launch | partially unblocked | — | private push + Release done 2026-07-06; PUBLIC visibility, signing/notarization, hero GIF, HN/PH still user-gated |

## Gate ledger (mirror of the PLAN's decision log — user answers land here too)

| Gate | Needed for | Answer |
|---|---|---|
| MIT confirm (defaulted yes) | WP-0 finalization | ✅ 2026-07-06 — holder `provi (me@provi.me)` |
| Bundle-id namespace | WP-0 README note | ✅ 2026-07-06 — delegated; moved to `me.provi.githud` (b525fef) |
| Push tag / create Release | Lane A completion | ✅ 2026-07-06 — **private** repo `pro-vi/githud`; main + v0.1.0 pushed; Release live; public later |
| Trust-code review sign-off | Phase 1 done | ✅ 2026-07-06 — "i trust your impl" |
| D-morph · D-card · D-glyph · D-reveal · D-copy | WP-3d, 4d, 5g | ✅ 2026-07-06 — user ratified ALL runner picks via mock review: hand-off morph, handshake-ledger, constant-beacon (amended), chevron-inline-peek (blocking amendments), plainspoken-as-amended + borrowed footer. Records: `docs/design/specs/*.json` + agenda |
| G-crossfade | WP-3x | ✅ 2026-07-06 — C slot-morph: cell-local 120ms fades, equal-digit ticks stay still, width settles 150ms, critical flip is the one color animation. Written invariant: "no motion where no fact changed" |
| G-keyboard | WP-6k | ✅ 2026-07-06 — scoped key session with ink-bar focus; Carbon 0-modifier capture permanently banned. Pre-merge obligations: re-word PRESSURE proof line + re-cut recording; reset keySessionActive in setExpanded(false); scope D-card's field key-moment as the SAME relaxation |
| async/await opt-in | WP-6w | — |
| Launch go (public/signing/HN-PH) | Launch package | — |
