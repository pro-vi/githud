---
title: Elegance · Native · Reactive · OSS — phased roadmap
type: roadmap
status: historical
date: 2026-07-02
origin: ultracode 7-scout audit (architecture / UX / native-feel / reactivity / OSS / doctrine / market) + first-hand code read; user-directed phasing with a Claude Design exploration phase
---

# githud — from competent to elegant

**Verdict the plan is built on:** githud is doctrinally excellent and mechanically
correct (the non-key overlay stack, the honesty-in-the-type-system pulse lattice,
the Core/App test split) — but *the glass hasn't caught up to the doctrine*. The
trust moat leaks in the presentation layer (frozen ages, a PR lane that can go
silently stale, a blank cold launch), the signature Dynamic-Island form has zero
motion, first-run dead-ends at a Terminal command, and the repo is not legally
forkable. Every row below works **with** the ratified doctrine (INTENT.md), not
against it; the few that brush a doctrine line are marked ⛔ USER GATE.

## How this plan runs (loopgen integration)

- This document is the **queue artifact** (`/loopgen` primitive
  *queue-as-second-artifact*) for this body of work: each checkbox is a row;
  provenance for every row is the 2026-07-02 scout audit unless noted; the
  reopen condition for any checked row is a regression against its stated proof.
- Two execution modes:
  1. **Interactive** — work phases in order in normal sessions; check boxes here.
  2. **Loop** — invoke `/loopgen` to compose a **goal-shaped loop** whose
     acceptance inventory is this plan's checklists (halt: all boxes checked or
     a ⛔ gate reached). Phases 1, 3, 4, 5 are loop-friendly (finite, provable);
     Phase 2 is explicitly **not** loop-able — it is human-participated design.
- Standing loop discipline binds every UI-touching row: build via
  `scripts/build-app.sh`, tests via `scripts/test.sh`, visual proof via
  `scripts/visual-proof.sh` manifests, and the PRESSURE rows (focus-non-theft ·
  idle-footprint · pulse-honesty · attention-non-theft) all still owe their
  burdens. Motion added in Phases 2–3 must map 1:1 to a user action or a real
  state change — never decorative.
- Ordering: 0 → 1 → 2 → 3 → 4, with Phase 5 parallelizable any time after 0,
  and Phase 6 gated on 2–4. Phase D (dogfood) runs alongside everything from
  Phase 1 on and is the product's actual open question.

---

## Phase 0 — Open the doors (repo table stakes) · zero risk, ship immediately

Nothing here touches product code; all of it changes how a stranger judges the repo.

- [x] **LICENSE (MIT)** at repo root. *(landed 5be626f; holder `provi (me@provi.me)` confirmed by user 2026-07-06)* Currently absent → default all-rights-reserved
      legally blocks forks and PRs. MIT per market evidence (the entire fast-growth
      menu-bar cohort — Stats 40k★, Gitify, RepoBar — is MIT; GPL only makes sense
      as an anti-incumbent stance githud doesn't have). *Proof: file exists, README badge.*
- [x] **CI** — `.github/workflows/ci.yml` running `scripts/test.sh` (PAT-free,
      319 checks, fast) + a build job; status badge in README. *Proof: green run on push.*
      *(workflow landed 5be626f; slug set to `pro-vi/githud` b525fef; **green run on
      first push 2026-07-06**, run 28838760847 — proof closed)*
- [x] **Tag `v0.1.0`** at HEAD + a GitHub Release with the zipped ad-hoc-signed
      `build/githud.app`, labeled unsigned. README declares "MVP complete"; the
      empty Releases tab currently reads as pre-alpha/abandoned. *Proof: release visible.*
      *(retagged at b525fef — the old local tag predated 20 landed commits, never
      pushed so safe to move; pushed 2026-07-06 with Release + zipped ad-hoc build,
      labeled unsigned: <https://github.com/pro-vi/githud/releases/tag/v0.1.0> —
      **private repo for now**, per user)*
- [x] **Orientation line for `loop/`** at the top of README: *(landed 7caec5e)* one sentence — "`loop/`
      and `docs/plans/` are this project's AI-pairing dev log — implementation
      detail, not required reading." (56 tracked loop files currently outweigh
      Sources/' 30 with zero signposting.)
- [x] **CONTRIBUTING.md** — state the loop relationship explicitly *(landed 7caec5e; PRs open, trust-logs framed as highest-leverage contribution)* (standard PRs
      welcome; ignore `loop/`; run `scripts/test.sh`, no PAT needed) or state that
      contributions aren't open yet. Silence currently reads as the latter.
- [ ] *(templates landed 7caec5e, YAML validated, now pushed; chooser-render proof
      = one look at the New Issue page — needs a browser, user's click)* **Issue templates that operationalize the north-star**: `missed-notification.md`
      ("githud hid something I needed") and `false-alarm.md` ("githud surfaced
      something useless"). This turns the trust experiment's two logs into
      community telemetry. *Proof: templates render in the New Issue chooser.*
- [x] *(landed 7caec5e)* **README PAT reframe** — keep the security-conscious setup, add *why* a
      classic PAT (the Notifications API rejects fine-grained/App tokens — an
      external wall, not a choice) and what githud never does with it (read-only,
      never acts). Note the in-app entry path coming in Phase 4.
- [x] Decide/annotate the `me.provi.githud` bundle-id namespace in README
      (or move to a neutral one) — unexplained corporate namespace reads oddly
      for an indie OSS tool. *(moved to `me.provi.githud` b525fef — user delegated;
      done pre-push at zero migration cost; queue labels renamed with it)*

## Phase 1 — Trust the glass (reactivity + honesty) · the doctrine's own debts

These are honesty bugs by the project's own standard. Highest product priority.

- [x] *(landed d46b11d + 8ebf504: format-at-render, expanded-gated bucket-flip
      re-render in the pure reducer; simulated-hours proof at unit level; 2 review
      blockers — filter-revert + stuck-stale banner — fixed and re-verified)*
      **Live ages.** `RadarRow`/`PulseRow` carry the timestamp (not a baked "· 2h"
      string, `RadarPresenter.swift:8`); views format age at render; re-render when
      a coarse age bucket flips and on every expand. Today `changeKey` excludes age
      by design, so the longest-stuck item shows the most-wrong age.
      *Proof: fixture with an old thread; expand after simulated hours → age correct.*
- [x] *(landed 8951d27: worst-of-both fold, don't-accuse-before-first-success;
      GraphQL-kill → caution unit-tested; 3-lens review PASS)* **H2 pulse joins Freshness.** `applyPulse` failures currently only hit a
      debug log (`PollScheduler.swift:148-162`) — the PR lane can freeze forever
      while the island claims fresh. Fold pulse success/failure into the freshness
      model (per-lane or worst-of-both), surfacing the existing caution cue.
      *Proof: kill GraphQL in a test double → caution appears; unit-tested.*
- [x] *(landed d46b11d + 8ebf504 + eb928ff: SnapshotStore never-fresh launch paint,
      reducer freshness seeded so the banner clears on first healthy poll, excerpts
      never persisted; round-trip/honesty/corrupt-file unit proofs ran; the live
      "relaunch offline → 1s" GUI proof needs a display — pending, in stop report)*
      **Persisted last-known-good snapshot.** Serialize the last rendered
      radar+pulse rows + timestamps; on launch, paint instantly **marked stale via
      the existing freshness banner** ("as of last session"). Kills the blank pill
      (worst case ~77s: sequential self-login → fetch → enrich → pulse before
      first paint). Honest by construction — no fabricated freshness.
      *Proof: relaunch offline → last data + stale cue within 1s.*
- [ ] **Poll-now triggers** — `NSWorkspace.didWakeNotification`, `NWPathMonitor`
      path-change, and panel-expand each trigger an immediate poll (debounced).
      All real events; squarely within no-faked-realtime. *Proof: wake from sleep
      → poll fires without waiting the ~60s tick.*
      *(wake+network landed 8951d27; panel-expand wired in WP-1c d46b11d — all
      three triggers live; accept/refuse/pause decisions unit-tested; the live
      wake proof needs a real sleep/wake cycle — pending, listed in stop report)*
- [x] *(landed 8951d27: shared NSLock-guarded pause, all five sites set+respect it,
      URLProtocol-stubbed per-endpoint tests ran; scope-403-with-headers correctly
      NOT masked — probed empirically, permanent regression test lands in WP-1c)*
      **Rate-limit backoff at all five call sites.** `rateLimitPause` currently
      guards only `GET /notifications`; enrichment, subject-state, self-login, and
      the GraphQL pulse retry on cadence with no backoff (`GitHubClient.swift`).
      *Proof: URLProtocol-stubbed 429/403-with-reset tests per endpoint.*
- [x] **Poll timer on `.common` run-loop mode** (`PollScheduler.swift:178`) — an
      open NSMenu currently stalls the tick. One line + a note. *(landed 8951d27)*
- [x] **`dispatchPrecondition(.notOnQueue(.main))`** at the top of
      `RadarPipeline.refresh/fetchPulse/blockingFetch` — turns a silent 30s
      main-thread hang into an immediate debug crash. One line each.
      *(landed 22577b8 + 1575300: unconditional after moving `githud probe`
      off-main; proven by graceful off-main probe run)*
- [x] *(landed: reducer + RadarSource 22577b8 (+43 checks), pulse-freshness +
      poll-now branches 8951d27 (+60 checks) — the named proof suite now exists
      in full; both packages 3-lens review PASS)* **PollScheduler becomes testable.** Extract a `RadarSource` protocol
      (`refresh()`/`fetchPulse()` → `Result`), inject it, and move the
      401→stop / 403→stop / rate-limit→pause / transient→retry / freshness
      decisions into a pure injected-clock reducer. The only trust-critical
      *stateful* object currently has **zero** tests while trivial pure code has
      40 suites. *Proof: reducer suite covering every branch incl. the new
      pulse-freshness and poll-now paths.*

## Phase 2 — Claude Design: explore every surfacable interaction ⛔ USER-PARTICIPATED

Run via **`/designer-loop`** (Claude Design through the designer MCP): the human
is the designer, Claude Design produces named variants, each settled exploration
gets a **decision record** (here or `loop/creative-consults.md`) and only then is
promoted to code in Phases 3–4. This phase is deliberately *before* the build
phases so the morph and onboarding implement ratified designs, not guesses.
Doctrine constraints carry into every prompt: ink by default · motion maps 1:1 to
user action or real change · no hover-as-primary · calm, never busy · the a11y
gray-swap law (meaning must survive without hue).

Interaction surface inventory to explore (feeling-shaped items get variants;
mechanical items are noted for Phase 3 and skip design):

- [ ] **The morph** — collapsed pill ⇄ expanded island transition: duration, curve
      (ease-out vs spring), whether content crossfades or the pill "grows into"
      the header, shadow/mask behavior mid-flight. The signature move; explore 2–3
      variants at real size over real desktops.
- [ ] **Collapsed pill state vocabulary** — loading dot · count+glyph · critical
      (danger) · caught-up segmented gauge · bare check · degraded-freshness
      prefix. Explore: do states share one geometry so width changes are calm?
      What does the ⛔-gated 150ms crossfade on a real count change look like vs
      an instant swap? (Crossfade judged on-doctrine — motion mapped to a real
      change — but brushes attention-non-theft: **user decides**.)
- [ ] **Expanded island anatomy** — header (count badge, gear, chevron), freshness
      banner appear/disappear, lane headers, stale/draft captions, the capped-lane
      **bottom fade** (overflow affordance replacing the invisible-overflow risk),
      footer inbox link. Explore density/spacing as a system, in all 5 themes.
- [ ] **Row interaction** — hover treatment (fill + ease), and the truncated-text
      reveal: click-to-peek inline expansion vs styled in-island tooltip vs status
      quo (OS tooltip only). The original intent's "inspector" collapsed to a
      one-line excerpt; decide its final form.
- [ ] **Empty/caught-up expanded state** — a single calm affirmation ("You're all
      caught up · nothing needs you") distinct from the banned per-lane
      placeholder. Explore tone + weight so it reads affirming, not blank.
- [ ] **First-run welcome card** (feeds Phase 4) — calm titled card, numbered
      steps, in-island secure token field, success moment (card morphs into the
      live pill?). The single highest-leverage trust surface; explore seriously.
- [ ] **Auth-error states** — 401/expired, wrong-shape token, SSO/scope 403: same
      family as the welcome card, error-but-not-alarming.
- [ ] **Status-item glyph language** (feeds Phase 5's hide affordance) — a calm
      hollow glyph when clear, filled/badged only when action is required, danger
      only for critical; template-rendered. This is the color doctrine applied to
      a fourth surface — needs a decided glyph set.
- [ ] **Keyboard session** ⛔ USER GATE (feeds Phase 6) — mock the interaction:
      hotkey-summon → focus ring on first row → ↑/↓/Return/Esc. Panel becomes key
      *only while keyboard-summoned* (mouse path stays non-key). A scoped,
      reversible relaxation of focus-non-theft — **user ratifies before build**.
- [ ] **Hide/show island choreography** — where the signal lives when the island
      is hidden (status item), and how it returns.
- Mechanical (no design pass needed, straight to Phase 3):
  `monospacedDigitSystemFont` on all counts/ages · hover-fill ~0.12s ease ·
  unified gear menu (Surface + Theme + Hide + Launch-at-Login + Quit) ·
  Control-click = right-click on the status item.

**Exit:** each explored row has a decision record; open ⛔ gates resolved
(crossfade yes/no, keyboard session yes/no).

## Phase 3 — Build the morph (elegance + interaction)

Implements Phase 2's decisions. All motion here is user-initiated or
real-change-mapped; Reduce Motion must degrade every item to the current
hard-cut behavior.

- [ ] **Animated expand/collapse** — one `NSAnimationContext` transaction
      (~0.22s, per Phase 2's curve) animating panel frame + content crossfade;
      interruptible; `reduceMotion` → instant. (`HUDPanelController.present`,
      `HUDPanelController.swift:236-248` today does a hard cut.)
      *Proof: screen-rec manifest; idle CPU still ~0 at rest.*
- [ ] **Click-away collapse** — passive `NSEvent.addGlobalMonitorForEvents(.leftMouseDown)`
      active only while expanded; click outside the panel frame → collapse.
      Observes, never steals focus. *Proof: focus-non-theft recording unchanged.*
      *(landed aa7e25f; passive + never-key verified by review; the recording proof
      needs an unlocked screen — pending, listed in the stop report)*
- [x] *(landed aa7e25f + 8fca3dc; was 3 renders/poll not 2; offset-survival proven
      live incl. theme-switch path; 3-lens review, hide() major fixed)*
      **Render coalescing + scroll preservation** — a changed poll currently
      tears down and rebuilds the island **twice** (radar then pulse) and destroys
      scroll position mid-read. Coalesce setters onto one next-runloop render;
      preserve per-lane scroll offsets across rebuilds (or diff rows).
      *Proof: scripted poll during scrolled state → offset survives.*
- [ ] **Bottom fade on capped lanes** (per Phase 2 treatment) — overlay scrollers
      autohide, leaving no "more below" cue; a clipped lane is a miss-adjacent risk.
- [x] **Unified gear menu** — gear opens Surface + Theme (+ Hide + Launch-at-login
      + Quit); Themes are currently findable only by right-clicking the status item.
      *(landed aa7e25f: Surface + Theme + Quit; Hide + Launch-at-login join in WP-5i)*
- [ ] **Caught-up expanded state** (per Phase 2 copy/tone).
- [ ] **Micro-polish batch** — monospaced digits everywhere counts/ages render;
      hover-fill ease; Control-click on status item; row truncated-text reveal per
      Phase 2's decision. *(all landed aa7e25f EXCEPT the text reveal — design-gated
      on D-reveal; box closes with it)*
- [ ] **Pill crossfade on real count change** — only if ⛔ gate approved.

## Phase 4 — The first 60 seconds (onboarding)

- [ ] **Welcome card replaces the orange MessageView** for the no-token state
      (per Phase 2 design): titled, calm, numbered steps, "what githud is" in one
      line, link to token creation. (`AppDelegate.swift:91-93`,
      `IslandContentView.swift:320-360` today: warning triangle + dense paragraph.)
- [ ] **In-app token entry** — secure `NSSecureTextField` in the card; validates
      classic-PAT shape (`looksLikeClassicPAT`); writes via `KeychainPAT`; never
      logs the value (existing `redacted()` discipline).
      *(plumbing landed 688de4f: KeychainPAT.store/delete, submitToken intake gated
      on the classic-PAT wall, never-log verified by review; the secure FIELD itself
      waits on D-card — WP-4d adds visuals + the call into submitToken)*
- [ ] *(mechanism landed 688de4f: startLiveSession extracted + reused, previous
      scheduler cleanly stopped — double-start refuted by review; reason-routed
      401/SSO-403/wrong-shape MessageView copy live; the named cold-start GUI proof
      runs when D-card lands)* **Hot start** — token stored → construct `GitHubClient` + start
      `PollScheduler` live, card morphs into the pill; no relaunch. Auth-error
      states (401 / wrong-shape / SSO 403) route back into the same card family
      with specific guidance. *Proof: cold start with no token → paste token →
      live pill within one poll, zero relaunches.*

## Phase 5 — Shipping-Mac-app basics (native integration) · parallelizable after Phase 0

- [x] **Launch at login** — `SMAppService.mainApp` + a checked menu item
      reflecting `.status`. An "ambient always-on" product that dies on reboot is
      self-refuting. (macOS 13 floor already satisfied.)
      *(landed e2b0574; checkmark reads .status live, .requiresApproval opens
      System Settings; real register round-trip unverifiable on an ad-hoc bundle
      (.status=notFound) — reliable only after Developer ID at the launch gate)*
- [x] *(landed e2b0574: screenProvider closure, call-time 3-step fallback,
      screen-params observer; live multi-monitor move untestable headless)*
      **Correct screen anchoring** — anchor to `statusItem.button?.window?.screen`
      (fallback: screen under mouse, then main) instead of `NSScreen.main`
      (`HUDPanelController.swift:220,244`), and observe
      `didChangeScreenParametersNotification` → re-clamp/reposition. Today the
      island can land on the wrong monitor or orphan off-screen.
- [x] *(landed e2b0574: menu item in the shared menu, state from live isVisible;
      glyph-as-fallback-signal waits on D-glyph; full-screen auto-suppress
      deferred as a product call — in stop report)* **Hide/Show island** — wire the existing dead `hide()`
      (`HUDPanelController.swift:142`) into the unified menu; status-item glyph
      becomes the fallback signal per Phase 2's glyph language. Optional:
      auto-suppress over full-screen frontmost apps (presentations).
- [ ] *(value construction landed b4dca46+e2b0574 — pure Core presenter, exact
      visual-branch parity confirmed by review, every state unit-tested; the named
      proof "VoiceOver reads every pill state" needs a live VO session — pending,
      in stop report)* **VoiceOver value on the collapsed pill** — `accessibilityValue` built from
      the same inputs as the visuals ("3 need you" / "all clear" / "2 ready,
      1 blocked", prefixed "reading may be stale" when degraded)
      (`CollapsedPillView.swift:48` today: static "githud — expand"). The pill is
      the product's thesis surface and it is currently mute — this is the
      gray-swap law's ultimate test. *Proof: VoiceOver reads every pill state.*
- [x] *(landed e2b0574: effectiveTheme choke point — border 1px opaque, hover
      ×2.2, tertiary→secondary; composes with Reduce Transparency)*
      **Increase Contrast** — branch on `accessibilityDisplayShouldIncreaseContrast`
      (same observer as Reduce Transparency, `AppDelegate.swift:121-125`): border
      0.5→1px opaque, hover fills strengthened, tertiary ink promoted.
- [x] **Appearance-change repaint** — baked `CGColor`s (border, badge, solid
      surface) don't re-resolve on Light↔Dark/accent change; add
      `viewDidChangeEffectiveAppearance` re-resolution.
      *(landed e2b0574: in-place re-bake, no re-entry — reviewed; live Light↔Dark
      visual diff not screen-recorded)*
- [ ] **Status-item state glyph** — per Phase 2's decided language; template image.

## Phase 6 — Growth architecture + launch · gated on Phases 2–4

- [x] *(landed ebd501d + aec373a: main-confined AppModel, synchronous observer
      list, change guards in mutators; render-count parity verified per event by
      the review panel)* **AppModel/store** — single observable app state (prefs, theme, freshness,
      rows, expanded); controllers render from it; AppDelegate mutates it. Do this
      *before* any Settings window or third lane; today every toggle hand-threads
      through 3–4 objects.
- [x] *(landed aec373a: factory owns surface/material/mask/border/grain/appearance
      re-bake; controller = lifecycle + render coordination)* **`IslandSurfaceFactory`** — extract theme→surface construction
      (`buildSurface` + mask, `HUDPanelController.swift:52-103`) from the
      controller; the controller becomes lifecycle + render coordination only.
- [x] *(landed ebd501d: PulsePresenter.sections(for:) is the one home; pill, island
      and VoiceOver presenter all consume it — byte-identical rule, panel-verified)*
      **Dedupe the live-work rule** — `!isDraft && !isStale` is triplicated across
      `IslandContentView.swift:60` and `CollapsedPillView.swift:21,90`; presenter
      hands views `PulseSections`/`liveRows` instead.
- [ ] **async/await migration** — delete the semaphores and the main-thread
      footgun outright (`actor RadarPipeline`); documented deliberate deferral,
      natural after the Phase 1 injectable-source refactor. Includes lifting
      `Package.swift` to Swift-6 language mode.
- [ ] **Keyboard session** — build per Phase 2's mock, only if ⛔ gate approved:
      global summon hotkey (no key status needed) + scoped key session while
      keyboard-summoned (↑/↓/Return/Esc, focus ring), focus returned on dismiss.
- [x] **Global summon hotkey** (independent of the key-session gate — toggling
      expand needs no key status; ship even if row-nav is declined).
      *(landed e86b10d: ⌃⌥G, Carbon RegisterEventHotKey — no permission, no key
      status; registration OSStatus 0 live-proven; a real keypress needs a GUI
      session — one press to confirm at dogfood)*
- [ ] **Launch** — Developer ID + notarization + Sparkle + Homebrew cask (unsigned
      casks are deprecated from the official tap by Sept 2026 — this is the
      distribution floor); hero GIF (idle pill → morph → theme switch) captured
      via the existing visual-proof pipeline **after** Phase 3 so the GIF shows
      the morph; then HN/PH with the hook **"the first notification tool that
      shows you what it hid"** (market scout: the ambient-surface + open
      classifier + auditable-suppressed-set combination is unclaimed; never
      "Arc but better" — killed framing). **Hold the launch until Phases 3+4 land
      — first impressions are unrepeatable.**

## Phase D — Dogfood (standing gate, runs alongside from Phase 1) ⛔ USER

No glass work substitutes for this; it is the product's actual open question and
only the user can run it (INTENT's standing #1 open call; `signal-trust-budget`
is DOWNGRADED, not paid).

- [ ] **Full-inbox suppressed-set re-audit** — 272 threads (~222 suppressed) via
      `githud probe --show-items --show-suppressed`, now that the page-1-only
      pagination bug is fixed. The iter-20 "it holds" verdict covered 50 of 272.
- [ ] **Daily-driver run** — multi-day, logging the two north-star inputs
      (false alarms / misses) against the 1–2/day budget.
- [ ] Feed results back: any miss → classifier fix before anything cosmetic; any
      friction → new rows here.

---

### Decision log (fill as gates resolve)

| Gate | Decision | Date | Record |
|---|---|---|---|
| Pill crossfade on real change | YES, as slot-morph: shared chassis, only the changed cell fades (120ms), digit ticks stay still, width settles 150ms | 2026-07-06 | user ratified runner pick; spec `docs/design/specs/Gates.json` |
| Keyboard session (scoped key) | YES: canBecomeKey only on the ⌃⌥G path, ink-bar focus, app never activates; 0-modifier Carbon capture banned | 2026-07-06 | user ratified runner pick; PRESSURE proof re-word + re-cut owed pre-merge |
| MIT vs other license | MIT, holder `provi (me@provi.me)` | 2026-07-06 | user confirm; LICENSE @ 5be626f |
| Bundle-id namespace | `me.provi.githud` (personal, matches license holder + repo owner) | 2026-07-06 | delegated by user ("trust your impl"); b525fef |
| Trust-code review (S1) | signed off — Phase 1 declared done | 2026-07-06 | user: "i trust your impl" |
| Push / repo visibility | pushed to **private** repo `pro-vi/githud`; Release v0.1.0 live; public later | 2026-07-06 | user: "private repo for now is fine" |
