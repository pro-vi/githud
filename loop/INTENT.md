# githud — INTENT (live target hypotheses)

> Invariant 3: the target is provisional and will reframe 2–4 times. Maintain ≥3
> live hypotheses. Re-review every ~10 iterations, on every user reframe, and
> before any major rubric revision. No rubric criterion may exist that doesn't map
> to a live hypothesis here.

Original intent (verbatim seed): *"a mac os native … hud display on screen overlay
that acts like a video game hud but for people who use github a lot … capture any
inbox or feed items from github … user can choose what they care about … latest
comment, pull request on their PR, new issues, even stars and forks, review
requests … minimal but elegant and mac native feeling. on hover it will expand and
on click there can be an inspector panel … Arc browser has a git live folder but
this is 5x better."*

> **Reframe log.**
> - **iter 1 (consult 001, gpt-5.2 blind adversarial):** the moat is *signal quality
>   + trust*, not the glass. H1's core sharpened from "you have notifications" →
>   **"do I need to ACT?"**. H2 demoted to a skin (presence signals aren't reliably
>   available from the Notifications spine). H3 confirmed kill. Hover-as-primary
>   flagged as a trap. North-star + trust experiment added below. Scores: none
>   existed (v0.1 ratified, nothing scored) → quarantine is free; rubric → v0.2.
> - **iter 14 (consult 004, gpt-5.2 blind adversarial, post-MVP):** the existential
>   metric is **recall / false-NEGATIVE rate** ("never miss the one that mattered"),
>   NOT compression. **"50→3" is demoted from a headline to a side effect** — quiet ≠
>   the goal, *correct urgency* is. The "calm pill as hero" and "60s poll" are
>   seductive-but-hollow framings. Kill "video-game HUD" as the *pitch* (keep it as
>   the form); lead with "does GitHub need me right now." Operationalized: a
>   **reveal-suppressed** audit (the trust test) — the user inspects the hidden set
>   for misses. RUBRIC #11 reframed accordingly (no version bump: sharpens the same
>   spine criterion, doesn't quarantine — there are still no formal scores).
> - **iter 25 (user-directed build):** after the user confirmed time-to-awareness =
>   **ambient** (no push) and asked what the pulse is, they chose to **build H2**. H2
>   is **PROMOTED from demoted-skin → a built, live-proven second lane** — but built
>   on exactly the part the iter-1 demotion said *was* trustworthy: standing PR state
>   (CI rollup / review decision / mergeability), via GraphQL, with an **honesty
>   contract** (null/UNKNOWN never render green/ready). The demotion's warning still
>   binds: no "N people looking" (not a real signal), no faked realtime ("as of last
>   poll"). H2 ≠ replacement for H1 — a *second question* ("how's my work doing?")
>   beside H1's ("does GitHub need me?"). New pressure `pulse-honesty` enforces it.
> - **iter 26 (3-model second-opinion → taxonomy hardening):** GPT-5.2 + Gemini 3.1
>   Pro + Grok 4.3 reviewed both lanes; user approved a batch + two product calls.
>   H1: `security_alert`↑, novel reasons un-buried, `invitation` added, **policy-b** —
>   a direct `@you` mention is never bot-demoted (a bot alerting you by name is signal,
>   not noise; deliberately trades false-alarm budget for never-miss — *measured* free,
>   0 of 11 radar items are automation). H2: closed a CI honesty hole (drift →
>   `pending`, never false-green); **draft PRs → own default-off subsection** grouped by
>   the `isDraft` fact (lattice untouched). The moat stayed **trust** throughout —
>   H1 never-miss, H2 never-fabricate. Enumeration-awareness is now a standing principle.
> - **iter 27 (State-vs-Event — a 3-model second-opinion REJECTED a refinement):**
>   investigated using H2's pulse STATE to refine H1's `author` urgency (incl. demoting
>   `author` on a draft PR). The trio (GPT-5.2 + Gemini 3.1 Pro + Grok 4.3) unanimously
>   rejected it as a MISS RISK + premature. The keeper principle: **H1 = Actor Events
>   ("a human just did something — look") ; H2 = System State ("here's the status").
>   They are ORTHOGONAL axes — overlap is dual-axis visibility, NOT redundancy. Never
>   use State to mask an Event** (a `ready` PR can still get a comment that needs you;
>   a human comment on YOUR draft is high-signal even though the draft is hidden from the
>   status dashboard). `author` also covers issues + threads H2 can't model. Decision:
>   **leave the `author` tier as-is.** The radar surfaces events correctly; quieting it
>   there = missing events. (A presentation-only "see Your PRs" cross-link is the only
>   surviving idea — deferred, low priority, needs a never-miss fallback.)
> - **iter 28 (THEME SYSTEM — native-feel as a product surface):** a user-directed turn
>   that started as a monotone-icon preference and reframed into a **runtime theme system**
>   (5 themes: Color default · Geist Mono · GitHub · Dracula · Nord). This advances the
>   long-stuck **#1 native-feel** axis (settled at "competent table-stakes" since iter 10) —
>   not as the moat (still signal/trust) but as the *form* the moat wears. Themes are pure
>   PRESENTATION: a `Theme` token bundle, swapped on the existing render() rebuild; the
>   classifier/pulse/signal logic is untouched, and the default Color theme reproduces the
>   validated look exactly. Constraint learned: exact brand palettes require **solid**
>   surfaces (vibrancy ties color to the desktop). Monotone themes are also **a11y-positive**
>   (state via shape/weight, not hue). The "video-game HUD" form now has a wardrobe; the
>   signal underneath is unchanged.
> - **iter 30 (COLOR DOCTRINE — GPT Pro, consult 008):** a `/agentify` extended-pro consult
>   ratified a coherent color theory and the loop *applied* it the same iteration. **The
>   doctrine in a sentence:** *shape says what, order says priority, color says what changes
>   the next move — githud is ink by default; color is spent only on a changed next-move
>   (`danger`=intervene, `success`=action unlocked, `caution`=the reading is degraded), with
>   critical facts crossing to the collapsed pill and no meaning ever carried by hue alone.*
>   This is the **visual expression of the same trust moat**: just as the classifier spends
>   *attention* only on action-required signal, the palette spends *color* only on
>   decision-changing info. Concretely it (a) dropped H1's urgency heat scale → mono glyphs +
>   ONE reserved critical (`security_alert`→danger), and caught a live bug — critical must be
>   a separate **sort** dimension (else review_requested=95 strands security_alert=92's red
>   glyph below a calm row); (b) settled **green = `ready` (merge unlocked), never "alive"**
>   (open PRs are open by query — green-for-alive encodes an invariant, the same error as
>   urgency-heat-after-sort); (c) **removed yellow** from every state (`waiting`=ordinary
>   in-flight→ink; `caution` reserved for degraded *reading* confidence/freshness; `warn`
>   deprecated). One a11y law: *swap every semantic color for the same gray and the meaning
>   must survive* (shape + VoiceOver carry it; Geist Mono is the proof case). Watch (GPT's own
>   counter): if H1 ever runs long enough that mono slows time-to-first-correct-row, add ONE
>   emphasis tier — never the heat ladder back.

---

## H1 — **The action radar: "do I need to act?"** *(PROMOTED — core)*

**Reading.** Not an inbox list — an *action radar*. A menu-bar agent + tiny glass
island whose entire job is to answer, at a glance, **"does GitHub need me right
now?"** It surfaces only **action-required** threads — @mention, review-requested,
a new comment on *your* PR/issue, an assignment — classified and ranked by urgency,
noise ruthlessly suppressed. Summon → expanded list (repo/actor/title/age); click →
inspector with the latest-comment excerpt + Open-on-GitHub. The HUD is the wrapper;
the **signal/trust model is the product.**

- **Supporting evidence.** Matches the original "does GitHub need me" intent and the
  GPT-Pro MVP cut; the Notifications API is built for exactly this inbox/triage
  poll; consult 001 converged here independently and called #4 (signal relevance)
  the *only* existential criterion.
- **Artifact implications.** REST `/notifications` spine, classic PAT, a
  **classification layer** (action-required vs FYI vs bot-noise) over the thread
  model, urgency ranking, an inspector. The classifier is fixture-testable headless
  (no PAT needed to *build/test*, only to fetch live data).
- **Good output makes the user** *trust a 2-second glance instead of opening a
  browser tab* — and be right enough that they stop reflex-checking github.com.
- **Failure smells.** Becomes an activity feed (shows comments, not *urgency*);
  false alarms (LGTM/nit/bot pinged as action-required) erode trust → users ignore
  it → it's worse than nothing. Misses (had to act, no surfacing) are equally fatal.
- **Invalidating evidence.** The trust experiment (below) shows users "still check
  GitHub anyway because I don't trust it"; or false-alarm rate stays > budget.
- **Cheap probe.** See **the trust experiment** below.

## H2 — Ambient PR pulse: "how's my work doing?" *(BUILT — second lane, iter 25)*

**Reading.** A glanceable, always-on read on the state of *your open PRs* — CI rollup
(passing/failing/running/no-checks), review decision (approved/changes/required), and
mergeability — rolled up to a single per-PR verdict (**blocked > ready > waiting >
draft**). A "Your PRs" lane in the expanded island; a caught-up pill **gauge** (worst
state + count) when the H1 inbox is clear, so the island stays a *living gauge*. The
island now answers **two** questions: H1 "does GitHub need me?" + H2 "how's my work
doing?".

- **Built on the trustworthy core (the iter-1 demotion's "what survives").** One
  GraphQL query (`viewer.pullRequests`) supplies *real* CI/review/merge state — the
  part consult 001 said was legitimate. The faked parts stay cut: **no "N people
  looking"** (not a real GitHub signal), **no faked realtime** (polled; "as of last
  poll", redraw on change only — no decorative motion).
- **Honesty contract (pressure `pulse-honesty`, the moat).** null `statusCheckRollup`
  → "no checks" (never green); UNKNOWN/null `mergeable` → "checking…" (never ready);
  null `reviewDecision` → "no review required" (not approved); `.ready` requires
  `mergeable` explicitly. A wrong/laggy pulse erodes trust exactly like a missed
  mention. The subtitle always **names** the failing/conflicts/unknown member, so the
  rollup glyph is never opaque.
- **Artifact implications.** `PullRequestPulse` + lattice (GithudCore),
  `GitHubClient.fetchOpenPullRequests` (GraphQL, separate 5000-pt bucket — REST
  304-discipline untouched), pulse fetched every poll tick (PR state changes without a
  notification), non-fatal (keeps last good).
- **Live-proven (iter 25).** `githud probe` → 16 open PRs classified
  (blocked/ready/waiting/draft) over GraphQL on the real PAT; both lanes render
  (manifest 520×457, pixel_live, idle 0.1, focus unchanged); evidence redacted.
- **Invalidating evidence (still binds).** Any ambient motion not mapped to a real
  change; any pulse state shown that the data can't back; the lane making the island
  feel busy rather than calm. **Open user call:** H1-primary vs H2-primary emphasis.

## H3 — Full GitHub client in an overlay *(KILLED — guardrail only)*

**Reading.** Reply, request-changes, merge, triage — all from the HUD.

- **Killed (GPT-Pro + consult 001 agree).** Mailbox→cockpit category error: trades
  calm-glance for a cramped mini-IDE, explodes auth to write scope, breaks focus +
  attention non-theft, and still loses to the browser on speed/context/trust. Kept
  only as a **guardrail**: any iteration where adding an in-HUD action measurably
  hurts native-feel / focus / attention / glance-ability confirms the trap → hold
  the line at **Open-on-GitHub**.
- **Cheap probe.** Add one inline action (e.g. "mark read"); if the island feels
  heavier, stop at Open-on-GitHub.

---

## North-star metric (consult 001)

**"# of useless GitHub checks the HUD prevented per day."** If that isn't clearly
> 0 for real users, the rubric is miscalibrated. Operationalized via the trust
experiment's two logs:
- **False alarms** — surfaced as action-required, but no action was needed.
- **Misses** — had to act, but it was not surfaced.

## The trust experiment *(pre-registered cheap invalidation probe; gated on PAT)*

The single cheapest test that could invalidate the whole direction. Build the
*signal model* first; prove it earns trust *before* polishing the overlay.

- **Setup.** A heavy-GitHub user (Provi, then 8–12 if it survives), real
  notifications, the intended filter rules, **≤5 surfaced items/day.** Each item
  carries exactly what the inspector would (repo, actor, title, age, last-comment
  excerpt, Open link).
- **Logs.** Daily false-alarms + misses (the north-star inputs).
- **Fail condition (kills the direction):** "I still check GitHub anyway because I
  don't trust it," or false-alarm rate persistently > **1–2/day** (the set budget).
- **Status.** Harness buildable now on **fixtures** (headless); runs on **real
  data** when `github_classic_pat_ready` flips. Build order: iter 2 ships the
  fixture-driven classifier; the live run waits on the gate.

---

**Current lean (post-iter-25):** **H1 (the action radar) is the validated core** —
its center of gravity is the signal/trust classifier, and the user confirmed it
"holds". **H2 (the ambient PR pulse) is now BUILT as a second lane** (user-directed),
on the trustworthy standing-state signals only, under the `pulse-honesty` contract.
Both share ONE moat: **trust** — H1 never misses/false-alarms; H2 never fabricates a
state. H3 is a guardrail (Open-on-GitHub; the pulse is read-only too). Stars/forks/FYI
stay **out** of both lanes. Open user call: which lane leads the collapsed glance. The
first existential question is still trust, not pixels — and as of iter 30 the *palette*
serves that moat too: the **color doctrine** (consult 008) spends color only on
decision-changing info (ink by default; `danger`/`success`/`caution` only), so the glass
never cries wolf in hue any more than the classifier does in attention.
