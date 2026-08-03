# githud — RUBRIC

```yaml
rubric_version: v0.2
score_comparable_with: []   # v0.1 quarantined (consult-001 reframe); v0.1 had no scores → free
score_lock: no              # ratified — see Ratification + Revision v0.2
ratified: yes
ratified_at: "2026-06-15 (v0.1 iter 0); 2026-06-16 (v0.2 iter 1, consult-driven)"
```

> **v0.2 — consult-driven reframe (iter 1).** Invariant 4: a reframe quarantines old
> scores and bumps the version. v0.1 had no scores, so quarantine is free. The
> moat is **signal quality + trust, not the glass**: native fidelity is reweighted
> to *table-stakes*, signal relevance + a new **signal-trust** criterion become the
> spine, and a new **attention-non-theft** criterion captures the real enemy
> (motion/novelty/persistent presence), distinct from focus non-theft. No criterion
> may exist that does not map to a live INTENT hypothesis.
>
> **Cap status (updated iter 3, 2026-06-16): `screen_recording_permission` GRANTED.**
> The visual hard-cap of 2 is **lifted** — a visual score >2 now requires a
> `visual-proof.sh` manifest with `pixel_live: true` (proven working:
> `loop/evidence/idle-normal-desktop-3.manifest.json`). Audience criteria (#1, #10)
> still cap at 3 without a blind comprehension read. `github_classic_pat_ready` is
> also GRANTED, so #4/#11's real-data range is now reachable via the live trust
> experiment. (Scores >2 still demand the cited evidence — the cap lift removes the
> *impossibility*, not the *evidence requirement*.)
>
> **Live evidence (iter 4):** #8 (polling discipline) **PROVEN on live data** —
> `GET /notifications` 200 → conditional 304, X-Poll-Interval=60 honored, no rate
> cost (`loop/evidence/live-probe-4.json`). #9 (credential safety) — token read via
> Security.framework / `security` CLI, only ever in the Authorization header, logged
> only as `ghp_•(40)`; unit-asserted that redaction omits the secret. #4/#11 have a
> first live data point (14/50 action-required) but real-data **precision is
> UNVERIFIED** — 13 `author` threads need enrichment to filter bot/CI (iter 5).
>
> **Live evidence (iter 6):** #4/#11 now have **strong** real-data evidence — with
> enrichment (`repo` scope) + self-activity demotion the radar cuts **50 raw → 13
> naive → 3 genuinely action-required** (`loop/evidence/live-probe-6.json`): bot/CI,
> firehose (`subscribed`/`ci_activity`/`state_change`), and your-own-latest-comment
> all suppressed; `review_requested` not missed. STILL not formally scored: the 3
> survivors aren't user-validated, #11's top range needs the **multi-day trust
> experiment** (user-logged false-alarm/miss ≤ 1–2/day), and the radar isn't yet
> wired into the island — score the integrated product, not the CLI probe.
>
> **Visual evidence (iter 8):** the populated island is now real
> (`hover-expanded-normal-desktop-8.manifest.json`: pixel_live=true, expanded
> 520×173, frontmost_unchanged). First blind comprehension read (consult 002): the
> FUNCTION landed (read as a glanceable dev-action triage) but **native-feel
> DIVERGED — "competent third-party, not first-party"** → **#1 (native-overlay
> fidelity) caps at ~2–3** until the iter-9 native-feel pass + a re-read that no
> longer says third-party. #2 (frontmost_unchanged✓) + #7 (static, no timers) have
> partial structural evidence; their >2 still needs the typing-while-expanding /
> idle-CPU recordings.
>
> **Visual evidence (iter 10):** after a native-feel pass (SF Symbols, count badge,
> `.popover` material + hairline edge, restrained type) the **second** blind read
> (consult 003) still reads "competent third-party, not first-party" → **#1
> (native-overlay fidelity) settles at ~3** — a *passing table-stakes* grade
> (consult-001: fidelity is table-stakes, not the moat). The remaining first-party
> levers (true list affordances: hover/selection/separators) are coupled to the
> interaction model (#5/#6), not another static-polish pass.

## Ratification (iter 0)

The seeded draft met all four `score_lock` exit conditions, verified this pass:

1. **8–12 criteria with 0/2/5 anchors + per-criterion evidence rules** — 10 criteria
   below; each has concrete 0/2/5 anchors (named visual defects, not vibes) and a
   typed evidence rule (screenshot/recording/manifest, network log, `top` reading,
   code audit, or inbox-diff). Verified concrete.
2. **Cheap dignity test written** — below; ratified usable (the 2-second-glance test).
3. **Audience-comprehension probe defined** — below; the blind-read packet is
   concrete (screenshot + 5s capture, no rubric/scores). It is *defined*, not yet
   *runnable* (needs `screen_recording_permission`).
4. **INTENT holds live hypotheses** — H1/H2/H3 in `INTENT.md`.

**INTENT mapping confirmed.** Every criterion maps to H1 (inbox) and/or H2
(ambient). No criterion maps to H3 — correct: H3 (full-client-in-overlay) is a
*guardrail*, not a target. H3 is held by criteria 2 (focus non-theft), 6 (inspector
anchors at *Open-on-GitHub*, not reply-from-HUD), 7 (idle calm), 10 (glance-ability):
any feature that bloats the HUD toward a mini-IDE costs those scores. No new
criterion needed for H3.

**Cap map confirmed (invariant 2).** Visual/behavioral criteria **1–3, 5–7, 10**
cap at 2 until `screen_recording_permission` (no pixel citation possible). Audience
criteria **1, 10** additionally cap at 3 without a blind comprehension read.
Criteria **4, 8, 9** are evidenceable now from logs/code (inbox-diff, network log,
source audit) — not screen-gated. Raising the bar is a **new `rubric_version`**, not
a stricter restatement of these anchors (invariant 4).

## Revision v0.2 (iter 1 — consult 001 reframe)

External tier-1 review (blind adversarial, gpt-5.2) found v0.1 over-weighted
*native fidelity* (table-stakes, not the moat) and under-weighted the existential
risk: **can the thing be trusted to answer "does GitHub need me right now?"**
Changes:

- **Spine = #4 signal relevance + #11 signal trust** (new). These are the only
  existential criteria; everything else is table-stakes *after* them. Both are
  evidenceable **now from fixtures** (classifier precision/recall on labeled
  notification threads) — no screen-rec needed — and fully from real data when the
  PAT gate flips (the trust experiment, see INTENT).
- **#12 attention non-theft** (new): focus-non-theft (#2, "don't activate") is
  necessary but insufficient — a non-activating panel can still be an *attention
  vampire*. #12 scores restraint on motion/novelty/persistent presence.
- **#5 hover-expand reframed** around *accidental-trigger resistance*: the cursor
  passes the top edge constantly, so whole-top-edge hover is a trap. The summon
  affordance must not fire on incidental passes.
- **#1/#3/#6 reweighted to table-stakes** (still required; an ugly or mispositioned
  always-on app gets killed — but they are not the differentiator).
- **Weight classes:** spine (4, 11) ≫ behavioral hygiene (2, 7, 12) ≈ infra
  (8, 9) ≫ table-stakes presentation (1, 3, 5, 6) · audience (10) reads the whole.

## Cheap dignity test (write/ratify in ramp)

> Before writing any total: *"If a Mac-power-user friend glanced at this island on
> my screen for two seconds, would it read as a real first-party macOS app — or
> as an obvious side-project rectangle?"* If the latter, the visual criteria cannot
> exceed 2 regardless of self-assessment.

## Audience-comprehension probe (define in ramp)

> Blind-read packet (no rubric, no scores): a screenshot + a 5s screen capture of
> the island idle → a notification arriving → hover-expand → click-inspect. Ask a
> fresh model-family session: *"what is this app, what does it do, and does it feel
> native?"* Compare to each artifact's `comprehensionClaim`.

## Criteria (0 / 2 / 5 anchors; evidence rule per row)

| # | Criterion | 0 | 2 | 5 | Evidence rule | INTENT |
|---|---|---|---|---|---|---|
| 1 | **Native-overlay fidelity** | web/synthetic rectangle | plausible but off (flat fill, wrong radius/shadow) | indistinguishable from a first-party macOS HUD; AppKit vibrancy, correct material/radius/shadow | screenshot + blind read | H1,H2 |
| 2 | **Focus non-theft** | HUD steals focus / interrupts typing | occasional focus flicker | zero focus theft across full-screen + Stage Manager + multi-monitor | screen recording of typing in another app while HUD active/expanding | H1,H2 |
| 3 | **Spaces / full-screen behavior** | hidden behind full-screen apps | shows but mispositioned/clipped | correct on all Spaces, full-screen, notch, multi-monitor | screenshots over full-screen Safari + Terminal | H1,H2 |
| 4 | **Signal relevance** *(spine)* | raw firehose | unfiltered notifications dump | only **action-required** items (mention/review-req/your-PR comments/assign), correctly classified & urgency-ranked, FYI/bot noise suppressed | classifier output vs labeled fixture; HUD items vs GitHub inbox diff for a real account | H1 |
| 5 | **Summon / expand interaction** | no expand | fires on incidental top-edge passes; janky/laggy | deliberate summon — **no accidental expansion** when the cursor merely passes the top edge; fluid spring, correct hit regions, clean collapse | screen recording of cursor crossing the top edge without triggering | H1 |
| 6 | **Inspector depth** | none | opens but thin | rich, fast, keyboard-navigable; latest-comment excerpt + Open-on-GitHub | screenshot + interaction recording | H1 |
| 7 | **Idle calm / footprint** | busy/animating/high CPU | occasional churn | ~0% CPU idle, network-sleep, no distracting motion | top / Activity Monitor reading + timer grep | H1,H2 |
| 8 | **Polling discipline** | naive poll loop | polls but ignores headers | Last-Modified/ETag + X-Poll-Interval + jitter; 304s don't burn rate limit | network log showing 304 + interval adherence | H1 |
| 9 | **Credential safety** | token in plaintext/logs | obscured but on disk | Keychain-only, never logged, never written plaintext | code audit + grep for token in logs/source | H1 |
| 10 | **Glance-ability ("5x better than Arc")** | ignorable/annoying | useful but noisy | ambient, trustworthy, leave-it-running-all-day; a glance answers "does GitHub need me?" | blind comprehension read + INTENT re-review | H1,H2 |
| 11 | **Signal trust / correctness** *(spine)* | **MISSES things you needed** (false negatives) — or shows activity-not-urgency | occasional miss OR some false alarms; trust wobbles | **ZERO misses on "needs-me-now" (recall≈1)** is the bar — earns "I stop reflex-checking github.com"; false-alarm ≤ **1–2/day** secondary; correct *ordering* > fewer items | reveal-suppressed audit (no urgent item hidden) over real use + classifier recall on a labeled fixture | H1 |
| 12 | **Attention non-theft** | autonomous motion/novelty; persistent visual pull | occasional unsolicited motion | still by default; motion **only** on a real action-required change; no decorative pulse; doesn't recruit the eye at idle | grep (no idle timers/animation) + screen recording (motion maps 1:1 to actionable change) | H1,H2 |

> **Visual evidence = a `scripts/visual-proof.sh` native manifest** (see PROMPT
> "Visual proof (native)") — `screencapture` + `CGWindowListCopyWindowInfo`
> window/bounds/focus/pixel/CPU checks, content-addressed + provenance-stamped — not
> a bare screenshot. `/visual-proof` (browser-only) does not apply.
>
> Criteria **1, 2, 3, 5, 6, 7, 10, 12** are **visual/behavioral**. The hard-cap of
> 2 is **lifted** (screen-rec granted iter 3) — a score >2 now requires a
> `visual-proof.sh` manifest with `pixel_live: true` (+ the criterion-specific
> condition: #2 needs the typing-while-expanding recording; #3 the over-fullscreen /
> multi-monitor manifests; #5 the cursor-crossing recording; #12 the motion-maps-to-
> change recording). Criteria **4, 8, 9, 11** are evidenceable from logs / code /
> **fixtures**; #11's top range needs the live trust experiment (now PAT-unblocked).
> Audience criteria (#1, #10) still cap at 3 without a blind comprehension read.
> Raise the ceiling as a **new version** (not a stricter restatement) when a
> milestone is hit faster than expected (invariant 4).
