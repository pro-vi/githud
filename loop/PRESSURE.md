# githud — PRESSURE (active field)

> **Rendered projection** of `loop/STATE.md` `pressure_objects` (the source of
> truth). Re-render + re-read this at **iteration step 0**, before any planning.
> Never trust this file independently of STATE. Maintenance rules (carried here so
> they survive context compaction):
>
> - Let each active row tilt the plan *while still planning, before any gate*.
> - Modes, weakest→strongest: `salience` < `preference` < `burden` < `constraint`.
>   Only `constraint` is a wall; the rest are slopes. Stronger wins on a shared scope.
> - Re-test every enforced `constraint` against its `expires`/reopen each pass; a
>   wall not re-tested this pass is read as a `burden` (fail-open, never self-brick).
> - Pressure shapes *how* a move is chosen, never *whether* a gate is met. A phase
>   gate / open rubric criterion outranks every pressure.
> - Write a `pressure_consulted` record to STATE each pass (row id → plan element
>   bent, or `no-effect: reason`). No record = step 0 not done.
> - On a failed verify/build/launch/focus-test/consult, append a `source:
>   backpressure` row in the softest justified mode (default `burden`).

## Active rows

### 🟧 `focus-non-theft` — burden · high

The HUD must never steal focus: never-key EXCEPT during an explicit user-consented
key moment — BOTH ratified moments are now BUILT: the WP-4d ledger-card field click,
and the WP-6k ⌃⌥G list session (the user's own chord IS the consent). Both scope
through the single `keySessionActive` flag: the card writes it via render() on card
presence; the list session via `HUDPanelController.keySelection`'s begin/end choke
points — ended instantly by esc / ⏎-after-open / second ⌃⌥G / click-away / chevron
collapse / hide() / a card interposing / key loss to another window. Every mouse
path (pill click, status-item click, "Show island") stays never-key, and the app
NEVER activates (`makeKey()` only; key snaps back to the still-active foreground
app via the order-out pulse). Any panel/event-handling change **owes proof** the
HUD doesn't interrupt the foreground app.
*Pays out on:* an input-routing proof PER key moment — a RATIFIED MERGE CONDITION
(Gates.json review note 1: "re-cut … BEFORE merge"); absent it the package PARKS
unmerged. Card moment: PAID — the WP-4d AX-witnessed run
(loop/evidence/wp4d-key-routing.manifest.json). List session — WP-6k's OWN
recording obligation: ⌃⌥G takes key (foreground caret honestly stops) while the
foreground app stays active; ↑/↓/space/⏎/esc act in the island; esc/⏎ hand key
straight back (post-esc keystrokes land in the foreground app, AX-read); the mouse
expand shows NO bar, NO hint and never takes key —
loop/evidence/wp6k-key-session.manifest.json. Plus: `HUDPanel.canBecomeKey ==
keySessionActive` (false at rest), card acquisition only via
`becomesKeyOnlyIfNeeded` + the field's `needsPanelToBecomeKey`;
`orderFrontRegardless` (not `makeKeyAndOrderFront`); no `NSApp.activate` anywhere.
*Still owed to dogfood (the recordings are synthesized-hands):* human-hands re-cuts
of both manifests; real VoiceOver narration (the AX mirror is only query-witnessed);
**the IME/composition-drop cost of `makeKey` mid-input in a real editor** (Gates.json
review note 2's second half — a CJK composition buffer dropping on ⌃⌥G is exactly the
named cost); the individually-unwitnessed end paths (click-away, key-loss,
second-⌃⌥G, chevron collapse, card interposing, gear-menu-during-session); and the
unmapped-key beep's sensory cost (letters mid-session audibly go nowhere — honest,
but feel it).
*2026-07-10 (D-pill chooser card):* a NEW card entered the island — proof owed and
paid at the CLT ceiling: `PillStyleChooser.takesKeyMoment == false` pinned headlessly,
the render branch forces `keySessionActive = false`, no editable field exists, and a
must-see ledger outranks it (guard at open + render order). Controller-level
integration assert not expressible in the Core-only runner (proof-by-proxy, recorded
in the WP landing record — same model as the ledger card's own proof).
*Expires:* iter 60 / panel architecture stabilizes.

### 🟧 `idle-footprint` — burden · medium

At idle the HUD must be silent and cheap. Adding any animation/timer **owes proof**
it doesn't run permanently.
*Pays out on:* `top`/Activity-Monitor ~0% CPU when idle; no permanent repeating
timer / `CADisplayLink` (grep). *Expires:* iter 80.
*2026-07-10 (D-pill config):* grep-clean re-proven on the full WP diff (zero new
Timer/CADisplayLink/animator). The F-1 sweep-crossing repaint rides the EXISTING
poll tick, change-gated on the boolean crossing (steady states emit nothing); the
sweep clock itself is read-at-render, deliberately un-notified (recorded). Chooser
previews rebuild behind an input-diff guard — no per-poll churn while the card is up.

### 🟦 `native-feel` — preference · high

Favor AppKit-owned vibrancy and native materials over synthetic/web-like looks —
this is the core value. Departing **owes an explanation**.
*Pays out on:* blind comprehension read confirms "polished Mac-native overlay, not
a web rectangle"; vibrancy via `NSVisualEffectView`, not SwiftUI `.material`.
*Expires:* iter 100 (re-review with INTENT).

### 🟥 `notifications-classic-pat` — constraint · high · WALL

The GitHub inbox path **must** authenticate with a **classic** PAT
(`notifications` scope). Wiring a fine-grained PAT or GitHub App token for
`/notifications` is **refused** — GPT-Pro-verified that the Notifications API 403s
/ returns empty for those token types.
*Pays out on:* the inbox client uses a classic PAT and the auth doc says so.
*Reopen:* if GitHub adds fine-grained / App-token support to the Notifications API.

### 🟧 `test-substrate-clt-only` — burden · medium · *(backpressure, iter 0)*

Tests run under Command Line Tools only — **XCTest and swift-testing are both
absent** (iter-0 probe: `no such module`). Any test work **owes proof** it runs on
the zero-dep runner, not a reach for `swift test`.
*Pays out on:* `scripts/test.sh` exits 0 via `swift run GithudCoreTests`.
*Reopen:* if full Xcode is adopted (then swap to XCTest/Testing).

### 🟩 `signal-trust-budget` — burden · high · **PAID (iter 20)** · *(the moat)*

The existential axis. **PAID** on its pre-registered channel: the user audited the
real suppressed set and returned **"it holds" — no misses**. The moat is validated on
real data. Kept active to *maintain* (the self-last-commenter demotion is a landmine —
re-audit periodically, especially on classifier changes).
*New feed source 2026-07-09 (the inbound SWEEP, `/search/issues` — user-directed):* the
row's scope covers "any new feed source"; audit state: the sweep ran once, manually,
pre-build against the real account — 8 items, and the 5-human/3-bot split validated the
bot demotion on real data (that cut IS the committed fixture). The surfaced set is
search-API ground truth (`is:open`, owned repos, not-authored) — no classifier between
the API and the lane; the honesty risks live in ADOPTION (incomplete never removes —
Core-tested) and DEPARTURE (an item leaves only on a complete reading — Core-tested,
**live-unwitnessed**: the first real close/merge disappearing from the queue is OWED to
dogfood). Confirmation (`inboundConfirmed`) gates the affirmation + pill all-clear on a
COMPLETE sweep. Idle note: the sweep adds ONE un-304-able search GET per ~60s tick on
the existing poll timer (no new timers — grep-clean; ~1/30 of the separate search
bucket; snapshot writes still ride lane-key changes only).
*Pill surface 2026-07-10 (D-pill config, WP 2026-07-10-001):* the sweep's honesty
reached the COLLAPSED pill — any inbound-count-bearing pill state now takes its
caution prefix from the SWEEP clock (never-swept ⇒ degraded; composed claims degrade
on the stalest member), and the trust panel's F-1 catch closed the render gap: the
fresh↔stale crossing is change-gated in the reducer and wakes exactly one repaint per
boundary (both directions; recovery clears next-tick, ~60s bound, documented). The
"adopted-stale count under fresh chrome" fabrication is now closed at both layers.
Live-unwitnessed: the on-screen crossing repaint (wiring proven to the notification
seam only) — rides the same dogfood watch as the close/merge departure.
*Classifier change 2026-07-09 (`inbound` derived reason, user-directed):* re-audit run —
live probe on real data found **zero `subscribed` threads** in 384 unread, so the change
is a live no-op today and the surfaced/suppressed split is UNCHANGED on real data
(monotonic-add verified in review: no previously-surfaced thread is suppressed). The
live half of this audit is therefore STILL OWED: the first real inbound arrival (and
whether the user's GitHub Watching setting even routes to the API inbox) is a standing
dogfood watch — recorded in the agenda's inbound entry.

### 🟧 `surfacing-honors-user-choice` — burden · medium · *(user reframe, iter 20)*

Surfacing is user-configurable (`SurfacePreferences`, default auto). Any change to
what surfaces **owes** respecting + persisting the user's enabled-reason set; bot/self
demotion still applies within it. *Verified:* custom pref → 1 vs auto → 3.
*Extended 2026-07-09:* the derived `inbound` toggle ("opened on your repo", default-on
per user call) — a stored custom set is honored verbatim (toggle appears unchecked);
only an un-era-stamped pre-inbound AUTO snapshot follows auto forward; a deliberate
inbound-off save is era-stamped and never re-migrated (Core `fromStored` tested; the
UserDefaults era gate is app-target, untestable here — disclosed).

### 🟧 `pulse-honesty` — burden · high · *(consult/moat, iter 25 — H2 lane)*

The H2 pulse must **never fabricate a green/ready state it can't back** — same moat
(trust) as `signal-trust-budget`, new surface. null `statusCheckRollup` → "no checks"
(not passing); UNKNOWN/null `mergeable` → "checking…" (never ready); null
`reviewDecision` → "no review required" (not approved); `.ready` requires `mergeable`
explicitly. Any pulse-model change **owes** re-proof of the honesty mappers. The
subtitle always **names** the failing/conflicts/unknown member (composition visible).
*Pays out on:* per-lattice-cell tests (164 checks) + live probe (real
blocked/ready/waiting/draft). *Expires:* iter 80 / pulse-model change.

### 🟧 `attention-non-theft` — burden · high · *(consult 001, iter 1)*

Focus-non-theft ("don't activate") is necessary but **insufficient** — a
non-activating panel can still be an attention vampire. Motion / novelty /
persistent presence **owes proof**: still by default; motion **only** on a real
action-required change.
*Pays out on:* grep (no idle motion) + screen recording (motion maps 1:1 to an
actionable change, PAT+screen-rec-gated). *Expires:* iter 100 (re-review w/ INTENT).

### 🟧 `keychain-headless-prompt` — burden · medium · *(backpressure, iter 4)*

An ad-hoc-signed binary calling `SecItemCopyMatching` **headless** blocks forever on
a GUI Keychain prompt. Headless token reads **owe** the `GITHUD_PAT` path (via the
already-authorized `security` CLI); the GUI app reads Keychain directly (one-time
Always-Allow). *Reopen:* if the app gets a Developer-ID signature.

### 🟧 `conditional-polling-no-cache` — burden · medium · *(backpressure, iter 4)*

`URLSession.shared`'s `URLCache` silently revalidates and serves a cached 200,
**swallowing the 304** and defeating RUBRIC #8. The conditional-polling client
**owes** an ephemeral/no-cache session so 304s reach our code (proven live 200→304).
*Expires:* iter 80 (re-review when the poll scheduler stabilizes).

### 🟥 `color-doctrine` — burden · high · *(consult 008, iter 30)*

The palette serving the **same trust moat** the classifier serves with attention:
**shape says what · order says priority · color says what changes the next move.**
Ink by default; color spent **only** on a changed next-move — `danger` (intervene /
the one reserved security-critical, sorted critical-first), `success` (a positive
action just unlocked), `caution` (the *reading* itself is degraded). Accent is chrome,
never status. No green-for-alive; no yellow-for-ordinary-progress. **A11y law:** swap
every semantic color for the same gray and the full meaning must still survive (shape
+ VoiceOver carry it). Any **new** use of color **owes proof** it marks decision-changing
info, not rank / identity / liveness.
*Pays out on:* 254 checks (critical-first sort + isCritical) + visual proof 300–303 +
the blind read (lone red security shield, zero yellow). *Expires:* iter 100 (or sooner
if dogfood shows mono slows time-to-first-correct-row → add ONE emphasis tier, never the
heat ladder back).
*2026-07-10 — first dogfood flicker:* the user, reviewing D-pill mocks: "tbh looking at
green and red on the island, not sure." Island pulse badges (ratified success/danger)
UNTOUCHED; the default pill style (queueLeads) happens to retire the pill's chronic
badge color as a side effect. If the discomfort recurs on the island itself, that is
this row's named reopen signal. Also load-bearing and now recorded: the D-pill session
proved the shield⊥gauge co-render exclusion is what the PAID blind-read proof rests on
(the killed composed variants would have broken it); any future design that co-renders
the two color families re-opens this row's proof.

---

*Ledger + lifecycle live in `loop/STATE.md` (`pressure_ledger` + `pressure_consulted`).
12 in-force rows (signal-trust-budget PAID+maintained; pulse-honesty added iter 25;
color-doctrine added iter 30; at cap 12).*
