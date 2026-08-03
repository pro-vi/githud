# githud — creative consults (invariant 8)

Blind adversarial creative-direction consults. Each records the packet (no scores,
no preferred plan, no self-justifying rationale), the verdict, and the **behavioral
change it forced** (a consult that changes nothing and isn't explicitly rejected
does not count).

---

## Consult 001 — iter 1 — rubric+intent blind read

- **Channel:** PAL → `gpt-5.2` (OpenAI; different model family than the Claude that
  generated the work, per invariant 8). `google/gemini-3-pro-preview` was tried
  first but has no live endpoint; gemini-2.5-pro available as fallback.
- **Date:** 2026-06-16 (iter 1).
- **Packet (blind):** verbatim user intent; H1/H2/H3 presented neutrally (no
  stated preference); current state (empty glass island, no data); the 10 rubric
  criteria **without scores**; known constraints (classic-PAT-only, threads-not-
  events, stars/forks deferred). Excluded: scores, the loop's next plan, rationale.
- **Questions:** (1) kill/demote which hypothesis; (2) seductive-but-hollow;
  (3) derivative/embarrassing in 6 months; (4) over-optimized assumption;
  (5) cheapest rubric-invalidating experiment.

### Verdict (summary)

1. **Kill H3 outright** (mailbox→cockpit category error; explodes auth/attention).
   **Demote H2 to a future skin, not core** — Notifications API does NOT supply
   reliable real-time presence ("N people looking", merge-readiness, CI pulse);
   building H2-as-core means faking it with polling+heuristics → wrong often →
   trust destroyed. **Promote H1 — but reframe its core from "you have
   notifications" to "do I need to ACT?"** The wedge is high-signal filtering +
   one-glance triage; the HUD is just the wrapper. Blend: H1 engine, *subtle* H2
   skin only when the signal is truly actionable.
2. **Seductive-but-hollow = the glass island itself.** Demos like magic for 30s,
   then becomes visual lint or a resented distraction. Notification threads are
   ambiguous (LGTM vs nit vs needs-changes vs bot) → activity ≠ urgency. Polling
   makes "ambient" laggy/random. **Hover-expand is a trap**: the cursor passes the
   top of the screen constantly (tabs, address bar, traffic lights, menu bar) →
   accidental expansions → you add hysteresis → it feels sluggish.
3. **Embarrassing in 6mo:** "Arc but HUD" anchors on a competitor (warning sign);
   top-center glass pill is now a commodity trope ("aesthetic cosplay"); PAT-only
   auth *feels* sketchy/dated even when secure; "unread count + list" is just a
   menu-bar app. The only moat is **signal quality + focus respect, not glass.**
4. **Over-optimized assumption:** that *native-overlay fidelity* is the hard part.
   It isn't — actionability + trust + workflow-fit are. Of 10 criteria only **#4
   (signal relevance)** is the existential risk; the rest are table stakes *after*
   you can answer "does GitHub need me right now?" Also: **focus-non-theft ("don't
   activate") is necessary but insufficient — the real enemy is ATTENTION theft**
   (motion, novelty, persistent presence). A non-activating panel can still be an
   attention vampire. Proposed north-star: **"# of useless GitHub checks the HUD
   prevented per day."**
5. **Cheapest invalidating experiment:** a **3-day trust-and-usefulness test** with
   a *fake* HUD and *real* notifications, BEFORE more overlay work. ≤5 pings/day
   using the intended filter rules (mention / review-requested / your-PR comment /
   assignment); users log **false alarms** (pinged, no action needed) and **misses**
   (had to act, no ping). **Fail condition that kills the direction:** "I still
   check GitHub anyway because I don't trust it."

Clarifying Qs raised: (a) first archetype — PR authors / reviewers / maintainers /
managers? (b) willing to be explicitly *action-required only*? (c) daily
false-alarm budget — 0 / 1–2 / 5+?

### Assessment (agree/reject, with reasons)

Largely **ACCEPT.** The redirect is correct and truer to the original "does GitHub
need me right now." Specific dispositions:
- **ACCEPT** kill H3, demote H2 (presence signals genuinely unavailable from the
  Notifications spine — this is *invalidating evidence* for H2-as-core, logged).
- **ACCEPT** reframe H1 → "the action radar"; signal/trust is the moat.
- **ACCEPT (new):** hover-expand-as-primary is a real trap → reconsider the summon
  affordance (criterion 5 reframed; click/explicit-summon or tightly-bounded hover
  with hysteresis, not whole-top-edge hover).
- **ACCEPT** the reweight: native fidelity is table-stakes, not the differentiator
  → RUBRIC v0.2 elevates signal/trust + adds attention-non-theft.
- **PARTIAL** on PAT: it's a hard API constraint, not a choice — but the *trust feel*
  is mitigable (transparent Keychain storage, minimal scopes). Keep as motivation.
- **NUANCE:** do not discard native-feel work — it's cheap, done, and necessary
  (an ugly always-on app gets killed). Keep its criteria, just stop calling it the moat.

### Behavioral change forced (this is what makes the consult "count")

1. **INTENT.md reframed** (first-class reframe, invariant 3): H1 → "action radar
   (do I need to act?)"; H2 demoted to skin with invalidating evidence recorded;
   H3 killed; north-star metric + the 3-day trust experiment pre-registered as the
   cheap distinguishing probe.
2. **RUBRIC → v0.2** (invariant 4 quarantine; v0.1 had no scores so quarantine is
   free): signal-relevance elevated to the spine; **new criterion: signal trust /
   correctness** (false-alarm & miss rate, budget ≤1–2/day); **new criterion:
   attention non-theft** (motion/novelty/persistent-presence restraint, distinct
   from focus non-theft); native-fidelity reframed as table-stakes weighting;
   hover-expand criterion reframed around accidental-trigger resistance.
3. **Two consult-driven pressure rows added** (STATE): `attention-non-theft`
   (burden) and `signal-trust-budget` (burden).
4. **Product-direction defaults set** (judgment default, logged as Alignment
   Reviews — reversible, NOT escalated): archetype = **PR authors + reviewers**;
   **action-required-only = yes** (FYI/stars/forks out of core); **false-alarm
   budget = 1–2/day** initial target.
5. **Build order reprioritized:** iter 2 builds the signal/trust classification
   model (action-required vs FYI) in GithudCore, fixture-driven + headless-tested —
   it is criterion-4's evidence surface AND the experiment harness, runnable on
   real data the moment the `github_classic_pat_ready` gate flips.

PAL continuation_id: `ad4d8699-9e65-4124-b48e-12fdb15717b8` (49 turns left).

---

## Consult 002 — iter 8 — blind VISUAL comprehension read (invariant 2)

- **Channel:** PAL → `gpt-5.2` (non-Claude family). Blind: only the screenshot, no
  rubric / scores / "I built this" / product name.
- **Artifact:** `loop/evidence/hover-expanded-normal-desktop-8.png` — the populated
  expanded island rendered from the fixture (visual-proof manifest
  `hover-expanded-normal-desktop-8.manifest.json`: status=captured, pixel_live=true,
  size_class=expanded 520×173, frontmost_unchanged=true, variance 680 / 64 colors).
- **comprehensionClaim:** "a native macOS HUD overlay showing the GitHub items that
  need your action (review requests, mentions, assignments) with urgency / repo /
  who / age — glanceable, first-party-feeling."

### Verdict
- **Function — MATCHES.** Read independently as "a menu-bar inbox/triage for dev
  work items — what needs your attention (reviews/mentions/assigned), glanceable,
  click-through." The action-radar intent came through with no priming. ✓
- **Native-feel — DIVERGES.** Reads as a "competent **third-party**" app, NOT
  first-party. Specifics: vibrancy looks "flat / mild gradient, not the alive macOS
  blur of Control Center / Notification Center"; typography/spacing feels "web
  list"; **missing macOS row anatomy** (leading SF Symbols, separators, trailing
  chevrons, timestamp alignment); urgency dots ambiguous (priority? unread?); no
  affordances (hover highlight, snooze/mute/done); header "Needs you 6" should be a
  title + count badge.
- **Product:** useful for engineers/PMs as a glanceable queue; **summon-on-demand =
  fine; persistent float = "a guilt-list / visual debt" without snooze/mute/clear.**

### Disposition (invariant 2 + 8)
- **ACCEPT.** The function landed; the first-party-feel did not. Per invariant 2 the
  blind read diverges from the claim → **criterion #1 (native-overlay fidelity)
  caps at ~2–3** (it's "competent third-party", i.e. better than a web rectangle but
  not first-party). #10 similarly gated.
- **Behavioral change (iter 9, within the 3-iter window):** a native-feel pass —
  (a) materials: try `.menu`/`.popover`/`.sidebar` vibrancy or proper blur so it
  reads "alive"; (b) row anatomy: leading SF Symbol per reason (arrow.triangle for
  review, at for mention, person for assign), tighter macOS row metrics; (c) header
  as a title + count badge; (d) dot semantics legend or replace with SF Symbols;
  (e) reconsider color tokens vs Apple system colors. AND reinforce the
  **summon-on-demand** interaction (collapsed by default; not a persistent guilt
  list) + plan snooze/mute as future affordances.

PAL continuation_id: `8a01a290-34a7-4308-85c9-bb3be9c2cb46`.

---

## Consult 003 — iter 10 — second blind VISUAL read (post native-feel pass)

- **Channel:** PAL → `gpt-5.2`, fresh blind session. **Artifact:**
  `loop/evidence/hover-expanded-normal-desktop-10.png` (refined island: SF Symbols +
  count badge + popover material + hairline edge + restrained type).

### Verdict
- **Function — still MATCHES** ("items that need you — mentions/reviews/assignments,
  triage, click-through").
- **Native-feel — improved in clarity but STILL "competent third-party", not
  first-party.** Remaining levers, in order: (1) **material** — "flat dark slab, not
  macOS popover vibrancy/material separation" (the single biggest change); (2)
  typography "web-app weight/scale" → tighter SF metrics; (3) colored icons "too
  loud" → use color more sparingly; (4) badge "oversized/stuck-on"; (5) no row
  affordances (hover/selection/separators) → "feels like a static card, not a native
  list".

### Disposition (invariant 2 + 8)
- **Acted on the cheap high-leverage levers** this pass: material `.hudWindow` →
  `.popover` + a 0.5pt hairline border; title weight `.semibold` → `.medium`; the
  badge pinned tight to its number. Visually improved (crisp edge, lighter type).
- **ACCEPT "competent third-party" as a PASSING table-stakes grade** and STOP here.
  Per consult-001, native fidelity is *table-stakes, not the moat* — chasing
  first-party perfection on a non-moat axis is over-optimization. **#1 (native
  fidelity) settles at ~3** (competent, evidenced; not first-party). The remaining
  levers (true list affordances: hover/selection/separators) are coupled to the
  **interaction model** (summon + click-to-inspect), so they land there, not in
  another static-polish pass.
- **Pivot (imbalance-seeking):** the most under-developed axis is no longer
  native-feel — it's the **live integration** (the app renders a fixture, but
  doesn't poll live / auto-refresh). That's iter 11.

PAL continuation_id: `4ff1ba31-cc89-40af-a525-b483c14514ce`.

---

## Consult 004 — iter 14 — creative-direction cadence (whole product, post-MVP)

- **Channel:** PAL → `gpt-5.2` (blind adversarial; gemini-2.5-pro was tried first but
  its safety filter blocked). Packet: original intent + signal/trust thesis, the live
  behavior (50→3, classifier rules, collapsed pill + summon + open-on-GitHub), the
  island screenshot, constraints; the 5 invariant-8 questions. No scores/plan/rationale.

### Verdict (the sharp parts)
1. **Kill "video-game HUD" as POSITIONING** (cosplay; the wedge is *attention
   arbitration* — "do I need to act?" — not UI novelty). Demote "heavy GitHub users"
   → the real segment is people **accountable for response time** (reviewers, leads,
   on-call). Challenge: "action-required is reliably inferable from threads" —
   threads are lossy; a week of **false NEGATIVES kills trust**.
2. **Seductive-but-hollow:** the **CALM pill as hero** ("users don't care about calm,
   they care about MISSES — first time it says CALM but they missed a review 3h ago,
   it's dead"); the **50→3 magic trick** ("compression isn't the job, correct
   *prioritization* is — users tolerate 10 if ordering is right + they never miss the
   one that mattered"); ambient without workflow closure (click→browser friction).
3. **6-mo-embarrassing:** a menu-bar notifications list (every dev tool ends here);
   icon+count+dark-glass (aesthetic sugar high); **"poll every 60s" as a feature** (a
   confession of constraints — don't center it).
4. **Over-optimizing COMPRESSION + QUIETNESS.** Quiet ≠ goal; **correct urgency** is.
   50→3 is gameable (filter harder → 1). Measure instead: **false-NEGATIVE rate on
   "needs me now"** (one miss/week = toast); **time-to-awareness vs baseline**; **user
   overrides** (mark urgent/noise). The self-last-commenter demotion is a landmine —
   measure it, don't assume.
5. **Cheapest invalidator — the "trust kill test":** show TWO numbers (action-required
   + **hidden-by-filter, with a one-click REVEAL SUPPRESSED**); 7 days, real
   reviewers; daily Q: "did githud miss anything that needed you within 2h?" If users
   regularly find urgent things in "suppressed," the moat is fake. Even cheaper: log
   suppressed locally + a daily "here's what githud hid" digest.

### Disposition (invariant 8 — act within 3 iters)
Largely **ACCEPT** — the misses-over-compression reframe is correct and important.
- **REFRAME the optimization target** (INTENT + RUBRIC #11): the existential metric is
  **recall / false-negative rate on "needs-me-now"**, NOT compression. "50→3" demoted
  from a headline to a side effect. Correct *ordering* matters more than fewer items.
- **BUILD the cheapest invalidator now (iter 14):** expose the SUPPRESSED bucket +
  a reveal affordance (`probe --show-suppressed`; later an in-island "N suppressed →
  reveal") so the user can catch misses. This IS the trust experiment, sharpened.
- **Positioning:** kill "video-game HUD" as the pitch (keep it as the form); lead with
  "does GitHub need me right now." Don't center "60s poll" or "calm".
- **NOTE (not yet acted):** the self-last-commenter demotion gets a miss-safety review
  via the reveal-suppressed data, not a blind code change.
- Open Qs to carry to the user-look gate: false-neg vs false-pos stance; are
  notifications already in Slack/email; which moment to win (deep work / EOD / always-on).

PAL continuation_id: `4cdb7c48-bf33-4b83-81c3-e74601da798a`.

---

## Consult 005 — iter 24 — adversarial CODE-CORRECTNESS review (moat path)

- **Channel:** PAL → `gpt-5.2`, with the 4 moat-critical files attached
  (SignalClassifier, SurfacePreferences, RadarPipeline, PollScheduler). Asked for
  REAL defects (correctness / concurrency / robustness / silent-drop), not style.
  The invariant-8 adversarial spirit applied to CODE, after 23 fast iterations.

### Findings + disposition
- **FIXED (trust-critical, 1.1/4.1):** a NOVEL GitHub reason was double-dropped —
  `classify` defaults unknown → fyi AND `surfaces()` gated it out (not in
  enabledReasons) → a silent MISS if GitHub adds an action-worthy reason. Fix:
  `surfaces()` now surfaces unknown reasons by default (never silently drop a novel
  one; the user can disable later). Tested (novel reason surfaces even with an empty
  enabled set; a disabled KNOWN reason stays hidden).
- **FIXED (robustness, 3.2):** `RadarPipeline.resolveSelfIfNeeded` set
  `selfResolved=true` even on a /user TIMEOUT → self-activity demotion permanently
  disabled → avoidable false positives. Fix: mark resolved only on success (retry
  otherwise); `selfLogin` now only written on the queue.
- **CONFIRMED SAFE (2.3):** the blocking-semaphore pattern is not a deadlock risk —
  URLSession dataTask completions fire on the session's background queue, never the
  poll queue. Documented in a code comment.
- **ACKNOWLEDGED, low-yield:** `running` Bool read off-queue (benign — at worst a
  ghost poll after stop, harmless at 60s cadence); `updatedAt` lexical sort (safe —
  GitHub returns normalized ISO8601 `…Z`). Noted, not changed.
- **REJECTED nothing fabricated** — the reviewer explicitly confirmed the
  radar/suppressed partition + bot/self demotion are sound.

105 tests; live probe unregressed. PAL continuation_id: `0e4148f1-846b-4447-8ee4-07fbef903a6f`.

---

## Consult 008 — iter 30 — color doctrine (GPT Pro extended-pro)

- **Channel:** `/agentify` → ChatGPT **Pro extended thinking** (modeIntent extended-pro,
  9m56s), context-packed Theme.swift + PullRequestPulse.swift + SignalClassifier.swift +
  INTENT.md. The MCP transport timed out (~10.4m ceiling) but the tab finished generating;
  read from the live page. Prompt (neutral, hypothesis-framed): land a 2–4 principle color
  doctrine + resolve four open threads (radar mono vs heat; green=alive vs ready; yellow's
  fate; emergency-flag mono-only vs mono+critical) across 9 themes + one a11y rule, and name
  the strongest counterargument to its own doctrine.

### The doctrine (verbatim spine)
> **Shape says *what*; order says *priority*; color says *what changes the next move*.**
> githud is ink by default. Color is spent only on a changed next-move — `danger`
> (intervene/contain), `success` (action newly unlocked), `caution` (the *reading* is
> degraded) — with critical facts propagated to the collapsed island, and no meaning ever
> carried by hue alone.

Four principles: (1) shape=what / order=priority / color=changed-next-move; (2) **normal
operation is quiet** — open/active/waiting/pending are normal, neither warnings nor
successes (don't reassure with green or agitate with yellow); (3) **accent is chrome, not
status** (the count badge never means ready/blocked/urgent); (4) **smallest sufficient
surface, except critical facts cross disclosure boundaries** (color the glyph/count, never
the row/panel bg; but a hidden critical fact must reach the collapsed pill).

### Resolutions (the four open threads)
- **Radar heat → mono + one critical (Option C), upgraded.** Drop the 4-band urgency heat
  (redundant with filter+sort). Keep ONE reserved color: `security_alert` → `danger`. **New
  catch:** make critical a separate *sort* dimension (critical-first), else `review_requested`
  (95) strands `security_alert` (92)'s red glyph below a calm row. Kill `radarUrgencyColor(_
  urgency:)` — "a color fn that takes an urgency number structurally invites the heat scale
  back." Ordinary glyph = `inkSecondary`.
- **Green = ready, NOT alive.** Every PR in the lane is already open (the query selects open),
  so green-for-alive encodes an invariant — the same mistake as urgency-heat after sort. It
  also erases the one positive transition worth signaling: *"I could only wait; now I can
  merge."* That earns `success`. (Ready with no checks still = green; subtitle says "no
  checks" for the honesty contract.)
- **Yellow removed from all current states.** `waiting` is ordinary in-flight → `inkSecondary`
  (outline clock). `caution` reserved for **degraded reading confidence** (stale data /
  poll-fail / mergeability-unknown-past-transient) on the H2 header/freshness label, not
  per-row. `warn` deprecated (no job).
- **A11y rule:** *replace every semantic color with the same gray — the complete meaning must
  still survive.* Geist Mono is the proof case (shield/triangle/check/clock/pencil shapes +
  VoiceOver). 9 themes map *roles* (danger may be red/coral/pink/white), never literal hue.

### Strongest counterargument (GPT's own)
Redundant color *can* be a pre-attentive scan-accelerator when H1 runs past one viewport or
users enter mid-list (heat maps sometimes beat ordered lists). But that justifies *at most*
one critical class + one emphasized first row — never a 4-band ladder on a calm 3–11-item
radar. **Watch:** time-to-first-correct-row under dogfooding; if it bites, add ONE emphasis
tier, not the heat map back.

### Behavioral change forced (this is what makes the consult "count")
Built iter 30: `SignalClassifier.criticalReasons` + `isCritical` + **critical-first sort**;
`RadarRow.isCritical`; `Theme.radarGlyphColor(critical:)` replaces `radarUrgencyColor`;
`pulseGlyph` `waiting`→ink, `draft`→inkTertiary (yellow gone); pill critical-aware. The plan
`docs/plans/2026-06-20-001` graduated active→completed with these amendments. New pressure
row `color-doctrine`. 254 checks; visual-proven (300–303); blind read = lone red security
shield on top + zero yellow.
