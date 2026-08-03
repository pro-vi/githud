# githud — loop state

```yaml
archetype: greenfield
identity: "githud greenfield discovery loop — native AppKit macOS GitHub HUD overlay"
primitive_bundle:
  target-shape: discovery-reframing
  halt-shape: manual-gated
  artifact-shape: rubric+intent
  convergence-shape: stone-reframe
  cadence-shape: checkpoint-gated
divergences: []          # pure greenfield, distance 0
overlays:
  - consult-tier-3
  - pressure            # 4 authored rows seeded
consult_tier: tier-3     # primary /agentify (Agentify Desktop MCP, extended-pro); PAL cross-family
evaluator_tier: T2       # ramp stages 1-3,5 closed; stage-4 (Spaces/notif-diff) deferred to gates
runnable: true           # bootstrap + rubric ratification launchable now; data/visual-evidence gate on preloop

derivation_read_set:
  - templates/composed-prompt.md
  - primitives/target-shape.md
  - primitives/halt-shape.md
  - primitives/artifact-shape.md
  - primitives/convergence-shape.md
  - primitives/cadence-shape.md
  - primitives/consult-capability.md
  - primitives/frontload-audit.md
  - primitives/runner-contract.md
  - primitives/judgment-default.md
  - primitives/evidence-tier.md
  - primitives/halt-cause-classifier.md
  - primitives/queue-as-second-artifact.md
  - primitives/pressure.md
  - primitives/evaluator-maturity.md
  - archetypes/greenfield.md
  - templates/bodies/greenfield-body.md
  - references/greenfield-invariants.md

frontload:
  resolved:
    - motive
    - evidence-surface-plan
    - scope-manifest
    - consult-tier (tier-3)
    - target-adjacency
    - intent-hypotheses (>=3)
    - model-identity (n/a — Swift app, no embedded LLM)
    - paid-apis (none — GitHub REST free; no budget policy needed)
    - phase-0-research (seeded done; see research_complete exit_evidence)
  defaulted:
    - quiet_signal_N: 8
    - stuck_attempt_N: 3
    - user_look_gate_iters: 25      # smaller than invariant ~50: MVP is small
    - consult_cadence_iters: 10
    - codesign: ad-hoc (--sign -)
    - pressure_cap: 12
  open_gaps: []                       # BOTH preloop gates CLOSED 2026-06-16 (PAT live-validated; screen-rec verified) → preloop_complete=yes. Loop fully unblocked.

artifacts:
  canonical:
    - loop/PROMPT.md
    - loop/STATE.md
    - loop/RUBRIC.md
    - loop/INTENT.md
    - loop/README.md
    - loop/PRESSURE.md
    - loop/creative-consults.md       # created on first consult
  repo_aliases: {}                    # no repo-native build yet

# ---- greenfield-specific keys ----
score_lock: no                        # released at iter 0 — RUBRIC ratified
rubric_version: v0.2                   # iter 1: consult-driven reframe (signal/trust is the spine)
score_comparable_with: []             # v0.1 quarantined; had no scores → quarantine free
rubric_ratified: yes
phase_gates:
  research_complete:
    value: yes
    owner: loop
    exit_evidence: >
      GPT-Pro Extended-Pro architecture consult (2026-06-15). Decision: native
      AppKit-first Swift (SwiftPM, no full Xcode) over Tauri. NSPanel
      non-activating overlay (level=.statusBar; collectionBehavior=[canJoinAllSpaces,
      fullScreenAuxiliary, stationary, ignoresCycle]; canBecomeKey/Main=false;
      orderFrontRegardless). NSVisualEffectView owns vibrancy. REST Notifications
      API spine + Last-Modified/X-Poll-Interval conditional polling; threads not
      events. Classic PAT auth (fine-grained / App tokens UNSUPPORTED by
      Notifications API). Stars/forks via Events API (not real-time) deferred from
      v1. Rejected: Tauri (macOS transparency needs macOSPrivateApi → no App
      Store; setIgnoreCursorEvents is whole-window only). Risks still open: NSPanel
      over Stage Manager/notch; polling-cadence feel.
  preloop_complete:
    value: yes
    owner: user
    derivation: "both sub-gates satisfied 2026-06-16: github_classic_pat_ready=yes (user, live-validated) AND screen_recording_permission=yes (verified). Derived value set to match its definition; user owns final say."
  github_classic_pat_ready:
    value: yes
    owner: user
    flipped_by: "user (provi) — explicit gate flip 2026-06-16"
    keychain: "login keychain — service=githud.github.pat, account=github; read via `security find-generic-password -s githud.github.pat -a github -w`"
    exit_evidence: >
      Classic PAT (ghp_, 40 chars, scope=notifications) created by the user and
      stored in the login keychain (service githud.github.pat / account github).
      LIVE-validated against GET /notifications 2026-06-16: HTTP 200,
      x-oauth-scopes=notifications, x-poll-interval=60, last-modified present,
      ratelimit 5000/4976. The notifications-classic-pat WALL is now satisfied on a
      live tier-2 signal (not just code intent). Unblocks the live trust experiment
      (RUBRIC #11 top-of-range) and the GitHubClient polling spine. Read the token
      from Keychain at runtime — never log it, never write it to disk plaintext
      (RUBRIC #9).
  screen_recording_permission:
    value: yes
    owner: user
    verified_by: "loop at user's request 2026-06-16 — user granted the permission; loop verified with tier-2 evidence and flipped"
    exit_evidence: >
      CGPreflightScreenCaptureAccess() == true (authoritative TCC API) AND an
      empirical capture has real content (full-screen 3456×2234, variance 207).
      visual-proof.sh now produces a REAL island manifest:
      loop/evidence/idle-normal-desktop-3.manifest.json — status=captured,
      pixel_live=true (island region 560×84, mean 38.5 / max 200.4 / variance 162.7,
      36 distinct colors), png_sha256 recorded. Lifts the visual-criteria cap of 2;
      unblocks real HUD evidence frames + blind comprehension reads of populated
      island screenshots.
  bootstrap_complete:
    value: yes
    owner: loop
    exit_evidence: >
      iter 0: `swift build` returns 0; the HUD island is on screen — CGWindowList
      shows one window owned by `githud`, layer 25 (NSStatusWindowLevel), bounds
      280×42 at (724,46), within_screen true, size_class collapsed
      (loop/evidence/validate-window-0.json + idle-normal-desktop-0.manifest.json);
      RUBRIC v0.1 ratified (score_lock released). Package.swift (GithudCore +
      githud + GithudCoreTests), Resources/Info.plist (LSUIElement), and
      scripts/{build-app,run-app,validate,visual-proof,test}.sh all present and
      green. build-app.sh assembles + ad-hoc-signs githud.app (valid on disk,
      Identifier me.provi.githud).
target_hypotheses: [H1-action-radar (core, validated), H2-ambient-pulse (BUILT+proven iter 25, user-directed second lane), H3-full-client (killed/guardrail)]   # iter-1 reframe + iter-25 H2 build; see INTENT.md
current_stone_axis: data-spine-completeness   # iter 2: classifier (moat) proven on fixtures → polling-discipline + integration next
intent_reframes:
  - iter: 1
    source: "consult 001 (gpt-5.2 blind adversarial)"
    change: "H1 sharpened literal-inbox → action-radar ('do I need to act?'); H2 demoted to conditional skin (presence signals unavailable from Notifications spine — invalidating evidence); H3 killed to guardrail; hover-as-primary flagged a trap; north-star + trust experiment pre-registered."
    stale_scores_reset: "none existed (v0.1 ratified, nothing scored) → rubric → v0.2, quarantine free"
capability_list:
  - swiftpm-swiftc
  - screencapture (LIVE — permission granted+verified 2026-06-16; pixel_live manifests now produced)
  - swift-format / swiftlint
  - gh-cli + curl
  - agentify-mcp (/agentify, extended-pro) / pal
  - top / osascript / log
user_halt_owner: user                 # Next action: HALT is the user's flip

# ---- iteration cursor ----
iteration: 41
phase: main                            # H1 doctrine-themed; H2 GitHub-native status icons; freshness; dogfood polish
current_artifact: Sources/GithudApp    # next: user confirms; then the trust audit
mvp_h1_complete: yes                    # iter 13
last_action: >
  iter 41 (DOGFOOD #8 — vertical centering). The leading glyph/status-badge was top-aligned to
  the title line (row stack alignment .top), so it sat high. User: "center the icon vertically."
  Changed both RadarRowView + PulseRowView row stacks to alignment .centerY → the glyph now
  centers against the whole row text (title + subtitle). Visual-proven 346 (GitHub status badges
  centered; conflict gray, fail red, ready green all visible). .app rebuilt. Eighth dogfood tweak.
  ──
  iter 40 (DOGFOOD #7 — FULL GitHub-native PR-status set, user: "yeah do the full set"). Extended
  iter-39's conflict glyph to ALL H2 states: a new GitHubStatus enum + GitHubStatusBadge (a 16px
  filled status-color circle + white inner glyph) — green ✓ success, red ✕ failure, amber ● dot
  pending, gray ⚠ conflict, gray ✎ draft — using GitHub Primer colors (#3FB950/#F85149/#D29922/
  #6E7681), THEME-INDEPENDENT. Applied in BOTH the expanded "Your PRs" rows (forPulse(state,merge))
  and the collapsed pill gauge (forState) so they match. REMOVED theme.pulseGlyph entirely (H2 no
  longer themed) + GitHubConflictBadge (subsumed). DOCTRINE EVOLUTION: the iter-30 color doctrine
  still governs H1 (radar ink+critical) + freshness (caution) + accent=chrome, but H2 PR-STATUS is
  now carved out as GitHub's visual language (theme-independent), the same exception class as the
  systemOrange auth warning. `success` token now reserved (GitHub green used instead). 283 checks.
  .app rebuilt; visual proof deferred (display asleep at capture) — user verifies live on real PRs
  (they have success/fail/pending/conflict PRs). Seventh dogfood-driven change.
  ──
  iter 39 (DOGFOOD #6 — GitHub-native conflict glyph; user: "github conflict is [gray-circle +
  white warning-triangle], we should match that despite themes"). A merge conflict now renders
  GitHub's OWN icon — a muted gray (#6E7681, GitHub fg.muted) circle with a white warning
  triangle — THEME-INDEPENDENT. New principle: a PR's *status* is GitHub's visual language, not
  githud's chrome (same rationale as the auth warning that stays systemOrange across themes), so
  a conflict reads identically in every theme rather than taking the theme's danger color.
  Threaded the raw `merge` member onto PulseRow; PulseRowView swaps in GitHubConflictBadge when
  merge==.conflicting (else the themed pulse glyph). This narrows the color doctrine for H2: the
  blocked STATE stays themed, but the conflict SUB-CASE adopts GitHub's canonical gray glyph.
  283 checks (+2: merge threads onto the row). Visual-proven 343 (fixture #78 conflicting shows
  the badge). .app rebuilt. OPEN: offer to extend GitHub-native status icons to the other states
  (CI-fail red X, ready green check, pending yellow dot) if the user wants full GitHub parity.
  ──
  iter 38 (DOGFOOD #5 — user screenshot diagnosed it precisely). The user shared a real
  expanded-island shot: the vibrancy BOX IS GONE (iter-34 maskImage worked — clean rounded
  island, no rectangular bleed). The actual complaint ("icons' tops clipped a little") was a
  LAYOUT bug: the leading reason/state glyphs were pinned to the row TOP (icon.topAnchor =
  iconWrap.top+1, iconWrap had no height) so with the row stack's .top alignment they sat at
  the row's top edge — above the title's visual center — reading as clipped/too-high. FIX: give
  iconWrap a fixed height (~the title line, 18) and CENTER the glyph in it, so a top-aligned row
  places the glyph on the TITLE's center. Both RadarRowView + PulseRowView (identical iconWrap).
  Visual-proven 342 (glyphs now centered on their titles). NOTE: the user's screenshot was a
  pre-iter-37 build (no collapse chevron visible) — the reliable minimize + insets + tooltips
  land once they pkill+relaunch. .app rebuilt. Fifth dogfood-only finding; the screenshot made
  it a 2-minute fix vs a third blind guess — lesson: ask for the artifact.
  ──
  iter 37 (DOGFOOD #4 — minimize unreliable + long-line reveal). The collapse chevron used an
  NSButton, which is finicky on a non-key panel (same first-mouse problem as the rows had) →
  replaced gear + chevron with IconButton: a gesture-driven IslandClickableView (reliable first-
  click + hover highlight + pointing-hand cursor, so the collapse affordance is now discoverable,
  not an inert 16px glyph). Bumped the expanded content insets (top/bottom 13→16, left/right
  16→18) so no content sits under the 14px rounded-corner mask ("some icons cut off"). Added
  toolTips on radar+pulse rows so a truncated long line reveals its FULL text on hover (the
  user asked for horizontal-scroll; tooltip is the reliable reveal — a scrolling marquee is
  offered as a follow-up, but it adds motion the app has deliberately avoided). 281 checks; .app
  rebuilt; visual-proven 341. STILL OPEN (can't reproduce headlessly — capture crops to the
  window bounds, so the vibrancy bleed/shadow/clip lives outside it): the "bounding box not
  good" — requested a fresh user screenshot to diagnose precisely rather than guess a 3rd time.
  ──
  iter 36 (DOGFOOD #3 — reactivity + clear expand/minimize affordances; the user: "I want some
  reactivity when I hover and a clear path to expand and to minimize. Really bad"). Centralized
  hover in the IslandClickableView base: on hover, EVERY clickable view (collapsed pill + radar/
  pulse rows + inbox link) now lights with theme.hoverFill AND shows a pointing-hand cursor
  (cursorUpdate via a .cursorUpdate tracking area — authoritative on a borderless overlay where
  cursor rects are unreliable). The collapsed PILL is now hover-reactive (was inert) — the main
  ambient state finally feels clickable. Added an explicit COLLAPSE control: a chevron.up button
  top-right of the expanded header (onCollapse → setExpanded(false)), beside the gear. Refactored
  the per-view hover duplication (rows/inbox each had their own hoverFill + tracking + enter/exit)
  down to the base. So now: hover = highlight + pointing hand everywhere; expand = click the
  bubble; minimize = the header chevron (or the menu-bar item). 281 checks; visual-proven (340 —
  chevron + gear in the header); .app rebuilt. Third straight dogfood-only finding.
  ──
  iter 35 (DOGFOOD BUG #2 — the island was non-interactive: grab cursor on hover, no clicks
  registered, couldn't expand or open rows). Root causes, all from the panel being NON-KEY by
  design (canBecomeKey=false, focus-non-theft): (1) NSVisualEffectView defaults
  mouseDownCanMoveWindow=TRUE → the surface read as a draggable window background (grab cursor)
  and consumed mousedowns as window-drags; (2) a non-key panel makes EVERY click a "first
  mouse", which default views reject as an activation attempt → row gesture-recognizers never
  fired; (3) inner labels/glyphs hit-tested over the row, and they reject first-mouse too;
  (4) the gear NSButton had the same first-mouse problem; (5) there was NO click-to-expand on
  the collapsed pill (expand was menu-bar-only — unintuitive). FIX: IslandEffectView/
  IslandSolidView (mouseDownCanMoveWindow=false + acceptsFirstMouse=true) for the surfaces; a
  shared IslandClickableView base for the rows/pill/message/inbox (those two overrides + a
  hitTest that treats the whole view as one click target so inner labels don't swallow it);
  FirstMouseButton for the gear; and the collapsed pill is now CLICK-TO-EXPAND (onTap →
  toggleExpand). 281 checks; .app rebuilt. Two dogfood bugs in two launches — real use is paying
  out exactly as predicted; neither was reachable by fixture/visual-proof (both are live mouse
  behaviors).
  ──
  iter 34 (FIRST DOGFOOD BUG — the user launched the real .app and saw a rectangular "bounding
  box" around the rounded island). Root cause: an NSVisualEffectView's vibrancy is NOT clipped
  by layer cornerRadius/masksToBounds (a private backdrop layer draws the material), so on the
  Color (only vibrant) theme the translucent material bled to the rectangular window bounds +
  the drop shadow was rectangular → a box around the rounded hairline border. The solid themes
  were unaffected (plain layer-backed view). Invisible in visual-proof (captures crop to the
  window bounds). FIX: `effect.maskImage = roundedMaskImage(14)` (the documented way to shape an
  NSVisualEffectView — clips the material AND rounds the shadow) + `panel.invalidateShadow()`
  after each resize. 281 checks; .app rebuilt. Proves the point that real use surfaces what
  fixture/visual-proof can't — the loop's highest-value fuel is dogfooding.
  ──
  iter 33 (product — FRESHNESS / degraded-reading-confidence; the moat extended to "is this
  reading even CURRENT?"). Closes the last silent honesty hole: a poll that fails/stalls left
  the last-good radar+pulse on screen with NO cue it was stale — the faked-liveness trap the
  app is built against. Now: PollScheduler tracks lastSuccessAt (200 OR 304 = current) +
  consecutiveFailures; a pure FreshnessModel (GithudCore, 11 tests) maps (lastSuccess, now,
  failures) → .fresh | .stale(age) | .failing(n) (degraded after 2 failures OR >180s without a
  success; nil-lastSuccess = loading, not stale; rate-limit pauses aren't 'failures' but age
  into .stale). Emitted on CHANGE only (no new timer; .fresh adds zero re-renders — normal
  operation stays quiet). The HUD shows the doctrine's SANCTIONED caution use: a caution-amber
  "Reconnecting — last update 8m ago" banner atop the expanded island, and a caution clock
  prepended to the collapsed pill (staleness must reach the GLANCE — that's where you trust it
  without expanding). This gives the `caution` token its FIRST consumer → the color doctrine is
  now complete (danger=intervene, success=unlocked, caution=degraded-reading all live). 281
  checks (+11). Visual-proven --stale: 330 (expanded banner, amber, 520×479 = +22 banner) + 331
  (collapsed caution pill, 79×36 = +19 clock pad), both pixel_live; without --stale, no chrome.
  ── iter 32 (WHOLE-PROJECT REVIEW ROUND 2 — user-pasted 62-agent cross-model review; every
  finding VERIFIED against current code). Its 3 P1s (selfResolved latch, change-keys,
  notifications pagination) were ALREADY FIXED in iter 31 (it ran on the pre-31 tree) —
  re-verified resolved. Fixed the NEW verified findings: (#6) GraphQL data+errors now throws
  (errors-first) so a PARTIAL pulse never renders as authoritative truth (pulse-honesty);
  (#5) pulse query first:50→100; (#13) looksLikeClassicPAT length gate >=36→>=40 (a truncated
  39-char paste no longer passes the 'classic PAT ✓' gate then 401s); (#11) EXTRACTED the
  radar/pulse change-keys to GithudCore (RadarPresenter.changeKey / PulsePresenter.changeKey)
  — pure + now UNIT-TESTED (in-place escalation; blocked-draft→blocked-live isDraft flip, the
  exact silent miss); (#7b) a non-rate-limit 403 (scope/SSO/forbidden) now stops + surfaces a
  setup message instead of looping forever; (#8b) URLSession timeoutIntervalForRequest=15 so a
  stalled request self-cancels (bounds abandoned tasks); (#10) Theme Reduce-Transparency
  fallback → appearance-aware windowBackgroundColor (was a fixed dark fill → dark-on-dark under
  Color theme in Light mode); (#12) EVIDENCE_JSON no longer emits the raw oauth_scopes string
  (capability disclosure in a committed artifact) — has_repo_scope boolean kept; SCRUBBED the 4
  committed live-probe files; (#14) htmlURL maps /commits/→/commit/ (commit notifications no
  longer open a 404); (#15) UTF-8-safe error-body excerpt (String(decoding:) never blanks on a
  severed multibyte); (#16) --fixture with a bad path now fails LOUDLY (was a misleading 'no
  token' island). 270 checks (+9). Live-verified post-change: 272 threads, 304 fires, enriched=26
  clean, EVIDENCE_JSON oauth_scopes-free (live-probe-32.json). DEFERRED (noted, real): island
  height scroll/clamp (#9 — maxRows bounds it; scroll view = focused follow-up); full pulse
  pageInfo pagination (>100 PRs); full async/background enrichment; EVIDENCE_JSON extract-to-
  testable; GHE/Release htmlURL hosts; a11y keyboard nav. REFUTED severity: #4 approval_requested
  is NOT 'hidden' — the iter-24 novel-reason surfaces() default already puts any unknown reason
  on the radar (urgency 60); explicit high-urgency mapping deferred pending confirmation it's a
  real GitHub reason.
  ── iter 31 (CODE REVIEW ROUND — user-pasted external review, all findings VERIFIED then
  fixed). HEADLINE (moat-critical): /notifications read PAGE 1 ONLY (no per_page/Link
  handling) → thread_count capped at 50. The live probe AFTER the fix returns 272 threads
  on the same account: the old code was silently DROPPING 222 notifications (82%),
  including action-required review_requested/mention/author on pages 2-6. The never-miss
  moat was BROKEN; the iter-20 'it holds' user audit only ever saw page 1. FIX: per_page=50
  + follow Link rel=next (testable parseNextLink), accumulate all pages, page-1 carries
  poll/rate/scopes, bounded to 20 pages, partial-on-page-error (never lose page 1). Live-
  verified: 272 threads across ~6 pages, 304 conditional STILL fires (poll discipline
  intact), rate 4943/5000, pulse 20 PRs (live-probe-31.json). OTHER fixes (all verified
  real): F10 review-decision mapper now fails safe (unknown non-null → reviewRequired, not
  ready-eligible none — mirrors the iter-26 CI fix; pulse-honesty hole closed); F9
  selfResolved set only on a real login (a fast /user 403 no longer permanently disables
  self-demotion); F3/F4 redraw keys now hash all display-affecting fields (radar: same-id
  excerpt/actor/reclassify redraws; pulse: draft→non-draft + CI/review/merge changes redraw
  — a blocked draft becoming actionable no longer stays hidden); F5 honor rate-limit
  Retry-After/X-RateLimit-Reset (new .rateLimited error; pause to reset, don't hammer); F8
  enforce classic-PAT shape at GUI startup (fine-grained token → setup message, not a silent
  403 loop); F6 bounded enrichment budget (12s/refresh + 6s/fetch — a slow network no longer
  stalls first render for minutes; un-enriched still surface); F2 README uses interactive -w
  (token never in shell history/argv); F7 a11y — clickable rows are now labelled .button with
  accessibilityPerformPress (VoiceOver/keyboard reachable). 261 checks (+7: parseNextLink +
  review-drift). DEFERRED (noted, real): full async/background enrichment (F6 is a budget
  mitigation, not the partial-render refactor); runtime-403→setup-failure classification
  (F8 startup-only, to avoid false-stops on secondary-limit 403s).
  ── iter 30 (product — COLOR DOCTRINE, user-directed `/agentify discuss to land on color
  theory`): a GPT-Pro extended-pro consult (008, 9m56s) ratified a coherent color theory and
  the loop APPLIED it the same iteration. DOCTRINE: shape=what · order=priority · color=changed
  next-move; ink by default; color spent only on danger(intervene)/success(action-unlocked)/
  caution(reading-degraded); critical facts cross to the collapsed pill; no meaning by hue
  alone. It's the palette serving the SAME trust moat the classifier serves with attention.
  SHIPPED: (1) H1 radar heat scale → monochrome glyphs + ONE reserved critical
  (security_alert→danger); `SignalClassifier.criticalReasons`+`isCritical`; `radarUrgencyColor`
  killed → `Theme.radarGlyphColor(critical:)` (ordinary=inkSecondary). (2) GPT caught a LIVE
  bug: critical must be a separate SORT dimension — `radar()` now sorts critical-first then
  urgency (else review_requested=95 strands security_alert=92's red glyph below a calm row);
  proven on the fixture (1005 above 1001, urgency unchanged at 92). (3) `RadarRow.isCritical`;
  pill critical-aware (`rows.contains{isCritical}`). (4) GREEN settled = `ready` (merge
  unlocked), NEVER "alive" (open PRs are open by query → green-for-alive = an invariant, the
  urgency-heat mistake again); resolves the user's "green feel?" musing — NO. (5) YELLOW removed
  from every state: `waiting`→inkSecondary outline clock (ordinary in-flight ≠ caution),
  `draft`→inkTertiary; `caution` reserved for degraded READING confidence (freshness; no UI
  yet), `warn` deprecated. 254 checks (added a doctrine suite). Visual-proven 300 Color / 301
  GitHub / 302 Solarized-Light expanded + 303 collapsed critical pill (all pixel_live,
  within_screen); blind read = lone red security shield on top + ZERO yellow. New pressure
  `color-doctrine`. plan 2026-06-20-001 graduated active→completed (with amendments).
  ── iter 29 (product — user-directed follow-ups): (a) +3 THEMES — Tokyo Night, Catppuccin,
  Solarized Dark (each one ThemeID case + one Theme.named palette; the system paid off) → and
  a LIGHT theme: Solarized Light (warm cream #fdf6e3, dark ink, hoverFill flipped to
  black-alpha so it's visible on light). 9 themes total (8 dark + 1 light), the Solarized
  PAIR (dark #002b36 + light) last. Refinements from user review: swapped Gruvbox → Solarized
  Dark; FIXED Dracula (its dim text used a made-up gray #9EA3C0 → now the signature comment
  purple #6272A4, so it reads distinctly Dracula). All visual-proven (281-294). (b) The CAUGHT-UP GAUGE REDESIGN (the long-open
  /ui-sketch decision): user picked C → shipped the SEGMENTED gauge — PulsePresenter.gauge
  (ready/blocked/waiting counts) replaces the worst-state+total rollup; the pill renders
  count-matched segments "✓ready · ⚠blocked" (good news leads, real backlog follows; waiting
  shown only when alone; drafts excluded). Fixes the old "red 11" mismatch + the ready-lead
  dishonesty. Themed automatically (each segment via theme.pulseGlyph). 241 checks; visual-
  proven "✓3 ⚠3" collapsed (290/291, 88×36, pixel_live, --collapsed affordance).
  ── iter 28 (product — THEME SYSTEM, user-directed). The user reframed the monotone-icon
  exploration as a theme system. Flow: /research (native macOS theming sweep) → /architect →
  /build, 5 units, all green. SHIPPED a runtime, user-selectable theme system with 5 themes:
  Color (default), Geist Mono, GitHub, Dracula, Nord. ARCHITECTURE (research-backed): a Theme
  TOKEN BUNDLE (GithudApp: surface vibrant↔solid, border, ink tiers, accent, danger/warn/
  caution/success/neutral, monochrome flag, hover, grain) + a pure ThemeID registry
  (GithudCore, testable) + ThemeStore. NO ThemeManager singleton — rides the existing render()
  rebuild path (setTheme mirrors setPulsePreferences). Two orthogonal axes (system light/dark
  stays on NSAppearance; brand theme = ours). Surface = solid for exact palettes (vibrancy
  ties color to the desktop), vibrant .popover only for Color. STATIC seeded 128×128 grain
  tile (Geist; deterministic LCG, no Date/random) → idle_cpu 0.3% (idle-footprint HOLDS).
  Reduce-Transparency→solid a11y (stored id unchanged). Theme menu picker; --theme arg.
  Every island color now from a token (grep gate: no hardcoded systemRed/label*/controlAccent
  left). Color theme reproduces the ORIGINAL look exactly (parity, structural + visual). 231
  checks. Visual proof ALL 5 themes (idle-normal-desktop-281..285, status=captured, pixel_live,
  520×457). docs/plans/2026-06-19-001-feat-theme-system-plan.md.
next_action: >
  iter 33 — freshness shipped → the color doctrine is COMPLETE (all three semantic colors have
  live consumers) and the spine's last silent-stale honesty hole is closed. The #1 priority is
  STILL the same and STILL needs the user: re-run the reveal-suppressed trust audit on the FULL
  inbox (272 threads, ~222 suppressed; the iter-20 'it holds' saw page 1 only), then the
  daily-driver run. Autonomous-buildable backlog if the loop continues without the user (all
  real, none blocking): island height scroll/clamp (review #9), async/background enrichment,
  EVIDENCE_JSON extract-to-testable (privacy-emitter coverage), full pulse pageInfo pagination,
  GHE/Release htmlURL. But note the standing tension: these are hardening/polish on an
  already-solid spine — the genuine gap is SUSTAINED DOGFOODING, which only the user can start.
  WATCH: signal-trust (DOWNGRADED from PAID — re-audit owed on the full inbox); pulse-honesty;
  idle-footprint (freshness adds no timer); color-doctrine (now fully consumed). Honor
  focus-non-theft + the classic-PAT WALL.
  ── (superseded) iter 32 — TWO review rounds have hardened the load-bearing spine (pagination, change-keys,
  selfResolved, GraphQL honesty, rate-limit, token-shape, a11y labels, evidence redaction). The
  code is now in genuinely good shape AND fetches the WHOLE inbox. The #1 priority is UNCHANGED
  and now both more answerable and more urgent: RE-RUN the reveal-suppressed trust audit on the
  FULL inbox (272 threads, ~222 suppressed) — the iter-20 'it holds' verdict is invalid (page 1
  only). That is the bridge to the standing 'genuinely, what's the state' answer: sustained
  dogfooding (install as a daily driver, log misses/false-alarms over days) still hasn't started,
  and there's now far more to validate. Offer the user: surface the full suppressed set to audit +
  set up the daily-driver run. DEFERRED engineering (all noted in iter-32 last_action): island
  scroll, full pulse pagination, async enrichment, EVIDENCE_JSON extract-to-testable, GHE htmlURL,
  a11y keyboard nav. WATCH: signal-trust (DOWNGRADED from PAID — re-audit owed); pulse-honesty
  (now also guards GraphQL partial-failures); idle-footprint; color-doctrine. Honor focus-non-theft
  + the classic-PAT WALL.
  ── (superseded) iter 31 — the review round CLOSED 10 verified findings, but it RE-OPENED the moat question:
  the signal-trust-budget was marked PAID (iter 20) on the user's 'it holds' audit — but that
  audit ran against PAGE 1 ONLY (50 of 272 threads). The audit is INVALID; ~57 action-required
  items now surface (was ≤50 total fetched). #1 NEXT: re-run the reveal-suppressed trust audit
  on the FULL inbox (272 threads, 215 suppressed) — the user must re-confirm misses ≤ budget on
  the complete set. This is also the bridge to the standing 'genuinely, what's the state' answer:
  the product is built + now fetches the WHOLE inbox, but sustained dogfooding (install as a
  daily driver, log misses/false-alarms over days) still hasn't happened — and now there's far
  more to validate. DEFERRED follow-ups (real): full background enrichment (F6 mitigated, not
  solved); runtime-403 setup-failure classification; the doctrine's caution-freshness indicator.
  Reversible defaults unchanged. WATCH: signal-trust (now DOWNGRADED from PAID — re-audit on the
  full inbox); pulse-honesty; idle-footprint (pagination adds requests only on a real change, not
  per-poll — 304s still free); the new color-doctrine pressure. Honor focus-non-theft + the
  classic-PAT WALL.
  ── (superseded) iter 30 — the COLOR DOCTRINE is ratified + applied; it answered the user's three open color
  questions (radar mono+critical YES; green=ready-not-alive; yellow GONE). REMAINING OPEN
  (user steer / dogfood, none blocking): (a) the doctrine's deferred FOLLOW-UPS: a `caution`
  freshness/staleness indicator on the H2 header (the only sanctioned new color use — needs a
  real elapsed-time/poll-fail signal first), and an a11y outline-ring shape-cue on the critical
  glyph (defer unless dogfood needs it); (b) WATCH the doctrine's own counterargument — if H1
  ever runs long enough that mono slows time-to-first-correct-row, add ONE emphasis tier, never
  the heat ladder back; (c) H1-vs-H2 pill emphasis (user leaning H1-primary); (d) split
  `waiting` human-vs-compute (dogfood); (e) "see Your PRs" cross-link (deferred); (f) light/dark
  adaptive token sets (deferred — NSColor dynamicProvider). The product is rich + proven; the
  open surface is polish/dogfood, not core. Reversible defaults: Color theme default, H1-primary
  pill, policy-b (measured free), author-as-is (State-vs-Event), C gauge, ordinary-glyph=
  inkSecondary, critical-first sort. WATCH: pulse-honesty; signal-trust (self-demotion
  landmine); idle-footprint (grain static, 0.3%); native-feel; the new color-doctrine pressure.
  Honor focus-non-theft + classic-PAT WALL.

# BOTH preloop gates closed. Loop FULLY unblocked. user_recommendation (soft, NOT a
# gate/halt): re-issue the classic PAT with scope=notifications,repo to unblock
# private-repo enrichment + #11 precision verification on real work threads.
# consult 002 due ~iter 11 (sooner once a POPULATED island screenshot exists).
# Route the next consult via /agentify (user preference).

user_recommendations:
  - id: pat-repo-scope
    iter: 5
    owner: user
    soft: true                         # not a phase gate; loop is NOT blocked
    status: satisfied                  # user added `repo` scope 2026-06-16
    recommendation: "Re-issue the classic PAT with scope=notifications,repo (same Keychain item githud.github.pat). Without `repo`, private-repo comment content 404s, so the bot/self-activity precision of the action radar (RUBRIC #11) can't be verified on your real (private) work threads."
    evidence: "loop/evidence/live-probe-5.json (skipped_private_no_repo_scope=7, has_repo_scope=false)"
    satisfied_evidence: "loop/evidence/live-probe-6.json — scopes=notifications,repo; enrichment now covers private repos (enriched=10, skipped_private=0); bot-awareness VERIFIED on real data (demoted=1; radar 13→12). RUBRIC #11 real-data bot-demotion now PROVEN."
    blocks: "RESOLVED. (Was: private-repo enrichment + #11 real-data precision verification.)"
  - id: display-awake
    iter: 7
    owner: user
    soft: true                         # instantly resolvable; loop can do non-visual work meanwhile
    status: satisfied                  # user woke the display 2026-06-16
    recommendation: "Wake the Mac display (it was asleep — CGGetActiveDisplayList=0)."
    note: "iter-8 finding: the width bug was NOT caused by display sleep — it was the content's Auto Layout pinning the window width. Fixed (size empty panel first). With the display awake, the populated island renders 520×173 and visual proof + blind read both ran."
    satisfied_evidence: "loop/evidence/hover-expanded-normal-desktop-8.manifest.json (status=captured, pixel_live=true)"
  - id: screen-unlock
    iter: 9
    owner: user
    soft: true
    status: satisfied                  # user unlocked 2026-06-16; iter-10 visual work ran
    recommendation: "Unlock the Mac screen (and ideally disable auto-lock for sustained visual work)."
    note: "Resolved — the badge-fixed island was re-captured + the 2nd blind read ran (consult 003). caffeinate -d keeps the display awake during captures; the lock-guard prevents lock-screen false-greens."
    satisfied_evidence: "loop/evidence/hover-expanded-normal-desktop-10.manifest.json (status=captured, pixel_live=true)"

halt_cause: null
halt_scan: null

# ---- ramp stages (evaluator maturity) ----
ramp_stages:
  stage1_command_discovery: closed      # swift build / build-app.sh / test.sh / validate.sh all return 0
  stage2_baseline_snapshot: closed      # first green state recorded (this entry + evidence_index)
  stage3_smoke_validator: closed        # validate.sh: build→launch→CGWindowList assert→kill, seconds
  stage4_discriminative: partial        # iter 0: no-window + focus-theft false greens. iter 2: classification discriminator. iter 3: pixel-liveness discriminator. iter 4: LIVE notification-diff landed (real /notifications → classifier, conditional 304). REMAINING: Spaces/full-screen capture discriminator (buildable now; screen-rec granted).
  stage5_traces: closed                 # failures + states emit queryable artifacts under loop/evidence/ + index rows
  ramp_exit: near                       # only the Spaces/full-screen discriminator remains for T3

# ---- evidence index (signal hierarchy tier-2, machine-derived) ----
evidence_index:
  - loop/evidence/validate-window-0.json          # iter 0 — CGWindowList: island on screen, collapsed, within_screen
  - loop/evidence/idle-normal-desktop-0.manifest.json  # iter 0 — native manifest: frontmost_unchanged, idle_cpu 0.1, status skipped (no screen-rec)
  - loop/evidence/classifier-metrics-2.txt        # iter 2 — confusion TP=7 FP=0 FN=0 TN=9, precision/recall 1.00 on the labeled fixture (RUBRIC #4 + #11)
  - Tests/Fixtures/notifications.json             # iter 2 — labeled ground-truth fixture (16 threads, human PR-author/reviewer labels)
  - Tests/GithudCoreTests/main.swift              # iter 2 — the classifier evidence harness (reproducible via scripts/test.sh)
  - loop/evidence/idle-normal-desktop-3.manifest.json  # iter 3 — FIRST REAL visual proof: status=captured, pixel_live=true, png_sha256, frontmost_unchanged, idle_cpu 0.1
  - loop/evidence/live-probe-4.json                # iter 4 — LIVE spine: GET /notifications 200 (50 threads, 14 action-req), conditional 304 (RUBRIC #8 proven), scopes=notifications. Redacted (counts/reasons/headers only). Caveat: author-thread precision unverified (no enrichment).
  - loop/evidence/live-probe-5.json                # iter 5 — enrichment: public enriched=3 (0 err), private skipped=7 (notifications-only PAT 404s comment content). #11 precision on private threads UNVERIFIED → needs repo-scoped PAT (user_recommendation pat-repo-scope).
  - loop/evidence/live-probe-6.json                # iter 6 — THE MOAT ON REAL DATA: 50 raw → 13 naive → 3 genuinely action-required (enriched=10, demoted=10 = bot + self-activity). repo scope live; ci_activity/state_change suppressed; review_requested surfaced; conditional 304 proven. Strong #4/#11 evidence (not yet scored).
  - loop/evidence/hover-expanded-normal-desktop-8.manifest.json  # iter 8 — FIRST POPULATED-ISLAND visual proof: status=captured, pixel_live=true, size_class=expanded (520×173), frontmost_unchanged, variance 680/64 colors. Blind read (consult 002): function matched, native-feel = "competent third-party" not first-party → #1 caps ~2-3.
  - loop/evidence/hover-expanded-normal-desktop-9.manifest.json  # iter 9 — native-feel refined (SF Symbols + badge); manifest HONESTLY status=skipped reason=screen_locked (lock-guard caught it).
  - loop/evidence/hover-expanded-normal-desktop-10.manifest.json # iter 10 — REFINED island (popover material + hairline edge + badge fix + restrained type): status=captured, pixel_live=true, expanded. 2nd blind read (consult 003): function matches; native-feel "competent third-party" → #1 settles ~3 (passing table-stakes).
  - loop/evidence/live-app-11.json                 # iter 11 — LIVE app end-to-end (githud, no args): "3 action-required (changed) — next poll 60s", island expanded 520×159 (real radar), idle_cpu 0.0 between polls. RUBRIC #8 + the spine in the real app. Redacted (no titles).
  - loop/evidence/hover-expanded-normal-desktop-21.manifest.json # iter 21 — island with comment-preview excerpts (dim 1-line per comment-bearing row); pixel_live; #6 inspector depth.
  - loop/evidence/hover-expanded-normal-desktop-13.manifest.json # iter 13 — island after click-to-open + hover wiring: pixel_live=true, expanded, no regression. Rows clickable (htmlURL tested) → Open-on-GitHub.
  - loop/evidence/idle-normal-desktop-25.manifest.json # iter 25 — H2 ambient pulse: BOTH lanes render (520×457, "Needs you" + "Your PRs"), status=captured, pixel_live=true (241 colors, variance 558), idle_cpu 0.1, frontmost_unchanged. Live pulse PROVEN via probe: 16 open PRs classified (blocked/ready/waiting/draft) over GraphQL on the real PAT; evidence histogram redacted (no titles/repos). docs/plans/2026-06-16-001-feat-ambient-pr-pulse-plan.md is the build plan.
  - loop/evidence/idle-normal-desktop-26.manifest.json  # iter 26 — taxonomy v2, DRAFTS OFF (default): "Your PRs" shows only non-drafts, no Drafts section; "Needs you" shows the codecov bot mention now surfacing (policy-b). pixel_live=true.
  - loop/evidence/idle-normal-desktop-261.manifest.json # iter 26 — taxonomy v2, DRAFTS ON (--show-drafts): a separate "Drafts" section appears (WIP #902 "no checks · draft", #903 "CI running · review required · draft"). pixel_live=true. docs/plans/2026-06-18-001-feat-signal-taxonomy-hardening-plan.md is the build plan. Live probe: 14 PRs / 5 drafts hidden by default; action_required 11 = ALL genuine (6 review_requested + 5 author); policy-b cost MEASURED 0 (radar_automation meter, iter 27).
  - loop/evidence/idle-normal-desktop-281..285.manifest.json # iter 28 — THEME SYSTEM, all 5 themes (281 color / 282 geist-mono / 283 github / 284 dracula / 285 nord) over the fixtures via --theme: each status=captured, pixel_live=true, 520×457. Geist (grain on) idle_cpu 0.3% vs 0.1-0.2% others → static grain ~0 idle (idle-footprint holds). Color theme = original look (parity). docs/plans/2026-06-19-001-feat-theme-system-plan.md is the build plan.
  - loop/evidence/idle-normal-desktop-286..288.manifest.json # iter 29 — +3 themes (286 tokyo-night / 287 catppuccin / 288 gruvbox), pixel_live, captured. 8 themes total.
  - loop/evidence/idle-normal-desktop-290.manifest.json # iter 29 — SEGMENTED caught-up gauge (the /ui-sketch C pick): collapsed pill "✓3 ⚠3" (88×36, pixel_live) — ready-leads + blocked count-matched, drafts excluded. (291 = same in Dracula.)
  - loop/evidence/idle-normal-desktop-292.manifest.json # iter 29 — SOLARIZED LIGHT (the lone light theme): cream surface, dark ink, blue badge, Solarized red/green accents, black-alpha hover visible. status=captured, pixel_live, 520×457. Proves the light surface + dark-on-light inversion works (hoverFill token flip).
  - loop/evidence/idle-normal-desktop-293..294.manifest.json # iter 29 — Dracula FIXED (dim text → comment purple #6272A4, reads distinctly Dracula now) + Solarized DARK (teal-navy #002b36, the dark half of the Solarized pair). Both captured, pixel_live. (Gruvbox swapped out; 288 manifest is the retired Gruvbox render.)
  - loop/evidence/idle-normal-desktop-300..302.manifest.json # iter 30 — COLOR DOCTRINE applied, expanded island, 3 themes (300 Color 66 colors / 301 GitHub 73 / 302 Solarized-Light 71), all status=captured pixel_live within_screen, 520×457, frontmost_unchanged, idle 0.1-0.2. Blind read of 300: the security_alert renders as the LONE RED shield at the TOP of the radar (critical-first sort live), every other reason-glyph muted ink; H2 ready=green / blocked=red; ZERO yellow anywhere (waiting now ink). Doctrine renders correctly. (PNGs gitignored — manifest is the proof.)
  - loop/evidence/idle-normal-desktop-303.manifest.json # iter 30 — collapsed CRITICAL pill (--collapsed, Color, notifications fixture): 60×36 rows-present pill (security shield + "7"), status=captured pixel_live within_screen. The critical fact crosses to the collapsed island (doctrine principle 4) — the pill recruits the eye only because a real emergency is present.
  - loop/evidence/idle-normal-desktop-330..331.manifest.json # iter 33 — FRESHNESS caution cue (--stale): 330 expanded shows the amber "Reconnecting — last update 8m ago" banner atop the island (520×479, +22 for the banner); 331 collapsed shows the caution clock prepended to the pill (79×36, +19). Both status=captured pixel_live. Without --stale, no freshness chrome (normal operation is quiet) — confirmed against the iter-30 captures (300-303, no banner). The doctrine's caution token now has a live consumer.
  - loop/evidence/live-probe-32.json # iter 32 — REVIEW ROUND 2: verifies the GithudApp-layer fixes on the live spine (272 threads post-change, 304 fires, bounded enrichment clean enriched=26, EVIDENCE_JSON oauth_scopes-free per review #12). The app-layer changes have no unit test target → probe is the verification.
  - loop/evidence/live-probe-31.json # iter 31 — REVIEW ROUND, the moat-critical proof: AFTER the pagination fix (review F1) the SAME live account returns thread_count=272 (was 50-capped page-1-only) → the old code silently dropped 222 notifications (82%), incl. action-required review_requested/mention/author on pages 2-6. 57 action-required post-enrich; 304 conditional STILL fires (poll discipline intact); rate 4943/5000; pulse 20 PRs. Redacted (counts/histogram only). This INVALIDATES the iter-20 'it holds' audit (it saw page 1 only) → signal-trust-budget downgraded from PAID, re-audit owed on the full inbox.
  # loop/evidence/*.png now REAL captures (screen-rec granted) but GITIGNORED (privacy — they image the desktop). The committed manifest (sha + pixel_stats, no image) is the proof.

# ---- alignment reviews (invariant 7 — reversible taste calls, logged) ----
alignment_reviews:
  - id: swift5-language-mode
    problem: "Swift 6 strict-concurrency mode floods an AppKit scaffold with isolation errors"
    options: "[swift6 mode + @MainActor everywhere now, swift5 mode, defer]"
    chosen: "swift-tools 5.9 / Swift 5 language mode for the scaffold"
    alignment_cost: "no compile-time concurrency safety yet"
    rollback_trigger: "bump to Swift 6 mode when the URLSession networking spine lands (it earns the strictness)"
    review_q: "OK to defer strict concurrency until the client lands?"
  - id: zero-dep-test-runner
    problem: "XCTest + swift-testing both require full Xcode; stack is CLT-only"
    options: "[swift-testing as a network SwiftPM dep, hand-rolled zero-dep executable runner]"
    chosen: "zero-dep executable runner (Tests/GithudCoreTests) via scripts/test.sh"
    alignment_cost: "no XCTest tooling (assertions, parallelism, fixtures) — hand-rolled expect()"
    rollback_trigger: "adopt full Xcode → swap to XCTest/Testing"
    review_q: "hand-rolled runner acceptable vs pulling swift-testing over the network?"
  - id: vibrancy-direct-nsvisualeffectview
    problem: "prompt said VisualEffectHostingView; cleaner to use NSVisualEffectView directly as contentView"
    options: "[NSHostingView-wrapped, NSVisualEffectView as panel.contentView]"
    chosen: "NSVisualEffectView directly (honors native-feel pressure; SwiftUI lands inside it later)"
    alignment_cost: "naming drift from the prompt's suggested type name"
    rollback_trigger: "if SwiftUI content needs the host wrapper, reintroduce a hosting view inside the island"
    review_q: "fine to put SwiftUI inside the NSVisualEffectView later rather than wrap it?"
  - id: bundle-id-and-placement
    problem: "need a bundle id + an island screen position"
    options: "[various]"
    chosen: "id me.provi.githud; island top-center under the menu bar (Dynamic-Island placement), collapsed 280×42"
    alignment_cost: "placement/id are guesses pending user taste"
    rollback_trigger: "user reframe on placement; or notch collision on a notched Mac (untested)"
    review_q: "top-center-under-menu-bar the right home, or top-right near the status item?"
  # iter 1 — consult-001 product-direction defaults (judgment default; reversible; NOT escalated)
  - id: first-archetype
    problem: "consult: signal rules differ radically by user archetype — pick one"
    options: "[PR authors, reviewers, maintainers, managers, all-at-once]"
    chosen: "PR authors + reviewers (the events 'review requested' / 'comment on your PR' are highest-signal + most time-sensitive; matches the verbatim intent)"
    alignment_cost: "maintainer/manager signals (e.g. triage queues) under-served at first"
    rollback_trigger: "user is primarily a maintainer/manager, or the trust experiment shows the archetype's signals don't dominate"
    review_q: "are you primarily a PR author/reviewer, or a maintainer/manager?"
  - id: action-required-only
    problem: "consult: be explicitly action-required-only, or include FYI/stars/forks?"
    options: "[action-required only, action-required + FYI tier, everything]"
    chosen: "action-required ONLY in the core (mention/review-req/your-PR comment/assign); FYI + stars/forks OUT of the core radar"
    alignment_cost: "loses the 'feed' flavor of the original intent's 'stars and forks'"
    rollback_trigger: "user wants an ambient FYI tier; revisit as a separate, visually-subordinate lane (not the radar)"
    review_q: "is the core strictly 'needs your action', with stars/forks as an optional separate lane?"
  - id: false-alarm-budget
    problem: "consult: the daily false-alarm budget dictates the whole classifier — 0 / 1-2 / 5+?"
    options: "[0 (unrealistic on lossy input), 1-2, 5+]"
    chosen: "1-2/day initial target (0 impossible given threads-not-events lossiness; 5+ erodes trust)"
    alignment_cost: "tuning the classifier to ≤1-2 may raise MISS rate — must watch both"
    rollback_trigger: "trust experiment shows users tolerate more, or demand 0 and accept more misses"
    review_q: "is 1-2 false alarms/day an acceptable trust budget, watching misses in tandem?"
  # iter 16 — consult-004 direction defaults (judgment default; reversible; surfaced to user at the look gate)
  - id: consult004-direction-defaults
    problem: "consult 004 raised target-direction Qs that are the user's call but defaultable"
    options: "[wait for user, pick reversible defaults + continue]"
    chosen: "defaults: (1) miss-tolerance = bias NEVER-MISS (recall) [already the classifier design]; (2) which-moment = always-on ambient [current]; (3) H1 action-radar stays the target, H2 ambient = conditional skin [current INTENT]; (4) assume notifications NOT already in Slack/email (githud = primary surface) until told otherwise"
    user_resolved:
      - "iter 25 — time-to-awareness = AMBIENT (no push notifications). USER-CONFIRMED (was a default). Stay glanceable, not push."
      - "iter 25 — H1-vs-H2: user is evaluating (asked 'what is ambient pulse?'); explained; awaiting their pick."
    alignment_cost: "if the user wants quieter / EOD-only / H2-pulse / Slack-overlay, some of iter 12-16 reorients"
    rollback_trigger: "user answers any of the look-gate Qs differently → first-class reframe (invariant 3), quarantine affected work"
    review_q: "miss tolerance? Slack/email overlap? moment to win? H1 vs H2 now that you've seen it?"

consults:
  log: loop/creative-consults.md
  cadence_iters: 10
  last_consult_iter: 30                  # consult 008 (/agentify GPT-Pro: color doctrine — ratified + applied iter 30)
  next_consult_due_iter: 40              # creative-direction cadence ~10
  pal_continuation_id: "4cdb7c48-bf33-4b83-81c3-e74601da798a"
  consult_003_followup: "MET (iter 10 material pass; accepted competent table-stakes)"
  consult_004_followup: "MET this pass — reframed metric to recall/misses (INTENT+RUBRIC #11) + built the reveal-suppressed trust test"
  consult_006: "iter 26 — 3-model /second-opinion (GPT-5.2+Gemini3.1Pro+Grok4.3) on the two-lane taxonomy → shipped taxonomy-hardening v2 (security_alert↑, policy-b, CI honesty, drafts subsection)"
  consult_007: "iter 27 — 3-model /second-opinion on author-tier precision → UNANIMOUS REJECT (miss-risk + premature). Keeper: State-vs-Event (H1 events ⊥ H2 state). Decision: leave author as-is. No build."
  consult_008: "iter 30 — /agentify GPT-Pro extended-pro: the COLOR DOCTRINE (shape=what/order=priority/color=changed-next-move; ink by default). APPLIED same iter (radar mono+critical+critical-first sort; green=ready-not-alive; yellow removed). Caught a live sort bug (security_alert 92 < review_requested 95). Logged in creative-consults.md (Consult 008) + pressure row color-doctrine."

# ---- pressure (source of truth; PRESSURE.md is the render) ----
pressure_objects:
  - id: focus-non-theft
    source: authored
    scope: "HUD panel + window event handling (Sources/GithudApp/HUDPanel.swift)"
    mode: burden
    strength: high
    satisfied_by: "tier-2 — screen recording: typing/clicking in another app continues uninterrupted while HUD visible + expanding; HUDPanel.canBecomeKey==false; orderFrontRegardless (not makeKeyAndOrderFront)"
    on_violation: owes_proof
    expires: "iter 60 or when HUD panel architecture stabilizes (re-review)"
    status: active
  - id: idle-footprint
    source: authored
    scope: "animation + timers — whole-app idle behavior"
    mode: burden
    strength: medium
    satisfied_by: "tier-2 — ~0% CPU when idle BETWEEN polls (ps idle_cpu 0.0, live-app-11); no per-frame / UI-animation timers / CADisplayLink (grep: the only timer is PollScheduler's). REFINED iter 11: the ~60s conditional /notifications poll timer is the app's CORE function (304s free; dormant + 0% CPU between polls; updates island on change only) — justified, NOT idle churn."
    on_violation: owes_proof
    expires: "iter 80"
    status: active
  - id: native-feel
    source: authored
    scope: "visual + interaction design — the core value"
    mode: preference
    strength: high
    satisfied_by: "tier-1 — blind comprehension read (invariant-8 channel): 'reads as a polished Mac-native overlay, not a web rectangle'; vibrancy via AppKit NSVisualEffectView, not SwiftUI .material"
    on_violation: owes_explanation
    expires: "iter 100 (re-review with INTENT)"
    status: active
  - id: notifications-classic-pat
    source: authored
    scope: "GitHub auth / Notifications API client (Sources/GitHubClient)"
    mode: constraint
    strength: high
    satisfied_by: "tier-2 — inbox path authenticates with a CLASSIC PAT (notifications scope); GPT-Pro-verified GitHub fact that /notifications 403s/empties on fine-grained PAT / App tokens"
    on_violation: blocks
    expires: "reopen if GitHub adds fine-grained / App-token support to the Notifications API"
    status: active
  - id: test-substrate-clt-only
    source: backpressure
    scope: "test framework choice (Tests/, the test command)"
    mode: burden
    strength: medium
    satisfied_by: "tier-2 — scripts/test.sh exits 0 via `swift run GithudCoreTests` (zero-dep executable runner). XCTest AND swift-testing are both absent under CommandLineTools (iter-0 probe: `swiftc -typecheck` → 'no such module Testing' / 'no such module XCTest'); reaching for them again wastes a pass."
    on_violation: owes_proof
    expires: "reopen if full Xcode is adopted (then swap to XCTest/Testing)"
    status: active
  - id: signal-trust-budget
    source: consult                     # consult 001 — the existential axis
    scope: "what the HUD surfaces — the classifier + any new feed source"
    mode: burden
    strength: high
    satisfied_by: "tier-2/1 — any surfaced item carries an action-required classification; classifier precision keeps false alarms ≤ 1-2/day on a labeled fixture (now) and in the trust experiment (PAT-gated). Adding any FYI/stars/forks source owes proof it doesn't blow the budget. NOTE (iter 31): the precision side still holds, but the RECALL/never-miss side is NO LONGER PAID — the iter-20 'it holds' audit ran on page 1 only (50 of 272 threads); the pagination MISS (review F1) means action-required items were silently dropped. Re-audit owed on the FULL inbox now that all pages are fetched."
    on_violation: owes_proof
    expires: "iter 60 or when the trust experiment runs on real data (re-review the budget then)"
    status: active
  - id: attention-non-theft
    source: consult                     # consult 001 — focus-non-theft is necessary but insufficient
    scope: "motion / animation / novelty / persistent on-screen presence"
    mode: burden
    strength: high
    satisfied_by: "tier-2 — no autonomous motion at idle (grep: no idle timers/animation) AND any motion maps 1:1 to a real action-required change (screen recording, PAT+screen-rec-gated). Distinct from idle-footprint (CPU) and focus-non-theft (activation): this is perceptual restraint."
    on_violation: owes_proof
    expires: "iter 100 (re-review with INTENT/glance-ability)"
    status: active
  - id: keychain-headless-prompt
    source: backpressure                # iter 4 — ad-hoc binary blocks on the Keychain GUI prompt
    scope: "reading the PAT from a HEADLESS run (probe / CI / loop), not the GUI app"
    mode: burden
    strength: medium
    satisfied_by: "tier-2 — headless token reads use GITHUD_PAT (supplied via the already-authorized `security` CLI); the GUI app reads Keychain directly (one-time Always-Allow). An ad-hoc-signed binary calling SecItemCopyMatching headless blocks on a GUI prompt forever (iter-4: probe hung, no output, killed)."
    on_violation: owes_proof
    expires: "reopen if the app gets a stable Developer-ID signature (then Keychain ACL can pin it; headless prompt goes away)"
    status: active
  - id: conditional-polling-no-cache
    source: backpressure                # iter 4 — URLCache swallowed the 304
    scope: "the HTTP client for conditional polling (GitHubClient)"
    mode: burden
    strength: medium
    satisfied_by: "tier-2 — the client uses an ephemeral/no-cache URLSession so conditional 304s reach our code (proven: live probe 200→304). URLSession.shared's URLCache transparently revalidates + serves a cached 200, hiding the 304 and defeating RUBRIC #8."
    on_violation: owes_proof
    expires: "iter 80 (re-review when the polling scheduler stabilizes)"
    status: active
  - id: surfacing-honors-user-choice
    source: user                          # iter-20 reframe
    scope: "what the radar surfaces — SurfacePreferences"
    mode: burden
    strength: medium
    satisfied_by: "tier-2 — surfacing respects the user's enabled-reason set (default auto), persisted; bot/self demotion still applies within it. Verified: custom pref (review_requested only) → 1 vs auto → 3."
    on_violation: owes_proof
    expires: "iter 120 (re-review when surfacing UX stabilizes)"
    status: active
  - id: pulse-honesty
    source: consult                       # iter-25 — H2 pulse; same moat (trust) as signal-trust, new surface
    scope: "the H2 pulse lane — PullRequestPulse state mapping + what the 'Your PRs' lane/pill render"
    mode: burden
    strength: high
    satisfied_by: "tier-2/1 — the pulse NEVER fabricates a green/ready state it can't back: null statusCheckRollup → CIState.none (not .passing), UNKNOWN/null mergeable → .unknown (NEVER .ready), null reviewDecision → .none (not approved); .ready requires merge==mergeable explicitly. Proven per lattice cell (164 checks) + live (probe: blocked/ready/waiting/draft all real). A faked/laggy pulse erodes trust exactly like a missed mention (consult 004). The subtitle always NAMES the salient members so the rollup glyph is never opaque."
    on_violation: owes_proof
    expires: "iter 80 or when the pulse data model changes (re-audit the honesty mappers)"
    status: active
  - id: color-doctrine
    source: consult                       # iter-30 — consult 008 (GPT-Pro); the palette serving the trust moat
    scope: "all semantic color in the island — Theme.radarGlyphColor / pulseGlyph + any new colored surface"
    mode: burden
    strength: high
    satisfied_by: "tier-1/2 — color is spent ONLY on a changed next-move: danger (intervene/critical), success (action unlocked), caution (the READING is degraded). Shape carries kind, sort carries rank, accent is chrome (never status). The ONE reserved H1 critical is security_alert (sorted critical-first so its red is never stranded). No green-for-alive, no yellow-for-ordinary-progress. A11y LAW: replace every semantic color with the same gray and the full meaning must survive (shape + VoiceOver). Any NEW use of color owes proof it marks decision-changing info, not rank/identity/liveness. Proven: 254 checks (critical-first sort + isCritical) + visual proof 300-303 + blind read (lone red shield, zero yellow)."
    on_violation: owes_proof
    expires: "iter 100 (re-review with INTENT; or sooner if dogfood shows mono slows time-to-first-correct-row → add ONE emphasis tier, never the heat ladder)"
    status: active

pressure_ledger:
  - iter: 0
    transition: "added"
    row: test-substrate-clt-only
    note: "backpressure from a failed command: `swift test` → 'no tests found' then XCTest/Testing 'no such module' under CLT. Softest justified mode = burden (steers test work to the zero-dep runner)."
    evidence: "iter-0 swiftc -typecheck probe output; swift test error"
  - iter: 0
    transition: "evidence-accrued (stays active)"
    row: focus-non-theft
    note: "PARTIAL pay: structural guarantees in code (HUDPanel canBecomeKey/Main=false; .nonactivatingPanel; orderFrontRegardless, no makeKeyAndOrderFront) + manifest frontmost_unchanged:true on show. NOT retired: the pre-registered channel (screen recording of uninterrupted typing while expanding) needs screen_recording_permission. Stays active."
    evidence: "Sources/GithudApp/HUDPanel.swift:11-12; HUDPanelController.swift:26,53; loop/evidence/idle-normal-desktop-0.manifest.json (frontmost_unchanged)"
  - iter: 0
    transition: "currently-satisfied (stays active)"
    row: idle-footprint
    note: "Both halves met: top/ps idle_cpu 0.1 (~0%) + grep shows zero Timer/CADisplayLink/animator in Sources. Kept active as an ongoing burden — future animation must re-prove."
    evidence: "loop/evidence/idle-normal-desktop-0.manifest.json (idle_cpu 0.1); grep -niE 'Timer|CADisplayLink|animator' Sources/ → none"
  - iter: 1
    transition: "added"
    row: signal-trust-budget
    note: "consult 001 named signal/trust the only existential axis. Burden: any surfaced item owes an action-required classification; false alarms ≤ 1-2/day."
    evidence: "loop/creative-consults.md consult 001 verdict Q4/Q5"
  - iter: 1
    transition: "added"
    row: attention-non-theft
    note: "consult 001: focus-non-theft ('don't activate') is necessary but insufficient — a non-activating panel can still be an attention vampire. Burden on motion/novelty/persistent presence."
    evidence: "loop/creative-consults.md consult 001 verdict Q4"
  - iter: 2
    transition: "evidence-accrued (stays active)"
    row: signal-trust-budget
    note: "PARTIAL pay: classifier precision=1.00 / recall=1.00 (FP=0 within the ≤1 budget proxy; zero misses) on the 16-thread labeled fixture. NOT retired — the pre-registered channel is the LIVE trust experiment (real false-alarm rate ≤ 1-2/day), PAT-gated. Stays active."
    evidence: "loop/evidence/classifier-metrics-2.txt; Tests/GithudCoreTests/main.swift"
  - iter: 3
    transition: "evidence-accrued (stays active — WALL)"
    row: notifications-classic-pat
    note: "LIVE validation: the user's CLASSIC PAT authenticates GET /notifications (HTTP 200, x-oauth-scopes=notifications, x-poll-interval=60). The WALL is now satisfied on a live tier-2 signal, not just code intent / GPT-Pro fact. Re-tested: reopen=GitHub adds fine-grained support → no change → wall STANDS (still forbids fine-grained / App tokens)."
    evidence: "phase_gates.github_classic_pat_ready.exit_evidence (user, 2026-06-16)"
  - iter: 3
    transition: "channel-opened (stays active)"
    row: focus-non-theft
    note: "screen_recording_permission GRANTED → the pre-registered proof channel (screen recording of uninterrupted typing while the HUD expands) is now ACHIEVABLE. Not yet paid (no expand interaction exists), but unblocked. frontmost_unchanged + idle_cpu 0.1 re-confirmed in the iter-3 real manifest."
    evidence: "loop/evidence/idle-normal-desktop-3.manifest.json"
  - iter: 4
    transition: "added"
    row: keychain-headless-prompt
    note: "backpressure: `githud probe` hung headless (no output, killed) — ad-hoc binary blocked on the Keychain GUI prompt. Resolved: probe reads GITHUD_PAT via the authorized `security` CLI; GUI app uses Keychain directly."
    evidence: "iter-4 probe hang (pid 4106, exit 143); `security find-generic-password` read OK"
  - iter: 4
    transition: "added"
    row: conditional-polling-no-cache
    note: "backpressure: probe's conditional re-GET returned 200 not 304 — URLSession.shared URLCache swallowed it. Resolved: GitHubClient uses an ephemeral no-cache session → live 304 surfaced."
    evidence: "loop/evidence/live-probe-4.json (second.status 200→304 after fix); curl control showed live 304"
  - iter: 4
    transition: "evidence-accrued — gap found (stays active)"
    row: signal-trust-budget
    note: "FIRST LIVE data point: 14/50 surfaced action-required, but 13 'author' threads are UNVERIFIED — base /notifications lacks the latest-comment author, so bot/CI on your own PRs can't be demoted. Real-data precision is therefore NOT yet earned; enrichment is the iter-5 fix. Recall looks good (review_requested surfaced; ci_activity=23 + state_change=13 suppressed)."
    evidence: "loop/evidence/live-probe-4.json (reason_histogram, precision caveat)"
  - iter: 4
    transition: "evidence-accrued (stays active — WALL)"
    row: notifications-classic-pat
    note: "Re-validated LIVE again via the probe: oauth_scopes=notifications on a 200. WALL re-tested: reopen=fine-grained support → no change → STANDS."
    evidence: "loop/evidence/live-probe-4.json (oauth_scopes)"
  - iter: 5
    transition: "evidence-accrued — still unverified (stays active)"
    row: signal-trust-budget
    note: "Enrichment machinery built + scope-aware. Real-data precision STILL unverified: only 3 PUBLIC author threads were checkable (all human, demoted 0); the 7 PRIVATE ones 404 without the `repo` scope. So the budget is NOT yet paid on real data — blocked on user_recommendation pat-repo-scope + self-activity demotion (iter 6). Stays active."
    evidence: "loop/evidence/live-probe-5.json (enriched=3, skipped_private=7, demoted=0)"
  - iter: 5
    transition: "evidence-accrued (stays active — WALL)"
    row: notifications-classic-pat
    note: "Enrichment GETs reuse the SAME classic PAT Bearer; oauth_scopes=notifications confirmed. WALL re-tested: no reopen → STANDS."
    evidence: "loop/evidence/live-probe-5.json"
  - iter: 6
    transition: "evidence-accrued — strong, near-paid (stays active)"
    row: signal-trust-budget
    note: "MAJOR real-data evidence: self-activity demotion + enrichment cut the radar 13 → 3 on live data (demoted 10 = bot + own-latest-comment). The false-alarm risk the consult flagged is now structurally addressed (bot + self + firehose all suppressed; review_requested not missed). NOT marked paid: 'paid' needs the PRE-REGISTERED channel (the multi-day trust experiment: user-logged false-alarms/misses ≤ 1-2/day), and the 3 survivors aren't user-validated. Stays active; budget is close."
    evidence: "loop/evidence/live-probe-6.json (action_required 13→3, demoted=10)"
  - iter: 6
    transition: "evidence-accrued (stays active — WALL)"
    row: notifications-classic-pat
    note: "GET /user + enrichment all via the classic PAT (scopes notifications,repo). WALL re-tested: reopen=fine-grained support → no change → STANDS."
    evidence: "loop/evidence/live-probe-6.json (oauth_scopes)"
  - iter: 8
    transition: "owes-proof (stays active — NOT satisfied)"
    row: native-feel
    note: "First blind read of the populated island (consult 002): the pre-registered channel (blind comprehension 'polished Mac-native, not a web rectangle') returned 'competent THIRD-PARTY, not first-party' — flat vibrancy, web-list spacing, missing SF Symbols/row anatomy. So native-feel is NOT paid; it owes the iter-9 refinement pass. attention-non-theft + focus-non-theft partially evidenced (manifest frontmost_unchanged=true; static render)."
    evidence: "loop/evidence/hover-expanded-normal-desktop-8.manifest.json; creative-consults.md consult 002"
  - iter: 9
    transition: "refined — re-proof pending (stays active)"
    row: native-feel
    note: "Acted on consult 002: leading SF Symbols per reason + header count badge + tighter metrics. SF Symbols confirmed in a brief-unlock capture; badge stretch fixed. Re-proof (2nd blind read 'no longer third-party') BLOCKED — screen locked. Stays active/owes-proof until the re-read."
    evidence: "iter-9 capture #1 (SF Symbols visible); loop/evidence/hover-expanded-normal-desktop-9.manifest.json (skipped: screen_locked)"
  - iter: 9
    transition: "tooling-hardened (observability)"
    row: "(visual-proof false-green guard)"
    note: "backpressure: visual-proof.sh captured a LOCK SCREEN and reported pixel_live=true (false green). Added scripts/screen-locked.swift + a guard → status=skipped reason=screen_locked when CGSSessionScreenIsLocked. Not a pressure row (a fixed tooling gap); recorded for the ledger."
    evidence: "scripts/screen-locked.swift; scripts/visual-proof.sh"
  - iter: 10
    transition: "core-bar met; settles at table-stakes (stays active, downgraded urgency)"
    row: native-feel
    note: "Two blind reads + a refined render: cleared the pressure's literal bar ('not a web rectangle' — both reads call it a competent NATIVE overlay, not web-in-a-box) but not the higher 'first-party' bar. ACCEPTED as table-stakes-met for the MVP (consult-001: fidelity is table-stakes, not the moat). #1 settles ~3. The first-party gap is coupled to the interaction model (hover/selection) — revisit there, not in another static-polish pass. Stops the polish loop."
    evidence: "loop/evidence/hover-expanded-normal-desktop-10.manifest.json; creative-consults.md consult 002+003"
  - iter: 11
    transition: "refined (burden bent, not broken)"
    row: idle-footprint
    note: "Live polling added ONE 60s repeating Timer (the app's core poll). Reconciled the pressure: it forbids per-frame/UI-animation timers (CADisplayLink), not the low-frequency conditional network poll. Evidence the burden still holds: idle_cpu 0.0 between polls; the only timer is PollScheduler's; 304s are free; island redraws on change only."
    evidence: "loop/evidence/live-app-11.json (idle_cpu 0.0); grep: only PollScheduler scheduledTimer"
  - iter: 11
    transition: "evidence-accrued — now in the real app (stays active)"
    row: signal-trust-budget
    note: "The moat (50→3 radar) now runs LIVE in the actual app, not just the probe — first poll surfaced 3 action-required. Budget still 'near-paid' (the multi-day trust experiment is the remaining channel), but the value is now reachable by just launching githud."
    evidence: "loop/evidence/live-app-11.json"
  - iter: 12
    transition: "evidence-accrued — collapsed-by-default (stays active)"
    row: attention-non-theft
    note: "The summon model directly addresses the consult-002/003 warning ('persistent float = guilt-list'). Default state is now a CALM collapsed pill (60×36, glyph+count), not the always-expanded list; the list appears only on a deliberate summon, and refreshes on change only. Full payment (motion-only-on-change recording) still future, but the core 'doesn't recruit the eye / not a guilt-list' is now structural."
    evidence: "iter-12: live launch → collapsed pill 60×36 (verified); HUDPanelController state machine"
  - iter: 20
    transition: "PAID (stays active — maintain)"
    row: signal-trust-budget
    note: "PAID on the pre-registered channel: the USER audited the real suppressed set (`probe --show-suppressed`) and returned 'IT HOLDS' — no misses. This is tier-1 external/reviewed evidence (the highest signal), exactly the trust-experiment verdict the budget was waiting on. The moat is validated on real data. KEPT ACTIVE (not retired): trust must be MAINTAINED — the self-last-commenter demotion is a landmine (consult 004); re-audit periodically, especially if the classifier changes."
    evidence: "user verdict 2026-06-16 ('it holds'); loop/evidence/live-app-11.json + live-probe-6.json (50→3, suppressed=47, 0 reported misses)"
  - iter: 20
    transition: "added"
    row: surfacing-honors-user-choice
    note: "User reframe: surfacing is now user-configurable (SurfacePreferences, default auto). New burden: any change to what surfaces must respect the user's enabled-reason set + persist it. The classifier's bot/self demotion still applies within the enabled set."
    evidence: "iter-20: SurfacePreferences + SurfaceStore; verified custom pref (review_requested only) → 1 vs auto → 3"
  - iter: 25
    transition: "added"
    row: pulse-honesty
    note: "H2 pulse lane: same trust moat, new surface. The honesty contract (null/UNKNOWN never render green/ready) is baked into the enum mappers + proven per lattice cell AND live (probe: blocked=5 draft=1 ready=10, all real states). Burden on any future pulse-model change."
    evidence: "Sources/GithudCore/PullRequestPulse.swift (mappers + lattice); 164 checks; live probe pulse histogram; loop/evidence/idle-normal-desktop-25.manifest.json"
  - iter: 25
    transition: "evidence-accrued — extended to a 2nd lane (stays active — maintain)"
    row: signal-trust-budget
    note: "The H2 pulse is a NEW thing the HUD surfaces — so the budget extends to it. Honored structurally: the pulse only shows YOUR open PRs' real state, never fabricated; the failing/conflicts/unknown members are always NAMED (composition visible), so the rollup is trustable not opaque. No false-alarm risk added (it's standing state, not events). H1 budget stays PAID ('it holds')."
    evidence: "loop/evidence/idle-normal-desktop-25.manifest.json; live probe pulse histogram (redacted)"
  - iter: 25
    transition: "evidence-accrued (stays active)"
    row: idle-footprint
    note: "H2 adds ONE GraphQL request per existing ~60s poll tick (no new timer; rides PollScheduler's loop). idle_cpu 0.1 in the iter-25 manifest; separate GraphQL rate bucket (4994 remaining). The burden holds — no per-frame work, redraw on change only."
    evidence: "loop/evidence/idle-normal-desktop-25.manifest.json (idle_cpu 0.1); GraphQL rate_remaining 4994"
  - iter: 25
    transition: "evidence-accrued (stays active — WALL)"
    row: notifications-classic-pat
    note: "The GraphQL pulse uses the SAME classic PAT (Bearer) + the repo scope the user already added (reaches private PRs). WALL re-tested: reopen=GitHub adds fine-grained support → no change → STANDS. (GraphQL accepts classic PATs; the Notifications-API fine-grained ban is unrelated + unchanged.)"
    evidence: "live probe (scopes=notifications,repo; GraphQL 200, 16 PRs)"

pressure_consulted:
  - iter: 0
    focus-non-theft: "bent HUDPanel design — canBecomeKey/Main=false override + .nonactivatingPanel style + orderFrontRegardless (never makeKeyAndOrderFront)"
    idle-footprint: "bent the scaffold — static empty island, zero timers / no CADisplayLink"
    native-feel: "bent the island — AppKit NSVisualEffectView (material .hudWindow, blendingMode .behindWindow), not SwiftUI .material"
    notifications-classic-pat: "no-effect — GitHub auth/client not built in bootstrap. WALL re-tested: reopen=GitHub adds fine-grained/App-token support → no change → stands; out of bootstrap scope."
    test-substrate-clt-only: "n/a this pass — added at end of pass as backpressure; bends iter-1 test work"
  - iter: 1
    native-feel: "bent the reframe — consult confirmed AppKit vibrancy is table-stakes (necessary, not the moat); kept the criterion, reweighted. No code touched."
    focus-non-theft: "no-effect on this spec/eval pass (no panel code changed)"
    idle-footprint: "no-effect on this spec/eval pass (no code changed)"
    notifications-classic-pat: "salience only this pass — INTENT/RUBRIC reframe kept the classic-PAT wall central to the data spine; WALL re-tested: reopen (GitHub adds fine-grained/App-token support) → no change → stands"
    test-substrate-clt-only: "bent iter-2 plan — the classifier tests will run on the zero-dep runner (scripts/test.sh), not swift test"
    signal-trust-budget: "bent the RUBRIC (added #11 + elevated #4) and the iter-2 plan (fixture precision ≤ budget is the build's acceptance bar)"
    attention-non-theft: "bent the RUBRIC (added #12) and INTENT (H2 demoted, no decorative motion); bends all future animation work"
  - iter: 2
    signal-trust-budget: "bent the build directly — classifier designed 'misses fatal, false alarms budgeted'; test asserts recall==1.0 + FP≤1 as the acceptance bar. PARTIAL pay (fixture; live experiment pending)"
    notifications-classic-pat: "salience — NotificationThread + classifier are the consumers of the classic-PAT-authed /notifications data; model decodes that exact schema, no fine-grained token wired. WALL re-tested: reopen (GitHub adds fine-grained support) → no change → stands"
    test-substrate-clt-only: "honored — classifier's 40 checks run on the zero-dep runner (scripts/test.sh), not swift test"
    attention-non-theft: "no-effect this pass (pure logic, no UI/motion); bends iter-4 island wiring"
    native-feel: "no-effect (no UI code this pass)"
    focus-non-theft: "no-effect (no panel/event code this pass)"
    idle-footprint: "no-effect (no timer/animation code this pass)"
  - iter: 3
    notifications-classic-pat: "WALL live-validated (user PAT → /notifications HTTP 200, scope notifications). Re-tested: no reopen → STANDS; still forbids fine-grained / App tokens"
    focus-non-theft: "no code changed; screen-rec channel now OPEN for the full proof (typing-while-expanding) — bends iter-4 island-interaction work"
    attention-non-theft: "no code changed; screen-rec channel now OPEN (motion-maps-to-change recording achievable) — bends iter-4 motion work"
    native-feel: "blind-comprehension channel now OPEN (screen-rec) but island still empty — a meaningful read waits for a populated island (iter 4)"
    idle-footprint: "re-confirmed satisfied — idle_cpu 0.1 in the iter-3 real manifest; stays active"
    signal-trust-budget: "no new payment; LIVE experiment channel now OPEN (PAT) — bends the iter-4 trust-experiment harness"
    test-substrate-clt-only: "no-effect (pixel-stats.swift + visual-proof are tooling, not the test target)"
  - iter: 4
    notifications-classic-pat: "WALL honored + re-validated live — GitHubClient auths with the CLASSIC Keychain PAT (Bearer); probe confirmed scopes=notifications. Re-tested: STANDS."
    signal-trust-budget: "bent the build + surfaced a gap — radar ran on real /notifications (14/50); but 13 author threads UNVERIFIED → drives iter-5 enrichment. The build's acceptance bar is now real-data precision, not just fixture."
    test-substrate-clt-only: "honored — PollPlan + KeychainPAT tests run on the zero-dep runner (58 checks); no swift test"
    keychain-headless-prompt: "ADDED — bent the probe design (GITHUD_PAT env path for headless; Keychain for GUI)"
    conditional-polling-no-cache: "ADDED — bent GitHubClient (ephemeral no-cache session) so 304s surface"
    idle-footprint: "no-effect (headless network pass; no timers/animation added)"
    focus-non-theft: "no-effect (no panel/event code; GUI path unchanged)"
    attention-non-theft: "no-effect (no UI/motion this pass)"
    native-feel: "no-effect (no UI this pass)"
  - iter: 5
    signal-trust-budget: "THE driver — built enrichment to attack the author-thread false-alarm risk. Surfaced the deeper gate: private-repo enrichment needs `repo` scope (7×404→scope-aware skip). Precision still unpaid on real data."
    notifications-classic-pat: "WALL honored — enrichment GETs use the same classic PAT; re-validated scopes=notifications. STANDS."
    conditional-polling-no-cache: "honored — enrichment fetches go through the same ephemeral no-cache GitHubClient"
    keychain-headless-prompt: "honored — re-probe ran headless via GITHUD_PAT"
    test-substrate-clt-only: "honored — needsEnrichment tested on the zero-dep runner (63 checks)"
    idle-footprint: "no-effect (headless pass)"
    focus-non-theft: "no-effect (no UI)"
    attention-non-theft: "no-effect (no UI)"
    native-feel: "no-effect (no UI)"
  - iter: 6
    signal-trust-budget: "THE driver — self-activity demotion drove the radar 13→3 on real data (the decisive precision lever after bot-demotion). Budget now near-paid; only the multi-day trust experiment + island validation remain."
    notifications-classic-pat: "WALL honored — GET /user + enrichment via the classic PAT (notifications,repo). Re-tested: STANDS."
    conditional-polling-no-cache: "honored — /user + enrichment go through the same ephemeral no-cache client"
    keychain-headless-prompt: "honored — probe ran headless via GITHUD_PAT"
    test-substrate-clt-only: "honored — self-demotion tested on the zero-dep runner (72 checks)"
    idle-footprint: "no-effect (headless pass)"
    focus-non-theft: "no-effect (no UI this pass)"
    attention-non-theft: "no-effect (no UI this pass) — but BENDS iter-7 island wiring (no decorative motion)"
    native-feel: "no-effect (no UI this pass) — BENDS iter-7 island wiring (AppKit-native render)"
  - iter: 7
    native-feel: "BENT the island — AppKit IslandContentView/RadarRowView inside the NSVisualEffectView; native label colors (label/secondary/tertiary) for vibrancy show-through, NO SwiftUI .material. (Visual quality unverified — display asleep.)"
    attention-non-theft: "BENT the island — static render, zero timers/animation on show (idle-footprint too); no decorative motion. Will re-prove on screen-recording once awake."
    focus-non-theft: "honored — showRadar uses orderFrontRegardless (never makeKey); HUDPanel still canBecomeKey/Main=false"
    idle-footprint: "honored — no timers added; the populated island is static"
    test-substrate-clt-only: "honored — RadarPresenter age/row formatting tested on the zero-dep runner (83 checks)"
    notifications-classic-pat: "no-effect (no network this pass; fixture render is offline)"
    signal-trust-budget: "no-effect (no classifier change; uses iter-6 radar)"
    conditional-polling-no-cache: "no-effect"
    keychain-headless-prompt: "no-effect"
  - iter: 8
    native-feel: "TESTED against its pre-registered channel (blind read) — FAILED to pay: 'competent third-party, not first-party'. Drives the iter-9 refinement (materials/SF Symbols/row anatomy). The strongest signal this pass."
    attention-non-theft: "evidence accrued — manifest frontmost_unchanged=true + static island (no motion). Full proof (motion-only-on-change) awaits the live/animated states."
    focus-non-theft: "evidence accrued — frontmost_unchanged=true on show (orderFrontRegardless worked; no focus theft)."
    idle-footprint: "honored — static populated island; no timers"
    test-substrate-clt-only: "honored — geometry fix kept the 83-check suite green on the zero-dep runner"
    notifications-classic-pat: "no-effect (fixture render, offline). WALL re-tested: no reopen → STANDS"
    signal-trust-budget: "no-effect (uses iter-6 radar)"
    conditional-polling-no-cache: "no-effect"
    keychain-headless-prompt: "no-effect"
  - iter: 9
    native-feel: "THE driver — refined per consult 002 (SF Symbols + badge + metrics). Re-proof blocked (screen locked). Stays owes-proof until the 2nd blind read."
    attention-non-theft: "honored — still static, no motion added"
    focus-non-theft: "honored — showRadar still orderFrontRegardless"
    idle-footprint: "honored — no timers added"
    test-substrate-clt-only: "honored — symbolName tested on the zero-dep runner (87 checks)"
    notifications-classic-pat: "no-effect (offline render). WALL re-tested: no reopen → STANDS"
    signal-trust-budget: "no-effect (uses iter-6 radar)"
    conditional-polling-no-cache: "no-effect"
    keychain-headless-prompt: "no-effect"
  - iter: 10
    native-feel: "driver — material/type pass; 2nd blind read settled it at competent table-stakes. BENT the decision to STOP polishing + pivot to live integration (don't over-optimize a non-moat axis)."
    attention-non-theft: "honored — still static; the .popover material/border add no motion"
    focus-non-theft: "honored — orderFrontRegardless unchanged"
    idle-footprint: "honored — no timers; but BENDS iter-11 (the live poll timer must reconcile this — 60s conditional poll justified, not UI animation)"
    test-substrate-clt-only: "honored — 87 checks on the zero-dep runner"
    notifications-classic-pat: "no-effect (offline render). WALL re-tested: STANDS"
    signal-trust-budget: "no-effect (uses iter-6 radar)"
    conditional-polling-no-cache: "no-effect this pass; BENDS iter-11 (the live scheduler reuses the no-cache client)"
    keychain-headless-prompt: "no-effect this pass; BENDS iter-11 (GUI live mode uses Keychain directly w/ Always-Allow)"
  - iter: 11
    idle-footprint: "REFINED — the live 60s poll Timer is justified (idle_cpu 0.0 between polls; conditional/cheap; no animation timers). Pressure bent, not broken."
    conditional-polling-no-cache: "honored — PollScheduler reuses the ephemeral no-cache GitHubClient; live 304s carry validators"
    keychain-headless-prompt: "honored — live mode reads GITHUD_PAT (headless verify) else Keychain (GUI); resolvePAT()"
    notifications-classic-pat: "WALL honored — live client auths with the classic PAT; re-tested: STANDS"
    attention-non-theft: "honored — island refreshes ON CHANGE only (PollScheduler change-detection), no churn between polls"
    focus-non-theft: "honored — showRadar orderFrontRegardless on refresh (no key-steal)"
    signal-trust-budget: "the moat now runs live in the app (50→3); evidence accrued"
    native-feel: "no-effect (no UI change this pass; reuses iter-10 island)"
    test-substrate-clt-only: "honored — 87 checks; PollScheduler is integration-verified (live-app-11), not unit-tested"
  - iter: 12
    attention-non-theft: "THE driver — collapsed-by-default summon model pays it (calm pill default, not a guilt-list). Bent the whole interaction design."
    native-feel: "BENT — the collapsed pill reuses the SF Symbol + popover material vocabulary; consistent with the expanded list"
    focus-non-theft: "honored — toggleExpand uses orderFrontRegardless; panel still non-activating (no key-steal on summon)"
    idle-footprint: "honored — no new timers; collapsed pill is static"
    test-substrate-clt-only: "honored — 87 checks; UI verified by geometry probe"
    notifications-classic-pat: "no-effect (no network change). WALL re-tested: STANDS"
    signal-trust-budget: "no-effect (reuses iter-11 live radar)"
    conditional-polling-no-cache: "no-effect"
    keychain-headless-prompt: "no-effect"
  - iter: 13
    focus-non-theft: "honored + extended — click→Open opens via NSWorkspace; panel stays non-activating (no key-steal). The H3 guardrail held: Open-on-GitHub, not act-from-HUD."
    native-feel: "BENT — added the hover selection fill (the 'native list affordance' consult 003 flagged); partial step on the first-party gap"
    attention-non-theft: "honored — hover fill only on mouse-over; no idle motion"
    test-substrate-clt-only: "honored — htmlURL mapping tested on the zero-dep runner (90 checks)"
    notifications-classic-pat: "no-effect. WALL re-tested: STANDS"
    idle-footprint: "honored — no timers"
    signal-trust-budget: "no-effect (reuses live radar)"
    conditional-polling-no-cache: "no-effect"
    keychain-headless-prompt: "no-effect"
  # iters 14-19 consulted (abbrev): each pass re-tested the classic-PAT WALL (STANDS) + honored test-substrate/focus/idle; drivers noted in last_action + ledger.
  - iter: 20
    signal-trust-budget: "PAID — the user's 'it holds' verdict on the real suppressed set is the pre-registered channel returning positive. The driver of the whole loop, now validated. Kept active to maintain."
    surfacing-honors-user-choice: "ADDED — the user-reframe feature; bends all future surfacing changes (respect + persist the enabled set)"
    notifications-classic-pat: "WALL honored — SurfacePreferences is offline logic; the live path still auths classic-PAT. Re-tested: STANDS"
    attention-non-theft: "honored — toggling reduces/keeps noise per the user's choice (more user control = less unwanted surfacing)"
    test-substrate-clt-only: "honored — SurfacePreferences toggling tested on the zero-dep runner (97 checks)"
    native-feel: "BENT — the Surface… submenu is native NSMenu; consistent"
    focus-non-theft: "honored — menu/toggle don't change the panel's non-activating behavior"
    idle-footprint: "honored — re-render on toggle recomputes from cached threads (no extra poll/timer)"
    conditional-polling-no-cache: "honored — setPreferences recomputes without a re-fetch"
    keychain-headless-prompt: "no-effect"
  - iter: 25
    pulse-honesty: "ADDED + THE driver — the entire H2 design bent around never fabricating a green/ready the data can't back (null/UNKNOWN → conservative member; .ready requires explicit mergeable). Proven per-cell + live."
    signal-trust-budget: "BENT — extended the budget to the new pulse surface; structural honesty + composition-visible subtitles keep it trustable. H1 stays PAID."
    notifications-classic-pat: "WALL honored — GraphQL pulse reuses the classic PAT (Bearer) + repo scope. Re-tested: GraphQL accepts classic PATs; the fine-grained Notifications ban is unrelated → STANDS."
    idle-footprint: "honored — one GraphQL call per existing poll tick, no new timer; idle_cpu 0.1; separate rate bucket. Burden holds."
    conditional-polling-no-cache: "honored — the pulse fetch goes through the same ephemeral no-cache GitHubClient; GraphQL has no 304 (documented; separate bucket, REST 304-discipline untouched)."
    attention-non-theft: "honored — the 'Your PRs' lane is static; the pill gauge updates on change only (PollScheduler diff); no idle motion."
    focus-non-theft: "honored — setPulse re-renders via orderFrontRegardless; panel stays non-activating; click→Open-on-GitHub (H3 guardrail) for PR rows."
    native-feel: "BENT — PulseRowView mirrors RadarRowView's AppKit anatomy (SF Symbol + label hierarchy + hover fill); consistent with the radar lane."
    test-substrate-clt-only: "honored — 164 checks on the zero-dep runner (lattice/decode/presenter/rollup/fixture/privacy); app-layer wiring is probe + visual-proof verified."
    surfacing-honors-user-choice: "no-effect (pulse is a separate lane; SurfacePreferences governs the H1 radar only — pulse surfacing prefs deferred)."
    keychain-headless-prompt: "honored — the live pulse verification ran headless via GITHUD_PAT (authorized security CLI)."
  - iter: 26
    signal-trust-budget: "THE driver (3-model second-opinion) — recalibrated H1: security_alert↑, novel-reason un-buried, invitation added. POLICY-b (direct @you mention never bot-demoted) trades false-alarm budget for never-miss (PagerDuty case). MEASURED (iter 27, radar_automation_policy_b meter + --show-items): policy-b false-alarm cost = 0 on current data — 0 of 11 radar items are automation; the 11 are genuine (6 review_requested + 5 author/PR-activity). PAID maintained (no new misses, no measured false alarms). The meter is the standing watch instrument."
    pulse-honesty: "RE-PROVEN + hardened — closed a hole the 2nd opinion found: an UNRECOGNIZED non-null CI rollup state was mapped to .none (no checks → ready-eligible), letting API drift false-certify green. Now → .pending (fails safe). Re-tested per-cell (drift→pending→waiting, not ready)."
    surfacing-honors-user-choice: "EXTENDED to the pulse lane — drafts are a new user-configurable surface (PulsePreferences.showDrafts, default off, persisted via PulseStore). Mirrors the H1 reason-toggle discipline (respect + persist; re-render no refetch)."
    attention-non-theft: "honored + ADVANCED — drafts (WIP 'ignore me') are hidden from the main lane + the calm pill gauge by default; less surfaced, not more."
    native-feel: "BENT — the 'Drafts' section reuses sectionHeader + PulseRowView; the menu checkbox is native NSMenuItem state. Consistent."
    test-substrate-clt-only: "honored — 214 checks on the zero-dep runner (recalibration, CI-drift, draft model + gauge-excludes-drafts invariant); app-layer (UI grouping, menu) is visual-proof + probe verified."
    notifications-classic-pat: "WALL honored — no auth change; classic PAT unchanged. Re-tested: STANDS."
    idle-footprint: "honored — the draft toggle is a pure re-render from cached pulse (no refetch/timer). idle_cpu 0.1 in both iter-26 manifests."
    focus-non-theft: "honored — setPulsePreferences re-renders via orderFrontRegardless; menu toggle doesn't change the panel's non-activating behavior."
    conditional-polling-no-cache: "no-effect (no network-path change this pass)."
    keychain-headless-prompt: "honored — live probe + visual proof ran headless via GITHUD_PAT."
  - iter: 28
    native-feel: "THE driver — the theme system is a native-feel investment (the moat-adjacent #1). Themes are AppKit-faithful: vibrant↔solid materials, semantic NSColor tokens, SF Symbols (mono fill/outline), a Geist grain tile. Monotone themes also satisfy 'Differentiate Without Color' (a11y). BENT the whole view layer onto tokens. Color theme parity keeps the validated look."
    idle-footprint: "RE-PROVEN with grain — the Geist grain is a STATIC seeded tile (no Date/random, no CIFilter, no timer); idle_cpu 0.3% in the iter-28 manifest (vs 0.1-0.2% others). Static texture, GPU-composited, 0 idle. setTheme re-renders only on a user pick (no loop). Burden holds."
    attention-non-theft: "honored — theme switch is a one-shot re-render on a deliberate menu pick; no idle motion; no animated grain (rejected for exactly this)."
    focus-non-theft: "honored — setTheme/setReduceTransparency re-render via the same orderFrontRegardless path; panel stays non-activating."
    test-substrate-clt-only: "honored — ThemeID registry tested on the zero-dep runner (231 checks); Theme/ThemeStore (AppKit) are compile-exhaustive + visual-proof verified (no GithudApp test target)."
    notifications-classic-pat: "WALL untouched — themes are pure presentation, no auth/network change. Re-tested: STANDS."
    signal-trust-budget: "no-effect — themes never change WHAT surfaces (classifier/pulse untouched); only HOW it looks. Color parity preserves the validated render."
    surfacing-honors-user-choice: "extended in spirit — theme is another persisted user choice (ThemeStore), mirroring SurfaceStore/PulseStore; re-render no refetch."
    conditional-polling-no-cache: "no-effect (no network path touched)."
    pulse-honesty: "no-effect (pulse model untouched; only the glyph TINT/fill is themed, never the state)."
  - iter: 30
    color-doctrine: "ADDED + THE driver — the consult-008 doctrine became a standing pressure AND was applied the same pass. Color now spent only on a changed next-move (danger/success/caution-degraded); ink by default; critical-first sort + one reserved security red; green=ready-not-alive; yellow gone. Bends ALL future color use."
    signal-trust-budget: "no-effect on WHAT surfaces — but conceptually ALIGNED: the doctrine is the same trust moat applied to the palette (color spent only on decision-changing info, as attention is spent only on action-required signal). Classifier urgency/action-class untouched; only the SORT gained a critical-first tier (security floats up — strictly never-miss-positive, no item dropped)."
    pulse-honesty: "honored — the H2 yellow→ink + green=ready-only change is presentation; the state LATTICE and honesty mappers are untouched (null/UNKNOWN still never render ready). The subtitle still NAMES the members. green still = real merge-availability, never a fake CI claim (no-checks ready keeps its 'no checks' subtitle)."
    native-feel: "BENT — the doctrine is a native-feel refinement (macOS HIG: use color sparingly/semantically, never as the sole carrier; Primer's open/success/attention/danger as distinct roles). Mono-by-default + one critical reads calmer + more first-party."
    attention-non-theft: "honored + ADVANCED — dropping the 4-band heat scale is literally less perceptual color-noise; the radar no longer 'cries wolf in hue'. No motion added."
    test-substrate-clt-only: "honored — 254 checks on the zero-dep runner (criticalReasons/isCritical/critical-first sort are pure GithudCore); the Theme color MAPPING (GithudApp) is visual-proof + blind-read verified (no GithudApp test target)."
    surfacing-honors-user-choice: "no-effect (the doctrine changes HOW items look, never WHICH surface — the enabled-reason set is untouched)."
    notifications-classic-pat: "WALL untouched — pure presentation + a sort-tier change; no auth/network. Re-tested: STANDS."
    idle-footprint: "honored — the doctrine is render-time color/sort logic; no timers, no per-frame work. idle_cpu 0.1 in manifests 300-303."
    focus-non-theft: "honored — no panel/event change; the island re-renders via the same orderFrontRegardless path."
    conditional-polling-no-cache: "no-effect (no network path touched)."
    keychain-headless-prompt: "honored — the iter-30 visual proof ran headless via GITHUD_SCREEN_REC; no token path touched."
  - iter: 31
    signal-trust-budget: "THE finding + a DOWNGRADE. The pagination MISS (page-1-only → 50 of 272 fetched) meant action-required items were silently dropped — the never-miss core was broken. FIXED + live-verified (272 threads). But this INVALIDATES the iter-20 'it holds' PAID verdict (it audited page 1 only). Recall is no longer paid; re-audit owed on the full inbox. The single most important pressure event since iter 20."
    pulse-honesty: "RE-PROVEN + hardened (review F10) — closed the review-mapper twin of the iter-26 CI hole: an unrecognized non-null reviewDecision mapped to .none (ready-eligible), letting API drift false-certify a PR as ready. Now → .reviewRequired (fail safe; blocks ready). Tested per-cell (drift review + passing + mergeable → waiting, not ready)."
    conditional-polling-no-cache: "honored + RE-PROVEN under pagination — the paginated fetch still surfaces the 304 (live-probe-31: second=304 not_modified). Continuation pages are plain GETs only on a real change (200); a 304 fetches ZERO pages. Burden holds."
    idle-footprint: "honored — pagination adds requests ONLY on a real change (a 200 with >50 unread), never per-poll; 304s still free. No new timer. The bounded enrichment (F6) caps per-refresh wall-clock; no per-frame work."
    notifications-classic-pat: "WALL honored + the GUI now ENFORCES the classic-PAT shape at startup (review F8) — a fine-grained token gets a setup message instead of a silent 403 loop. Re-tested: live probe scopes=notifications,repo on a 200 → STANDS."
    keychain-headless-prompt: "honored — the verification probe ran headless via GITHUD_PAT (inlined from the authorized security CLI; token never logged/printed). README now documents the interactive -w so users don't leak it either (review F2)."
    attention-non-theft: "no-effect on motion (no UI motion changed); the redraw-key fix (F3/F4) actually TIGHTENS change-detection so the island redraws on real content change, not noise."
    test-substrate-clt-only: "honored — 261 checks on the zero-dep runner (+ parseNextLink + review-drift); the app-layer network/redraw/a11y changes are build + live-probe verified (no GithudApp test target)."
    focus-non-theft: "honored — a11y additions (F7) expose .button role + performPress but the panel stays non-activating; opening a row still uses NSWorkspace (no key-steal)."
    color-doctrine: "no-effect (no color/sort change this pass; the review was correctness/reliability/security, not presentation)."
    surfacing-honors-user-choice: "no-effect (the enabled-reason set is untouched; pagination just fetches the COMPLETE set the prefs then filter)."
  - iter: 33
    color-doctrine: "ADVANCED + COMPLETED — built the freshness cue, the doctrine's ONE sanctioned `caution` use (degraded reading confidence). caution was a reserved token with no consumer; now danger/success/caution all have live consumers. The cue is shown ONLY when degraded (normal operation is quiet) and crosses to the collapsed pill (critical-facts-cross-boundaries principle)."
    pulse-honesty: "EXTENDED to a new axis — honesty about 'is this reading CURRENT?', not just 'is each state real?'. A stalled/failing poll no longer presents last-good data as live; the caution banner says 'Reconnecting — last update Nm ago'. Same trust moat, the time dimension."
    signal-trust: "ALIGNED — a silently-stale radar is a miss-by-omission (you trust a glance that's hours old). The freshness cue makes that visible. Doesn't change WHAT surfaces; flags WHEN the surface is old."
    idle-footprint: "honored — freshness rides the EXISTING poll outcomes (no new timer); emitted on CHANGE only, so a steady .fresh adds zero re-renders. The pure model has no I/O."
    native-feel: "BENT — the banner/clock reuse the SF Symbol + label vocabulary + a semantic token; consistent with the island. caution-amber only when degraded."
    test-substrate-clt-only: "honored — FreshnessModel is pure GithudCore (11 zero-dep checks); the HUD wiring is visual-proof verified (330/331, --stale)."
    notifications-classic-pat: "WALL untouched (no auth/network change). Re-tested: STANDS."
    attention-non-theft: "honored — no motion; the cue appears only on a real degradation, vanishes on recovery; no idle chrome."
    focus-non-theft: "honored — setFreshness re-renders via the same orderFrontRegardless path; panel stays non-activating."
    conditional-polling-no-cache: "honored + REINFORCED — a 304 counts as a success (data confirmed current → .fresh), so the 304-discipline and freshness agree."
```
