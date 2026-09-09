---
title: Quick navigator — filter the island (type-to-jump)
date: 2026-09-04
status: RATIFIED 2026-09-04 — user picked thesis A ("lets do A first"); the two build-time
  forks below (input model, fallback row) were delegated to the runner ("go figure it out")
  and are decisions D1/D2 here, amendable at build with a recorded note.
  AMENDED 2026-09-05 — after U1–U4 landed, D1's manual editing was replaced by a native
  text field with a summon-time row snapshot; see "Native editing — replacement plan"
  under Build-time spec amendments. That section is the build entry point (U6 → U5).
mocks: 2026-09-04-quick-navigator-mocks.html (interactive; option A, eight states, typing is live)
origin: a voice note ("I want a quick navigator to the PR — I don't always have the link or
  the branch when talking to agents") → /ui-sketch (three theses) → this record. Every
  file:line claim below was verified against source by two read-only agents on 2026-09-04.
---

# Quick navigator — agenda

One decision record. Thesis A is the decision; B and C are struck for now and kept for the
record. Numbered decisions D1–D7 are the runner's picks on the forks the sketch could not
settle; each carries its reason so a builder can overturn it knowingly, not silently.

## The ask (verbatim, filler trimmed)

> I want to serve myself, who lives in the keyboard. A Swift native app has a good
> capability to respond to hot keys. The pain point I'm having is agent workflows —
> talking to agents, I don't always have access to the link to the PR, or branch. So
> essentially what I want is really a quick navigator to the PR. That's all I need.
> I want to navigate to a PR, and once we build that, a lot of it can become natural:
> I can navigate to a repo, I can query for issues. It becomes this thing that's ready
> for me to always just look up things instead of having to move my mouse, open it,
> and scroll through a bunch of random stuff.

## The three theses

| Variant | Verdict | Essence |
|---|---|---|
| ★ `A · filter-the-island` | **ratified** | no new surface, no new chord; after ⌃⌥G any printable key starts a jump line in the header slot and the three lanes narrow in place to what the island already holds; a trailing GitHub row is the way out |
| `B · palette` | kill (for now) | second chord ⌃⌥P, a well + grouped results, GitHub search debounced per keystroke; the right shape only if issue queries become daily |
| `C · resolver` | kill (parser kept) | second chord, Connect-card ledger, one handle → one destination; its handle parser is folded into A |

## What A is, after contact with the code

⌃⌥G summons the island as today (`SummonHotkey.swift`, `AppDelegate.swift:157-178` — the
only caller of `beginKeySummonSession`). During that session the panel *is* key
(`HUDPanel.swift:37`, `canBecomeKey == keySessionActive`) and every key not in the ratified
map falls through to a beep (`KeySession.swift:22-25`, `HUDPanelController.swift:658-690`).
The feature widens that map: printable keys and backspace build a **query string**; the
header slot draws it; the three lanes are narrowed to matching rows **before** both the view
and the keyboard walk see them.

Matching is over the row's **displayed line** — title, the `repo` string (`owner/repo #n`),
the subtitle (which is where `@author` and the reason words live) — plus one new field, the
PR's **head branch**, which only Your PRs can carry (D3). The typed text is parsed as a
handle first (number / repo / repo+number / branch / URL / text); the handle kind decides the
match rule and what the trailing GitHub row offers.

Header while text is present: `N of M` (matched of admitted rows). Lanes with zero matches
disappear (header and rows); lanes with matches keep their 240pt cap and in-place scroll
(`IslandGeometry.perPaneMaxHeight`). When nothing matches, one line says so and the GitHub
row is the only row left. `esc` with text clears it and every lane returns; `esc` on an empty
line puts the island away as today. `↑ ↓ ⏎` walk and open the narrowed rows exactly as today.

## Decisions

- **D1 · input model — the key session accumulates characters; no NSTextField.**
  Reason: the moment a field editor is first responder, `HUDPanel.keyDown` stops firing and the
  whole ratified ↑↓⏎esc/space map would have to be re-implemented in `doCommandBy`
  (`LedgerCardView.swift:290-301` is the precedent and the warning). Keeping one router keeps
  the key map in one place (Gates.json G-keyboard). `KeySession` gains `type(Character)`,
  `deleteBackward`, and `paste` intents; the query is a `String` in the controller, drawn as a
  label in the header with a caret glyph. ⌘V is handled explicitly in
  `HUDPanel.performKeyEquivalent` (`HUDPanel.swift:84-99`) by reading `NSPasteboard.general`
  — today the probe finds no editable responder and falls through, so nothing is stolen.
  Cost accepted: no cursor movement inside the query, no text selection. A jump line does not
  need them.
- **D2 · fallback row — ⏎ opens a github.com search URL; no in-app resolution.**
  Reason: zero new network paths, no in-flight state on the glass, nothing for `idle-footprint`
  to audit (`loop/PRESSURE.md:63-70`). A branch query opens `search?q=is:pr+head:<branch>`;
  a number opens `search?q=<n>+is:pr` scoped to the user's login where the parser can tell;
  a repo opens the repo; a URL opens itself; free text opens `search?q=<text>`. Resolving in
  place (one search call on ⏎, land on the PR) is the named follow-up.
- **D3 · branch matching is Your-PRs only.** `PullRequestPulse.openPRsQuery`
  (`PullRequestPulse.swift:163-166`) gains the scalar `headRefName` on the same node —
  same GraphQL call, no extra points (`GitHubClient.swift:432-437`). Needs-you and Inbound
  come from `search/issues` and the notifications API, which carry no head ref; they never
  match a branch. The sketch's "resolving" state already admits this thin spot; D2 covers it.
- **D4 · space.** Space peeks when the query is empty (today's ratified mapping, untouched)
  and types a space when the query has text. Peek on a narrowed row is reached by `→`
  while text is present. Reason: the collision is real (`KeySession.swift:22` maps 49 to
  peek) and context is the smallest honest resolution; the alternative, moving peek
  permanently, would amend a ratified map for the empty-query case where nothing changed.
- **D5 · laws.** `docs/TOPOLOGY.md:36-37` (L1) and `:56-58` (L2) are edited in the same PR.
  A typed narrowing is a third boundary beside Admission and Input gating (`:45-54`):
  transient, user-directed, reversible on `esc`, its residue the `N of M` header. L2 gets
  the E2-style clause: the pill, gauge and glyph keep counting the admitted set while the lane
  shows the narrowed one, and the header count is the disclosure. L4 ("no zero") is honoured
  by never printing `0 of M` — the nothing-matches line takes its place. Law assertions in
  `Tests/GithudCoreTests/main.swift` change in the same commit (`TOPOLOGY.md:253`).
- **D6 · mouse summons stay keyboard-chromeless.** Only a ⌃⌥G session can start a query
  (the "F8 boundary", `AppDelegate.swift:157-178`). A click-summoned island shows no jump
  line and takes no letters, because it is not key.
- **D7 · modified chords stay unconsumed** except ⌘V (paste) and ⌫. ⌘-letters, ⌥-letters,
  keypad Enter (76) fall through exactly as ratified
  (`2026-07-06-designer-session-agenda.md:179-190`).

## Acceptance criteria

1. ⌃⌥G, type `214`, ⏎ → `pro-vi/githud#214` opens in the browser and the island is put away. No mouse.
2. Typing the head-branch name of one of your open PRs narrows to that PR with **no network call** (the branch arrived with the last poll).
3. Text that matches nothing shows the nothing-matches line and one GitHub row; ⏎ on it opens the URL the handle kind prescribes (D2).
4. `esc` with text clears it and restores every lane; `esc` on an empty query puts the island away as today.
5. `↑ ↓` walk only the rows drawn after narrowing; the ink-bar focus, ⏎ and the open-then-hide path behave as today. A selection can never land on an undrawn row (L3).
6. Header shows `N of M` while text is present and never `0 of M`; zero-match lanes collapse; matching lanes keep the 240pt cap.
7. Printable keys, ⌫ and ⌘V build the query; every other modified chord and keypad Enter fall through as today. Space follows D4.
8. A poll tick while text is present re-narrows against the new rows and keeps the text and the selection by stable row id.
9. Collapsed pill, summon chord, mouse-summoned island, and the lanes' rendering with an empty query are pixel-unchanged.
10. `GithudCoreTests` cover the handle parser, the narrowing over fixture rows, the widened key map (the assertion at `main.swift:4456` that letters fall through is rewritten, not deleted), and the edited law assertions.
11. The focus-non-theft input-routing proof is re-cut for the widened session (`loop/PRESSURE.md:22-37`: an event-handling change "owes proof the HUD doesn't interrupt the foreground app"; absent it the package parks unmerged).
12. `README.md:185-197` gains a "Jump to a row" line and a two-stage `esc` wording.

## Out of scope (deliberately)

- Option B, Option C, any second global hotkey.
- Copy-link / copy-branch / copy-checkout chords. Natural follow-up once the query exists.
- In-app resolution of a handle the island does not hold (D2 names it as the follow-up).
- Issue queries by label, GitHub search grammar beyond the handle table.
- Fuzzy matching, match highlighting in row text.
- Branch names on Needs-you or Inbound rows (D3).

## Build-time spec amendments (recorded, not silent)

### Landed U4 amendments

The owner reported “the white thing looks ugly on open and no inline input on invoke.”
The header now shows “Type to jump…” when a keyboard session begins; mouse summons
keep the ordinary header. Selection uses a background highlight instead of a white
edge strip. Native view renders exposed an overflowing no-match paragraph, which was
removed. Option–Backspace was subsequently added using AppKit word boundaries.
These landed changes still use a label and manual character accumulation.

### Native editing — replacement plan (approved 2026-09-05, session-snapshot shape)

**Objective:** look up a PR in the existing island while typing, selecting, correcting,
and pasting text with normal macOS editing behavior.
**Origin:** conversation — punctuation and Option–Backspace exposed the cost of manual
editing; the owner requested `/architect` after discussing native fields.
**Date:** 2026-09-04, revised 2026-09-05. **Status:** approved. The 2026-09-04 draft kept
a persistent panel root so the editor could survive every poll and appearance refresh.
The owner chose the smaller shape recorded here instead: the island's existing
rebuild-per-render path stays untouched outside a session; inside a session the
rows are a snapshot taken at summon, poll and appearance updates are deferred to
session exit, and only the query's row-only update runs while the editor is alive.
**Depth:** Deep for editor ownership, responder lifecycle, and focus proof; no stored
format, dependency, network endpoint, or global shortcut changes.
**Inspected base:** `db22bf4` on `main`.

**Precedence:** this replacement plan is the build entry point. The earlier
Decisions, Architecture Decision, Scope Boundaries and U3/U4 instructions below are
historical wherever they conflict with the tables here. U1–U4 are already implemented,
not work to repeat. Their acceptance obligations remain, revised below.
Execution order is **U6 → U5**: one native-input change, then the outstanding
laws, README and final proof. Former U7/U8 are folded into U6; existing IDs are not
renumbered. Do not recreate `docs/plans/`.
The amendments section remains the editable plan home; the older record is retained
rather than silently rewritten.

**What the snapshot shape trades away.** Rows shown during a session are the rows
that existed at summon, until the session ends. That is not "a few seconds stale":
a session left open stays at its summon-time state for as long as it is open. This
explicitly replaces AC8 (a poll tick re-narrows against new rows mid-query). What it
buys: no change to how the island renders for mouse summons, the collapsed pill, cards,
or theme switches, and no persistent-root refactor. **Build record (2026-09-08).** U6 uses the native field/editor and row-only updates
over `JumpSnapshot`. U5 live input checks exposed and corrected a competing header
spacer that clipped the editor when the count appeared, and missing accessible row
selection. The final 60-second recording exercises global summon, native editing,
result selection, Escape hand-back, mouse non-key behavior, and Return/browser exit.
The evidence record is `loop/evidence/wp6k-native-input.manifest.json`; it pins the
source and artifacts and distinguishes local tests from live observations. Real IME
candidate UI, VoiceOver speech, and a human-hand recut remain explicitly unwitnessed.

#### Background and evidence

- `HUDPanelController.swift:690` rejects modified input before the Core key map;
  manual append, deletion, word deletion and paste follow. This caused the reported
  editing gaps. `JumpQuery` is still the authority for matching and destinations.
- `IslandContentView.swift:138` builds the header in its initializer.
  `HUDPanelController.swift:1175` constructs a new island on every result render;
  `present` at line 1286 detaches its previous subtree. A native field cannot
  survive that, so during a session that path must not run; the query needs its
  own row-only update that leaves the header attached.
- Narrowing reads the live model arrays: `beginKeySummonSession`
  (`HUDPanelController.swift:627`) and `render()` (`:1150`) both call
  `query.narrow(radar: model.radarRows, …)`. `AppModel` receives poll rows before it
  notifies the controller, so freezing renders alone would leave the next query edit
  narrowing against rows the user has not seen. The session therefore captures its
  rows and matching context at summon and uses that snapshot for filtering, counts,
  selection and destinations until it ends.
- Poll-driven changes reach the controller through `handle(_:)`
  (`HUDPanelController.swift:150-164`) as a coalesced `setNeedsRender()`. Theme,
  Reduce-Transparency and Increase-Contrast changes (`:165-168`) call `buildSurface()`
  (`:285`), which replaces `panel.contentView`, and then `renderNow()`. Both routes
  destroy a live editor; both are deferred while a session is live and applied once
  at session exit. Polling itself continues unchanged.
- Screen-parameter changes (`:137-141`) also arrive as `setNeedsRender()`; `present()`
  recomputes the frame origin, and the island height is clamped to the screen at
  render time (`min(fittingHeight, screenHeightCap())`, `:1213`, and the peek reflow
  at `:1437`). During a session a screen change must still keep the panel on-screen
  and fitting, so it may re-anchor the panel and resize the island and its scroll
  panes; it must not replace the header or the editor.
- Session-ending choke points stay immediate and unchanged: `hide()` (`:551`),
  `setExpanded` (`:866`), a card taking the surface (`:960`, `:1012`, `:1053`), the
  ledger card (`:188`), and key loss (`:109`). Their order matters for the replay:
  `setExpanded` ends the session *before* it flips `expanded` and calls `renderNow()`,
  and the card branches end it *inside* `render()`. A replay inside
  `endKeySummonSession` would therefore render the expanded island before a collapse,
  render twice, or nest a render inside a render. So teardown only clears session
  state and marks the deferred work as owed; the enclosing transition applies it after
  establishing its final state.
- The preference controls drawn on the island ("show gone quiet", "show held back",
  "just cleared", hide drafts, unfold an owner) do not end a session today;
  they flip a model preference that reaches `handle(_:)` in the same coalesced group
  as poll data (`:151-153`). Deferring that group would let a click change the
  preference without changing what is displayed. They are deliberate user actions,
  so they end the jump session first, then apply and render immediately.
- `LedgerCardView.swift:145` updates in place and lines 287–301 use native
  text-change and command delegates. Its theme rebuild preserves only text and
  deliberately loses focus; that part is not a pattern for the jump field.
- `HUDPanel.swift:87` already forwards standard Edit commands through the responder
  chain because the app has no main menu. Its query-specific paste interception
  bypasses selection and must go. Redo needs an explicit Command–Shift–Z route.
- `HUDPanel.swift:61` and `IslandContentView.swift:589` currently report result-row
  accessibility focus. Native editing requires actual editor focus and separate
  result selection.
- The recorded iTerm2/CotEditor/Maccy/Strongbox precedent is about releasing key,
  not evidence for avoiding text fields. Current
  [Maccy SearchFieldView](https://github.com/p0deje/Maccy/blob/master/Maccy/Views/SearchFieldView.swift)
  uses a plain native text control; its
  [KeyHandlingView](https://github.com/p0deje/Maccy/blob/master/Maccy/Views/KeyHandlingView.swift)
  handles app commands and defers during composition. We are using this ownership
  pattern, not copying its particular shortcuts.
- Apple's [control command delegate](https://developer.apple.com/documentation/appkit/nscontroltexteditingdelegate/control(_:textview:docommandby:))
  allows selective command handling and returns false for native handling.
  [Field editors](https://developer.apple.com/documentation/appkit/nstextview/isfieldeditor)
  treat Tab and Return as editing commands rather than ordinary text.
- **Executed, limited evidence:** a temporary AppKit probe in an unshown window
  created an actual field editor, replaced a selected word with punctuation,
  executed native undo/redo, dispatched move-down and Return through the control
  delegate, and preserved the editor/selection/marked range while replacing a
  sibling view. Its composition guard returned false without opening a result.
  No visible window or global events were used. It did not exercise this controller,
  a real IME candidate window, a material change, or focus return. Recreate those
  assertions in the committed native runner; the temporary probe is not a build input.
- The previous computer-use runtime returned `process is not defined` before any
  app capture. Recheck available tooling at build time; do not equate that failure
  with a passing focus test.

#### Requirements and prior-contract replacement

| ID | Required outcome | Prior obligations carried forward |
|---|---|---|
| R1 | Native insertion, uppercase, punctuation including !@#$, selection replacement, horizontal and word movement, character/word deletion, cut/copy/paste, undo/redo, and text composition | Replaces D1 and the printable-input part of AC7; includes the reported modifier bugs |
| R2 | The header is an inline borderless editor immediately after keyboard summon; ordinary mouse summons have no editable query control | AC9 as amended, D6; current header dimensions, placeholder and background selection treatment |
| R3 | One narrowed row set feeds drawn results and keyboard traversal; local matching and GitHub fallback behave as before | AC1–3,5,6,8, O1, O2, O4, O5, D2, D3 |
| R4 | Native editing commands coexist with result navigation using the command table below | Revises D4/D7 and AC4/7; retains keyboard peek through Option–Return |
| R5 | Editor identity, selection, marked text and undo survive query edits and peek reflow. Poll, theme, transparency and contrast updates are deferred while the session is live and applied at exit; the session's rows are the summon-time snapshot | Replaces AC8 (live re-narrowing mid-query is given up); the island's rendering path outside a session is unchanged |
| R6 | Key acquisition is explicit, mouse summons never acquire it, every exit releases editor ownership, and ledger editing stays separate | D6, AC9/11; no app activation |
| R7 | Diagnostics never log query contents; native accessibility focus is truthful and result selection remains discoverable | O3, AC5/11; overrides the old AX row-focus proof expectation |
| R8 | Tests, README, law text/assertions and a current input-routing artifact match the shipped behavior | AC10–12 and original U5; no acceptance item is discarded |

D2 and D3 stay unchanged: no query-triggered network request and no new branch
fetch for Needs you or Inbound. D5's law/assertion coupling remains binding.
The query parser and destination semantics are not being redesigned.

#### Naming ledger

| Role / meaning | Existing term | Chosen name | Owner / placement | Status | Consumer / reason | Sibling disposition |
|---|---|---|---|---|---|---|
| Header containing editable query and count | JumpLineView | `JumpLineView` | `Sources/GithudApp/IslandContentView.swift` | reuse, implementation changes | IslandContentView; native tests | LedgerCardView retains its secure input policy |
| Query interpretation snapshot | JumpQuery | `JumpQuery` | `Sources/GithudCore/JumpQuery.swift` | reuse | Controller, matching, destination | Remove its App-layer editing extension |
| Result action requested by native command routing | KeySession.Intent | `KeySession.Intent` | `Sources/GithudCore/KeySession.swift` | reuse, narrow cases | JumpLineView delegate and controller | Delete text-editing cases; no parallel command vocabulary |
| The rows and matching context captured at summon, used for every narrowing in the session | none (render reads `model.*Rows` live) | `JumpSnapshot` | `Sources/GithudCore/JumpQuery.swift`, one value owned by the controller beside `jumpQuery` | new | Narrowing, count, selection walk and destination all read it; nothing in a session reads `model.*Rows` | Zero-dependency value type so narrowing over a snapshot is testable headlessly |
| Model and appearance updates held back while a session is live | none | `deferredWhileJumping` | Private flag(s) in `HUDPanelController.swift` | new | `handle(_:)` records instead of rendering; the transition that ended the session replays the newest state after reaching its final state | No queue: only "a render is owed" and "a surface rebuild is owed" are remembered |
| Native field editor with undo history restricted to one query session | Window's shared field editor | `JumpFieldEditor` | `Sources/GithudApp/IslandContentView.swift` | new | The query must not share undo history with the secure ledger or later sessions | Native NSTextView subclass for this lifetime boundary only; ledger keeps its default editor |
| Selected result | keySelection | `keySelection` | `HUDPanelController.swift` | reuse | View highlighting and result actions | Never becomes text caret or AX editing focus |

No new Swift module, dependency, generic editor framework, or search service.
The existing file and type names already describe the jobs.

#### Architecture Decision

**Approach:** put a borderless ordinary `NSTextField` inside `JumpLineView`.
AppKit owns editing, the caret, selection, composition, and undo. The controller
owns a `JumpQuery` snapshot used for narrowing, not an independently edited buffer.
A text-change callback reads native text and updates results; it never assigns the
snapshot back to the field during routine rendering.

Keep the expanded `IslandContentView`, its header and its query field attached for
the whole session. Inside a session the only thing that changes the island is a
query edit, and that runs a row-only update: the rows below the header are rebuilt
from the session's `JumpSnapshot`, the header count and hint are updated in place,
the header itself is never replaced. Poll and appearance changes do not touch the
island while the session is live; `handle(_:)` records that a render or a surface
rebuild is owed. One owner applies the owed work: the transition that ended the
session (collapse, hide, card arrival, key loss, or the in-place esc/⏎ exit), after
it has established its own final state, through the existing `buildSurface()` and
`render()` path. Teardown itself never renders. A screen change during a session
re-anchors and, if needed, resizes the island and its scroll panes in place. The
island's own preference controls end the session and render immediately. Outside a
session nothing changes: the island is still rebuilt per render exactly as today.
Keep both the view and the keyboard walk downstream of the controller's existing
single narrowing computation, now fed from the snapshot. No result-row diff engine
is needed: rebuilding the small result subtree is sufficient.

Reuse the ledger's delegate-and-in-place-update pattern, not its secure field or
its text-only theme stash. Reuse the panel's standard Edit-action routing; remove
query-specific clipboard reads and manual text mutation. Use a session-owned JumpFieldEditor, configured as a native single-line field
editor with undo enabled and its own UndoManager. HUDPanel supplies it through
its field-editor lookup only for this session's exact query field; every other
client uses the existing native editor. This subclass owns undo lifetime, not
keystroke interpretation.
The native editor's delegate translates only owned commands to `KeySession.Intent`;
all other text operations remain with AppKit.

**Why this wins:** extending `KeySession.intent` and the controller's string edits
would require implementing selection, insertion positions, composition, clipboard
replacement and undo. `NSTextField` supplies those facilities. `NSSearchField`
adds search/cancel chrome not needed in this header; a SwiftUI wrapper adds a second
UI framework to an AppKit view. Retaining/reparenting a field across whole-island
rebuilds does not protect its attached editor. The rejected alternative, a persistent
panel root that survives every refresh, protects the editor by changing how the island
renders for everyone; the session snapshot protects it by not refreshing the island
while the editor is alive, and leaves everyone else's rendering untouched.

**Consequences:** rows shown during a session are fixed at their summon-time state
until dismissal. Space and horizontal arrows become editing commands. Native caret
blinking and native IME candidate UI are allowed during editing; the no-idle-timers
rule prohibits new app-owned repeating work, not the operating system's focused
editor. The existing mouse layout and collapsed pill remain the baseline.

**D1, restated rather than discarded.** D1's intention was clear keyboard ownership:
one place decides what a key does. That survives. Its implementation, manual
accumulation in the key session, is replaced by native editing. Text belongs to the
editor; result commands belong to the controller through the field's command delegate.
Space belongs to editing.

**Approval means:** native input replaces D1's implementation; the following keyboard
table replaces D4/D7; the session's rows are a snapshot and poll/appearance updates
are deferred to exit (replacing AC8); input-routing proof remains required rather
than being inferred from renders.

#### Keyboard and input contract

| Input/state | Owner and effect |
|---|---|
| Printable characters, Shift/Option-produced text, Caps Lock, dead keys, Unicode | Native editor; no printable-character allowlist |
| Left/Right, modified horizontal arrows, selection shortcuts, Backspace and Option–Backspace | Native editor at its real insertion point or selection |
| Space, including an empty field | Native text insertion; no peek |
| Unmodified Up/Down outside composition | Select previous/next result, clamped; editor retains keyboard focus |
| Unmodified Return or keypad Enter outside composition | Open selected result once, then end session and collapse |
| Option–Return outside composition | Peek selected result through its existing action; no insertion or open |
| Escape outside composition, any raw text including spaces | Clear via native editing so undo can restore it; keep session |
| Escape outside composition, truly empty field | End session and collapse |
| Commands while marked text exists | Defer to AppKit/input method; no result navigation, peek, open or dismissal |
| Command–A/C/X/V/Z and Command–Shift–Z | Shared native responder Edit actions, including redo; query-specific paste code removed |
| Tab/Shift–Tab | Native key-view traversal; the query is the sole key-view stop in this list session, so traversal returns to it; no inserted tabs and no loss of typing |
| Other modified commands | Not treated as app result actions; leave to native responder behavior |
| Pointer click/drag inside query during session | Native caret placement and selection; no row click flattening over the field |
| Mouse-summoned island outside session | No editable query control and no key acquisition |

Ignore AppKit's incidental numeric-pad/function flags when classifying plain arrow
or keypad keys, not Shift/Control/Option/Command. Use the field delegate's
selectors and the actual event only to distinguish owned result commands.
Do not install a broad event monitor that consumes native editing before the field.
If Option–Return arrives as an alternate newline selector, recognize that selector
in the same delegate; do not add a second independent keyboard router.

Whitespace is deliberately two facts: raw field text determines clear-vs-dismiss
and the Escape hint; `JumpQuery.isEmpty` determines identity narrowing and absence
of the GitHub row/count. Never trim or rewrite the editor to reconcile them.
Use the native single-line field's paste behavior; test embedded line breaks against
an ordinary native field. Do not append a second flattened clipboard string.

During composition, native marked text is authoritative. Results use the latest
text snapshot delivered by native change notifications; interim text may narrow
locally if a notification exposes it. No query result action is allowed while
marked text remains. A composition commit publishes its final text. Poll updates
never reach the island during a session, so nothing can commit/cancel composition
or write into the field from the model side.

#### Representation and integration contracts

| Meaning | Authority | Derived consumers / boundary | Guard |
|---|---|---|---|
| Current text and edit state | Native field editor while editing | Control text-change notification → controller's JumpQuery snapshot | Native editing integration tests; no stringValue echo on refresh |
| Query meaning | JumpQuery | Narrowed rows, destination, count | Existing parser/narrowing suites |
| Rows and matching context during a session | JumpSnapshot, captured once at summon | Narrowing, count, KeySelection walk, knownRepos, destination | Core test: a poll that changes `model.*Rows` mid-session changes nothing the session computes; exit applies the newest rows |
| App result commands | KeySession.Intent | Field delegate translates native selectors; controller executes an exhaustive switch | Native command-routing tests; unknown selectors return false |
| Selected result | KeySelection | Highlight, open, peek, accessible selection information | Stable-ID rebuild and walk/render tests |
| Key eligibility | Controller session/card lifecycle | HUDPanel flag and actual first responder | Acquisition/teardown and mouse/card tests |
| Edit history | Native undo operations in JumpFieldEditor | Query editor only; default field editor for ledger | Same-session undo continuity and cross-session isolation tests |

There is no new persistence or wire representation.
The control delegate's input is `NSControl`/`NSTextView`/`Selector`, not the
existing `NSEvent` callback. Its Boolean result means handled-or-defer, while the
controller needs a result intent. **U6 owns this integration change**;
matching return types do not establish that the old callback can be reused.
The temporary probe executed the native delegate path. Integration with HUDPanel's query-only field-editor lookup and the row-only update path remains unverified.

Directional flow, not an implementation signature:

```text
keyboard summon → capture JumpSnapshot → attach jump field → grant key eligibility → acquire key/editor once
native edit → text-change callback → JumpQuery × JumpSnapshot → one Narrowed result
                                            → replace rows below the header + rebuild KeySelection + update count
native command → composition check → owned result intent → controller action
poll/theme/a11y during session → model updates as today; controller records "render owed" / "surface rebuild owed"; island untouched
screen change during session → re-anchor panel; resize island and scroll panes in place if the screen shrank; header/editor untouched
island preference control during session → end session (teardown below) → apply preference → render immediately
teardown (any exit) → clear session ownership and callbacks → detach editor → discard undo → release key; NO render here
enclosing transition (collapse, hide, card, key loss, or the esc/⏎ exit itself) → reach its final state
                                             → replay owed surface rebuild and render once from the live model
```

#### Program obligations

O1–O5 from the original plan remain requirements; O3 covers every new callback.

- **O6:** While a session is live, query edits and peek reflow preserve the field,
  attached field editor, selected range, marked range, and undo continuity, and no
  poll, theme, transparency, contrast or screen-parameter change replaces or reparents
  the island's header. A screen-parameter change may re-anchor the panel and resize
  the island and its scroll panes in place. The deferred updates are applied exactly
  once, from the live model, by the transition that ended the session after it has
  reached its final state; never by teardown itself, never earlier, never nested
  inside a running render.
- **O7:** `jumpQuery != nil iff keySelection != nil iff jumpSnapshot != nil`; all three
  transition synchronously at session boundaries. An editable JumpLineView is
  available iff that session is live on the list surface after reconciliation.
  Acquisition-pending state cannot execute result commands; any failed acquisition
  clears all three values and replays nothing (nothing was deferred yet).
- **O6a:** Nothing computed during a session reads `model.radarRows`,
  `model.inboundRows` or `model.pulseRows`; narrowing, count, walk, known repos and
  destination read `jumpSnapshot`. Session-ending choke points (hide, collapse, card,
  ledger, key loss) stay immediate and are never deferred. The island's own
  preference controls (stale, held back, just cleared, drafts, owner unfold) end
  the session before the preference changes, so a click never changes a preference
  without changing what is displayed.
- **O8:** Native editing is the only text mutation authority. Remove manual type,
  delete, word-delete and paste paths, their obsolete Intent cases and key map.
  Clear-query uses a native undoable edit; teardown discards history.
- **O9:** Composition suppresses only app result actions, never native text
  operations. Unrecognized commands remain unconsumed.
- **O10:** AX focus reports the actual text editor. Result highlighting and selected
  result announcements never impersonate an editing-focus change.
- **O11:** Query undo history cannot be reached from the next session or ledger.
  Query-specific callbacks cannot observe the secure ledger's text.
- **O12:** User edits cause local result work only. No added fetch, debounce timer,
  repeating animation or polling loop is introduced. Native caret behavior is scoped
  to editing and disappears on teardown.

#### State-action contracts

All callbacks execute on the main thread. No durable query or editor state is
written in any cell. Each row names observation, transient effect, external effect,
repeat/race rule and locking test; serialized native edits are not deduplicated.

| Action × state | Observation and transient effect | External effect | Repeat/race rule | Test |
|---|---|---|---|---|
| Summon × ordinary expanded/collapsed list | JumpSnapshot captured, editor appears, key/editor acquisition is checked; initial result selected | Existing panel presentation only | Session state set before reentrant callbacks; failed acquisition retires it | session-acquires-native-editor |
| Poll × editing or composing | Model rows update; island, editor, selection, marked range and undo untouched; "render owed" recorded | None | Repeated polls collapse to one owed render; a poll cannot force marked text to commit | poll-deferred-during-session |
| Theme / transparency / contrast × editing | Model updates; no `buildSurface()`, no render; "surface rebuild owed" recorded | None | Repeated flips collapse to one owed rebuild | appearance-deferred-during-session |
| Screen parameters × editing | Panel re-anchored; island height and scroll-pane heights re-clamped in place if the screen shrank; header, editor, selection and undo untouched | Existing placement only | Same coalesced path as today | screen-change-keeps-panel-on-screen-and-fitting |
| Island preference control × editing | Session ends (teardown), then the preference applies and the island renders immediately from the live model | Existing preference persistence | The click is the transition; it owns the replay | preference-control-ends-session |
| Exit × owed updates | Teardown clears session state and detaches the editor without rendering; the enclosing transition (collapse, hide, card, key loss, esc/⏎ exit) renders the latest rows and appearance once after its final state | Existing order-out release if still key | Owed flags cleared before the replay so a reentrant change is not lost; no render nested in a render | exit-applies-deferred-updates |
| Edit × live session | Native edit observed, query snapshot/results update; caret follows native edit | Metadata-only diagnostics if enabled | Reentrant result rendering never writes text back | native-edit-operations |
| Escape × raw nonempty field | Native clear, identity results, session remains; undo can restore | None | Next Escape sees actual empty field and dismisses | whitespace-and-clear-undo |
| Command × composing | Native input method receives command; result action count stays unchanged | Native candidate UI only | Commit/cancel notification publishes final state before later result commands | composition-command-priority |
| Return × selected row or fallback | One selected destination opens, session retires, island collapses | Browser open through existing path | Reentrant resign callback sees retired/inactive session; no duplicate open | native-open-once |
| Return × no actionable ID | No destination opened; session ends as existing open path does | Collapse/release only | Repeated late callbacks cannot open stale selection | empty-open |
| Exit/card/key-loss × editing or composing | Query/selection retired, editor detached, history discarded | Existing order-out release if still key | Late native end-edit callbacks ignored by sender/session identity | editor-session-teardown |
| Edit or command callback × ended session | No query reconstructed and no row acted upon | None | Sender/current-session checks reject obsolete notifications | late-editor-callback |
| Mouse summon × no session | Ordinary header, no editable query view, never-key list | Existing presentation only | Letters stay outside the island | mouse-summon-never-edits |
| Edit shortcut × ledger card | Native secure-field behavior; no jump callback/history | Existing ledger behavior only | Query route absent; never inspect a real token during testing | ledger-edit-isolation |

Additional states explicitly covered: secure-input/key acquisition refusal; appearance
change while marked text is active. Neither is treated as an ordinary successful
refresh. Production checks fail by retiring an unusable session or declining the
result action, not by assertions that leave a false focus cue in release builds.
Escape must clear spaces before dismissing even when narrowing is already identity.

#### Implementation units

##### U6. Native input, editor lifetime and verification

- **Goal:** Replace manual character accumulation with normal native editing in
  the existing header, preserving that editing state while the query narrows a
  summon-time snapshot of the rows. The session-scoped deferral and its tests are
  part of this one end-to-end unit; the rendering path outside a session is not touched.
- **Requirements:** R1–R7 and the verification part of R8; O1–O12 including O6a.
- **Dependencies:** Landed U1–U4; verify current main rather than repeating them.
- **Files:** Modify `Sources/GithudApp/HUDPanelController.swift`,
  `Sources/GithudApp/IslandContentView.swift`, `Sources/GithudApp/HUDPanel.swift`,
  `Sources/GithudCore/JumpQuery.swift` (add `JumpSnapshot`),
  `Sources/GithudCore/KeySession.swift`, `Sources/GithudCore/PlainWords.swift`.
  `Sources/GithudApp/IslandSurfaceFactory.swift` is not expected to change.
  Test through `Tests/GithudCoreTests/main.swift`,
  `Tests/GithudAppSnapshots/main.swift` and `Tests/GithudAppSnapshots/run.sh`.
  Existing `scripts/ax-drive.swift` remains read-only reference.
- **Approach:** At summon, capture `JumpSnapshot` (the three row arrays, the pulse,
  inbound and lens preferences, and `selfLogin`) and narrow it for the initial
  selection. While the session is live, `handle(_:)` records an owed render for the
  data cases and an owed surface rebuild for the appearance cases instead of running
  them; the screen-parameter case still re-anchors the panel and re-clamps the island
  and scroll-pane heights in place. A query edit runs a row-only update on the
  attached island: rebuild the rows below the header from the snapshot, update the
  count and hint in place. Teardown (`endKeySummonSession`) detaches the editor and
  clears the session values and never renders; the transition that called it
  (`setExpanded`, `hide()`, the card branches of `render()`, key loss, or the esc/⏎
  exit path) replays the owed rebuild and render once after its own final state is
  set, so a collapse never paints the expanded island first and a card branch never
  nests a render. The island's preference callbacks (`onToggleStale`,
  `onToggleHeldBackInbound`, `onToggleJustCleared`, `onToggleDrafts`,
  `onToggleFoldedOwner`) end the session before forwarding the click, so their
  preference change renders immediately. Install the native field, delegate, session-scoped
  undo and keyboard table together; feed changes through the existing single narrowing
  call, now over the snapshot. Remove manual input/paste paths and correct
  accessibility focus. There is no separately shipped rendering foundation or
  qualification unit.
- **Patterns to follow:** LedgerCardView's in-place apply and native delegate;
  HUDPanel's shared Edit dispatch; existing scroll/peek carry, KeySelection,
  row open/peek actions, surface/grain ownership and native test runner.
- **Test scenarios:**
  - *Happy path:* punctuation/uppercase, insertion in the middle, selection
    replacement, word deletion, native paste, undo/redo; results track text.
    Up/Down changes selected result without moving editing focus; Return opens once.
  - *Editing edges:* spaces-only clear-vs-dismiss and hint; clear/undo/clear/dismiss;
    long text, keypad Enter, native Tab traversal, unowned modified commands,
    Unicode and marked-text composition. Composition commands never act on results.
  - *Lifecycle edges:* edit, peek and interrupted morphs preserve editor identity,
    selection, marked range and undo. A poll that adds, removes or changes rows
    mid-session changes nothing on screen and nothing the session computes; a theme,
    transparency or contrast flip mid-session changes nothing on screen; moving to a
    shorter display re-anchors the panel and shrinks the island and its scroll panes
    while the header, editor, selection and undo stay intact; clicking "show gone
    quiet", "show held back", "just cleared", hide drafts or unfold an owner
    mid-session ends the session and shows the new preference immediately; session
    exit by esc, ⏎, hide, collapse, card or key loss renders the newest rows and
    appearance exactly once, after the transition's final state (a collapse never
    paints the expanded island first; a card arrival never nests a render).
    Row maps, folds, tails, scroll and peeks remain consistent. Mouse/pill renders
    and hit targets are pixel-unchanged, since their path did not change.
  - *Error paths:* refused key/editor acquisition retires the session; late callbacks
    cannot recreate it; undo cannot recover a previous query or reach ledger history.
    Missing permission/tooling or blank capture is unverified evidence, not a pass.
  - *Integration:* exercise production native callbacks in isolated fixture windows
    with captured destinations and synthetic text, not only Core intent methods.
    Then use a contained fixture session and disposable foreground marker document
    to witness global summon, editor-only input, Escape focus return, mouse non-key
    behavior and external AX focus. Test Return/browser focus separately; opening a
    browser legitimately changes the foreground app.
- **Verification:** Native editing, the session snapshot, the deferral and O1–O12
  (including O6a) hold through the relevant tests. Remove the artificial caret,
  character allowlist, manual deletion helpers and query paste interceptor. Rewrite
  the existing key-map suite for result commands. Report local/native and live focus
  evidence separately.
- **Runtime evidence:** unverified — extend and run the native runner against the
  production integration, then the authorized live fixture exercise. The isolated
  planning probe, old renders and WP-6k recording do not prove this integration.
- **Checkpoint:** auto — Core suite, native integration/render checks and app build;
  fix observed failures before landing this one source commit. Attempt the contained
  live exercise when its target/permission conditions hold. If live evidence cannot
  be obtained, record exactly what is unverified, continue independent U5 preparation,
  and hold U5's final proof commit. Green local checks do not certify global input.
  Never synthesize events into an unknown or unrelated app.

##### U5. Reconcile laws, README and the final proof record

- **Goal:** Complete the original pending unit using the native editor's real behavior.
- **Requirements:** R3, R7, R8; original AC10–12 and D5.
- **Dependencies:** U6. Drafting can proceed while live evidence is unavailable;
  recording and the final commit require the implemented editor and current proof.
- **Files:** Modify `docs/TOPOLOGY.md`, `README.md`,
  `Tests/GithudCoreTests/main.swift`, and this agenda's amendments section.
  Create only the authorized new input-routing proof artifact and manifest in
  `loop/evidence/`; no other loop edits.
- **Approach:** Carry the original L1 narrowing boundary, L2 admitted-vs-narrowed
  disclosure and L3 destination-walk explanation into law text and assertions in
  the same commit. Document the native editing/peek/Escape contract. Record the final
  contained input-routing exercise and pin its evidence
  to tested source revision/fingerprint and artifact hashes.
- **Patterns to follow:** TOPOLOGY's law/assertion rule; README keyboard table;
  WP-6k manifest's witnessed/not-witnessed distinction.
- **Test scenarios:** *Laws:* input = matched plus unmatched; existing folds/preferences
  still account for their own rows; pill/glyph use admitted rows; keyboard walks the
  drawn set plus the trailing destination; never zero-of-total. *Docs/proof:*
  every claimed behavior has a relevant witness; real VoiceOver speech is not
  claimed from AX queries alone.
- **Verification:** Law text and assertions agree, README no longer promises
  Space/right-arrow peek or label-only input, README states that the rows stay as
  they were at summon until the session ends (AC8's live re-narrowing is gone), and
  the current input-routing record names both successes and any still-unverified
  human observation.
- **Runtime evidence:** the actual recording of U6's native editor; capture any
  missing live witnesses here. Test/build success and old artifacts are insufficient.
- **Checkpoint:** gate — current complete input-routing evidence plus both scripts
  green → commit/push and close this plan; missing recording/assistance → hold this
  commit, finish independent local docs/tests, report the exact missing witness.
  No bare user “looks fine” is substituted for a missing recording.

#### Scope boundaries and system-wide impact

- Same island, header geometry, summon chord, parser, lane ordering and GitHub URL
  fallback. No palette, resolver, fuzzy matching or match highlighting.
- No stored query history, persistence change, new dependency, token access or
  new network path. Existing pending follow-ups stay recorded in the original
  Deferred to Follow-Up Work section; none is absorbed here.
- Pointer peek and the row highlight survive. Only the keyboard peek binding changes.
- Interaction chain: summon → native first responder → control delegate →
  query/result update or app command → existing row action → session teardown.
  Native edits are synchronous; model renders retain their existing coalescing.
- Surface, grain and morph code is not touched: the island's rendering path outside
  a session is the one that ships today. Inside a session the island is not
  re-rendered at all except by the query's row-only update.
- The rows a session shows are its summon-time snapshot until dismissal. A row
  opened from the snapshot may have changed on GitHub meanwhile; the destination is
  a URL, so it still opens the right thing.
- Ledger's secure editor continues through the shared Edit router with its own
  delegate and default undo scope. Never test it with real credentials.
- Query and selection equality remains sufficient for local snapshots: main-thread
  callbacks are serialized and the existing poll reducer owns network freshness.
  This plan adds no async query resolver or new event taxonomy.

#### Disconfirming evidence and bug-trace check

| Motivating failure / contract | Falsifier and locking test | Required result |
|---|---|---|
| Shift punctuation/uppercase rejected | native-edit-operations sends normal key events through the field | All printable input stays native; no modifier allowlist |
| Option–Backspace needed custom code | Native editor deletes from middle/selection, then undo | No end-only manual deletion survives |
| No input cue on invoke | session-acquires-native-editor checks actual first responder and native placeholder | Prompt/editor on successful keyboard summon |
| Rebuild destroys selection/composition | poll-deferred-during-session and appearance-deferred-during-session capture editor identity and ranges, then fire a poll and a theme flip mid-session | Same field/editor, caret, marked range and undo; island header identity unchanged |
| Session narrows against rows the user has not seen | Core test mutates the model rows after summon and re-narrows | Count, walk and destination come from `JumpSnapshot`; nothing changes until exit |
| Deferred updates are lost, applied twice, or applied before the transition settles | exit-applies-deferred-updates ends the session by each choke point after owed changes and records the render sequence | Newest rows and appearance render exactly once, after the transition's final state; no expanded paint before a collapse, no nested render |
| A preference click changes the preference but not the display | preference-control-ends-session clicks each island control mid-session | Session ends, preference applies, island renders the new preference immediately |
| A shorter display leaves a too-tall island | screen-change-keeps-panel-on-screen-and-fitting moves the fixture to a shorter screen mid-session | Island and scroll panes re-clamped; header/editor identity, selection and undo intact |
| IME confirmation opens a PR | composition-command-priority counts result actions during composition | Zero app actions until composition is resolved |
| AX reports result instead of editor | editor-focus-versus-result-selection uses external AX on live panel | Actual editing focus plus separate selected-result state |
| Mouse summon captures letters | mouse-summon-never-edits with disposable foreground markers | Marker reaches foreground only |
| Query text leaks through callbacks/undo | query-log-remains-content-free and editor-session-teardown | No diagnostic content; later sessions/ledger cannot recover query |
| Count and keyboard walk disagree | Existing narrowing suites plus native row-map comparison | Matching count truthful; selected IDs are drawn |

Every row maps to R1–R8 and a named unit above; no motivating failure is waived.
An editor/range reset, a duplicate browser open, an unexpected app activation,
or any marker routed to an unrelated app kills the corresponding proof. Fix
the mechanism; do not downgrade the test or substitute a screenshot.
Performance check: native editor never resets during a 100-edit fixture sequence;
measure edit-to-result render duration and report it. A visible backlog or lost edit
fails qualification; do not claim a cross-machine latency guarantee.

#### Build Execution Contract

- **Closed decisions (approved 2026-09-05):** native NSTextField; summon-time
  `JumpSnapshot` for every in-session computation; poll and appearance updates
  deferred to session exit; session-ending choke points stay immediate; the
  rendering path outside a session is unchanged (no persistent root); native
  Edit/undo ownership; composition gets command priority; keyboard table; one
  narrowing result; no global hotkey/network/persistence changes.
- **Builder autonomy:** exact private method signatures, layout constraint factoring,
  the shape of result-update arguments, and test fixture names. Keep names from the
  ledger. Record a reversible implementation choice and continue.
- **Verify at contact:** native newline/Escape selectors and keypad flags → native
  event tests → adjust only the selector translation, not the editing model.
  HUDPanel's field-editor lookup → execute lookup for the query and synthetic
  ledger clients, assert editor/history isolation → use NSWindow's documented
  delegate provision if overriding lookup is not called on the actual edit path.
  Keep the same JumpFieldEditor ownership and native editing; do not add manual undo.
  The deferral → fire `.radar`, `.theme` and `didChangeScreenParameters` mid-session
  in the native runner → if any path still reaches `buildSurface()` or a full
  `render()` while the session is live, route that case through the owed flags; never
  reparent the active editor to survive it.
  Marked text publication → real composition tests → observe native commit/end-edit
  notifications as needed without editing its buffer.
- **Expected gates:** every landed unit passes `scripts/test.sh` and
  `scripts/build-app.sh`; U6 also runs the native runner. No failing test is
  accepted because a later unit owns its file. UI unavailability is unverified
  evidence and blocks only proof-dependent actions, never ordinary local work.
- **Authority:** use this checkout on main, preserve pre-existing untracked files,
  stage explicit unit paths, and push each green unit as already authorized.
  No branch/PR/release. Only U5's new proof artifact/manifest may be written under
  loop. The existing agenda is the plan home. A different public artifact location
  or unrelated source cleanup is not implied by this plan.
- **Contained effects:** deterministic tests use in-process windows and a captured
  open-destination callback; no real clipboard or browser effects. Live proof may
  operate only a verified disposable marker document and fixture app under the
  owner's supervised exercise. Before sending global keys, identify both targets
  and exclude send/submit surfaces. If supervision, target identity or permissions
  are missing, hold that live effect and continue native/local work.
- **Human inventory:** native-editor design approval is the judgment requested by
  this document. Subsequent human assistance is needed only for unavailable OS
  permissions/global-input tooling or the supervised focus recording; local editor
  correctness uses synthetic fixtures without secrets. No real PAT is needed for
  this change. Daily-use taste can be reported against the built artifact; it does
  not block deterministic implementation. The former per-keystroke-rebuild and
  Space-rule decisions are replaced here, not left as another unanswered pause.
- **Stop:** only when required external assistance is still unavailable after all
  safe local work is exhausted, or an observed integration cannot preserve the
  native editing contract within scope. Report the failed witness and the exact
  assistance required. Never mark missing evidence passed.

#### Risks and confidence

| Risk | Mechanism / proof |
|---|---|
| A refresh path not listed here still reaches the island mid-session and kills the editor | Verify-at-contact fires every `handle(_:)` case and the screen notification mid-session in the native runner |
| Owed updates replay twice, not at all, or before the transition settles | One owner per exit: teardown never renders; the enclosing transition replays after its final state; exit-applies-deferred-updates covers every choke point; flags cleared before the replay |
| A deferred preference group swallows a deliberate click | Island preference callbacks end the session first; preference-control-ends-session |
| A long-open session shows stale rows | Accepted and documented (README, U5); the destination is a URL and stays valid |
| Query history reaches ledger/next query | Query-only JumpFieldEditor, exact client identity checks and teardown tests |
| Composition consumes navigation/open keys differently | Native delegate guard plus actual candidate-window witness |
| Result refresh steals text focus through old AX events | Remove row-focus override; announce explicit selection separately |
| UI tool remains unavailable | Continue native tests and docs; hold only live proof/final evidence commit |

The source inspection and isolated probe justify this architecture, not a claim
that the integrated feature already works. Global input, actual IME candidates,
VoiceOver speech and foreground-app hand-back remain distinct evidence obligations.

### A path and living prototype suite

<a id="quick-navigator-build"></a>

**Objective:** when a query matches a captured row, the user can see it, select it, and open it without first changing browse preferences; keep that interaction available as a reusable, traceable design prototype.
**Origin:** conversation — the owner showed “keeper”, “1 of 24”, a “gone quiet (show)” caption, and only the GitHub fallback, then asked to redesign the topology.
**Status:** A is selected by the owner (“A is good.”, 2026-09-08). The combined implementation plan is proposed; this architecture turn does not start a build.
**Origin extension:** the owner requested a living, interactive prototype suite and metadata for tracking its evolution, then asked to architect both together.
**Depth:** Deep for the prototype authoring boundary, metadata lifecycle, shared fixtures and browser/native verification. App changes remain reversible presentation/selection changes; production persistence and native input ownership do not change.
**Inspected base:** `55f789b` on `main`.

**Precedence after build approval:** this is the build entry point for U12 → U9 → U10 → U11. U12 is newly assigned, not a renumbering. It replaces the older rule that query matches still pass through browse gates/folds, and replaces stable-ID selection retention on actual query text edits. U1–U6 are landed; former U7/U8 remain retired. Native editing, snapshot freezing, keyboard commands, and admission rules remain as previously approved. The current TOPOLOGY document is not rewritten until its behavior and assertions change together.

#### Architecture decision

The island has two presentation contracts, selected by the existing query value:

- **Browse:** empty or whitespace-only query. Apply current draft visibility, quiet and held-back captions, owner grouping/folds, and receipt presentation.
- **Search:** nonempty query. Draw all matching captured rows directly, in the existing lanes. No browse caption, owner fold, merged ledger, draft gate, group header, or visibility control may hide a search result.

Search is not browse with every preference temporarily switched on. It bypasses that composition. Stored preferences never change. Clearing the query returns to browse over the same summon-time snapshot; ending the session applies deferred live updates.

**Trade-off:** search temporarily includes drafts and held-back items that the user normally hides. Search also gives up owner grouping and manual owner ordering. These are browsing preferences, not restrictions on what an explicit lookup can find. Row facts, badges, complete repository names, and ages remain truthful; “quiet” does not become “active”.

**Rejected alternative:** force `showDrafts`, `showStale`, and `showHeldBackInbound` true and unfold owners during search. That still runs browse topology, retains controls whose actions conflict with search, and risks separately overriding flags in rendering and keyboard traversal. Existing row-view factories already allow direct results with less policy duplication.

**Closed A choice:** include browse-hidden drafts/quiet/held-back/folded-owner rows in search; use flat results within each lane; select the first local result after every actual text edit. Do not offer B again. No new app surface, shortcut, fetch, or persisted setting.

**Suite decision:** keep one evolving standalone HTML per prototype, with a canonical JSON companion and synthetic fixture file. A small local script embeds those inputs for offline use, checks drift and runs browser scenarios. Git is the version history; meaningful decisions live in the companion JSON and are rendered into the prototype. No framework, hosting service, generic plugin system, or separate revision-number scheme.

**Approval of this combined plan means:** add the named prototype, test-tooling and documentation paths; keep browser/design evidence distinct from native proof. The suite design is new scope; A itself is already settled.

#### Requirements

- **R9 — reachable matches:** each matching source row is drawn once and keyboard-reachable in search, including browse-hidden rows.
- **R10 — count agreement:** positive `N of M` means N local result rows from M captured searchable rows. N excludes the GitHub destination. Zero uses the no-match message and no count.
- **R11 — useful default:** every actual text edit selects the first local result, or GitHub when no local result exists. Explicit arrow selection survives until the next text edit.
- **R12 — reversible presentation:** clearing restores browse preferences, grouping and folds without writing them; dismissal restores live data through existing teardown.
- **R13 — unchanged boundaries:** no suppressed notifications, cleared receipts, new GitHub data, ranking algorithm, or cross-lane deduplication enters search.
- **R14 — native continuity:** retain header/editor identity, caret, selection, composition, undo, and truthful AX focus across browse/search transitions.
- **R15 — tested laws:** live documentation changes with the behavior and its assertions; regression evidence includes the reported quiet-only case.
- **R16 — reusable prototype:** promote A to a stable repo path, openable offline with interactive scenarios; no personal cached data or discarded B/Current implementations in the living file.
- **R17 — evolution record:** one current metadata record plus meaningful decision history, rendered from the same source; Git supplies exact historical revisions.
- **R18 — honest implementation link:** distinguish selected design from verified implementation; unknown/stale metadata cannot quietly claim “implemented”.
- **R19 — repeatable suite:** stable scenario IDs, deterministic synthetic fixtures and independent expected outcomes connect browser checks to corresponding native tests.
- **R20 — maintenance:** a small index and documented commands make future updates discoverable and keep generated payloads in sync.

#### Verified background

`JumpSnapshot` captures the complete radar/inbound/pulse arrays before browse preferences. `JumpQuery.narrow` counts matches in those arrays. The controller then passes browse preferences to both the view and `KeySession.actionableIDs`. The walk correctly excludes hidden rows, but its set is smaller than the count's set.

Relevant boundaries at the inspected base:

- `Sources/GithudCore/JumpQuery.swift:73`: preserves input order while narrowing; `JumpSnapshot.narrow` forwards the captured arrays.
- `Sources/GithudApp/HUDPanelController.swift:669`: snapshot acquisition; `:720`: text-edit update; `:1256`: general render path.
- `Sources/GithudApp/IslandContentView.swift:430`: shared body builder; held-back composition at `:464`, draft/owner/quiet composition at `:484`.
- `Sources/GithudCore/KeySession.swift:31`: browse walk; `:127`: rebuild preserves an existing selected ID, including `jump:github`.

There is a second failure: an intermediate prefix with no matches selects GitHub, then a later prefix with local matches keeps GitHub selected. Revealing quiet rows alone does not fix Return's default.

The selected temporary sketch is an interaction reference only: it embeds 25 personal cached rows, hard-codes one owner, uses Date.now(), and approximates Swift matching in JavaScript. It passed 33 browser scenario combinations, but that neither makes its data safe to commit nor proves native parity. Replace all account-derived data and labels before promotion. Historical dated mocks remain design records; do not bulk-migrate or overwrite them.

Existing tools: scripts/test.sh runs the zero-dependency Swift Core executable; the native runner compiles production app views with its test main. Node v24.14.0 and agent-browser 0.31.1 were found on this machine; neither is a production app dependency. No repo package.json or prototype runner exists. No external research is needed: existing HTML sketches, fixture runners and native proof records provide the local patterns.

#### Naming and ownership

| Meaning | Existing name | Decision / owner | Status | Consumers / reason |
|---|---|---|---|---|
| Captured searchable rows and saved browse context | `JumpSnapshot` | Keep in Core; controller owns session lifetime | reuse | Narrowing and browse restoration |
| Query interpretation and emptiness | `JumpQuery` | Keep; `isEmpty` is the only browse/search discriminator | reuse | Controller and body builder; no second mode flag |
| Matching row arrays and totals | `JumpQuery.Narrowed` | Keep; this result supplies both search rows and their walk | reuse | IslandContentView and controller/KeySession |
| Selected result | `KeySelection` | Keep; distinguish text-edit reset from ordinary rebuild | reuse | Result actions, highlight, accessible selection |

No new production module, stored app enum, or presentation framework. Any small derived ID helper belongs with existing Core result/walk code, not in a new utility. Existing `admitted` denotes the source-array total before browse gates. Counts measure row occurrences, not distinct GitHub URLs; preserve existing IDs and reject duplicate IDs in authored fixtures rather than introducing an unrequested production identity migration.

| Suite concept | Chosen name / owner | Status | Consumers and boundary reason | Sibling disposition |
|---|---|---|---|---|
| Metadata, scenario catalog and decision history | `quick-navigator.json` in docs/design/prototypes | new | Generator/checker and embedded browser display; one authoring source | Dated mock files remain historical, not renamed |
| Interactive visual design | `quick-navigator.html` in docs/design/prototypes | new, promoted from selected sketch | Human review and browser checks; current dated mock is not overwritten | One living file, Git keeps prior revisions |
| Deterministic row facts and fixed clock | `quick-navigator-prototype.json` in Tests/Fixtures | new | Browser payload and native fixture adapter | Existing endpoint fixtures retain their wire-format meaning |
| Typed test-only fixture/scenario adapter | `PrototypeFixture` in Tests/GithudAppSnapshots | new | Existing native runner; cannot put prototype metadata into production Core | Separate from FixtureLoader's three GitHub formats |
| Local embedding and verification commands | `scripts/prototypes.mjs` | new | Designers and prototype checks; file:// cannot reliably fetch JSON companions | No generic tools/helpers module |

The losing alternatives are explicit: do not promote the cached HTML unchanged; do not mutate the dated historical mock; do not add a framework to read two JSON files; do not teach production FixtureLoader a non-GitHub format. Native JSON decoding and Node standard libraries are sufficient for the tooling. Necessary Swift/JavaScript fixture mirrors are checked against declared expected cases, not asserted equivalent by prose.

#### Proposed law changes

These are proposed wording and scope, not claims about current behavior.

- **L1 — conservation:** within a declared surface scope, each row is represented exactly once. Browse may account for hidden rows through its existing captions and ledger lines. Search must represent every match as a result row; a count cannot substitute for a match.
- **L2 — agreement:** surfaces agree when they claim the same set, measurement, and snapshot. The search count, result rows, and local keyboard walk describe the same matching set. The browse pill/gauge do not claim to be search-result counts.
- **L3 — traversal:** search traversal is the displayed local result order followed by the GitHub destination. No hidden match or disclosure control belongs in that walk. Browse traversal remains unchanged.
- **L4 — no zero:** retain. No-match text replaces a zero result count.
- **L5 — fail closed:** retain. An empty search is not an all-clear claim.
- **E1 — drafts:** scope its input gating explicitly to browse/lens presentation. Hidden drafts remain available to explicit search because they already exist in the captured source arrays.
- **Operators:** scope collapse, fold, tail, sink and merge to browse composition. A query filters the captured source set; it does not feed matches back through those hiding operators.
- **G3 — departure receipts:** remains a browse-only known gap. Receipts are not current search rows and never enter the search count.

This replaces the single “fold, not filter” gloss with two precise promises: browse accounts for hidden work; search exposes its matches. No new exemption for quiet rows is added.

#### Data flow and ordering

Directional guidance, not implementation code:

```text
Source admission → captured JumpSnapshot                     unchanged
                         ├─ empty query → browse composition  unchanged
                         └─ query → JumpQuery.Narrowed        existing matching
                                      ├─ direct result rows  changed
                                      ├─ local result walk   changed
                                      └─ N of M              same source set
```

Search lane order is Needs you → Inbound → Your PRs, omitting empty lanes, then GitHub. Within each lane, preserve the matching array's snapshot order. Do not apply owner ordering, regroup by quiet/draft/held-back, or add relevance sorting. Full repo labels remain on search rows because owner group headers are absent. The current pulse array is active → quiet → drafts (PulsePresenter.rows), unlike browse's active → drafts → quiet composition; search deliberately preserves the array order.

Reuse `radarRowView`, `inboundRowView`, `pulseRowView`, scroll panes, the existing destination row, and row-only `updateJump`. Browse keeps the existing presenter/owner-lens path. Both initial construction and row-only updates use the same body-builder decision.

#### Living prototype authoring contract

Proposed files (only one prototype is built now; the directory convention supports later ones):

```text
docs/design/prototypes/
  README.md                  index, commands, maintenance contract
  quick-navigator.html       authored layout/styles/interactions; one generated data block
  quick-navigator.json       authoritative metadata, scenarios, decision history
Tests/Fixtures/
  quick-navigator-prototype.json   synthetic row sets and a fixed reference time
Tests/GithudAppSnapshots/
  PrototypeFixture.swift     test-only typed decoding and scenario access
scripts/
  prototypes.mjs             sync / check / verify; Node standard library only
```

The suite README links prototypes but does not duplicate their status or decision summaries. HTML may be copied as a single offline file because its data is embedded. Authors edit layout/CSS/interaction code in HTML, and metadata/scenarios in JSON. Only the inert `prototype-data` script block is generated; a separate template tree is unnecessary.

**Metadata fields, schema version 1:**

| Field | Meaning / rule |
|---|---|
| schema_version | Exactly the supported schema version; unknown versions fail validation |
| id, title | Stable prototype ID and readable title; ID matches its basename |
| status | exploring, selected, implemented, or superseded; describes this design revision, not overall app quality |
| selected_variant | A initially; required for selected/implemented; never changed by a browser toggle |
| plan | Relative link to this agenda's quick-navigator-build anchor |
| fixture | Repo-contained relative path to the synthetic fixture JSON |
| default_scenario, scenarios | One canonical catalog; selector, deep links and test enumeration derive from it |
| history | Entries with date, actor, change, why, and a plan/commit/quoted-conversation reference |
| implementation | null until verified; otherwise an existing app commit, design fingerprint and repo-relative native evidence path |
| superseded_by | Required prototype ID/link only when superseded |

Do not add updated_at, manual version numbers, duplicate decision-date fields, or copies named final-v2. The last meaningful history entry provides the date; Git supplies exact changes and actors. Initial history records the actual owner choice “A is good.” Separately label architectural rationale as the architect's explanation, not an invented owner quote.

**History is not a second status machine.** It is an ordered list of human-readable design decisions, not executable events. Current status is authoritative in metadata; badges and the history table are derived in HTML. Only meaningful changes need history entries—new interaction contract, accepted variant, changed scope, implementation verification, or supersession—not every spacing adjustment.

**Status transitions:**

| Event | Metadata / visible observation | Persistent effects and repeats | Required check |
|---|---|---|---|
| Promote selected A | selected, variant A, implementation null | New safe files; selection quote recorded once | selected-is-not-implemented |
| Edit layout, fixtures or scenarios | Remain selected within A, or exploring if reopening a design choice; clear current implementation linkage | Git preserves the prior record; history entry for meaningful changes | changed-design-invalidates-verification |
| Verify implementation | implemented plus existing app commit, matching design fingerprint, evidence path | Later metadata/proof commit refers to earlier code commit; never its own future SHA | implemented-requires-evidence |
| Add a history explanation only | Design and implementation reference remain valid | No fixture/layout mutation or automatic status change | history-does-not-change-design-fingerprint |
| Replace with another prototype | superseded plus valid successor; earlier file remains openable | No auto-deletion or redirect hiding the old design | superseded-has-successor |
| Bad JSON, unknown status, duplicate IDs or missing files | Explicit validation error, never a green empty suite or a fallback to quiet | sync refuses to write; check exits nonzero | invalid-input-refused |

An `implemented` record is a claim about the named app commit and covered scenarios, not a claim that every later app revision still matches it. When changing related app behavior, update the prototype/metadata and native cases in the same change set. Browser checks cannot upgrade status.

**Non-circular fingerprint:** hash the authored HTML with its generated block replaced by a fixed marker, canonical fixture bytes, and canonical metadata excluding status, history, implementation and superseded_by. Canonical JSON sorts object keys and preserves array order. Store the resulting design fingerprint inside implementation metadata only after proof. Generated payloads carry source JSON/fixture hashes. Never embed an HTML file's own full hash inside itself, and never demand the commit currently being created. `check` rejects implemented metadata whose design fingerprint no longer matches.

**Local commands:**

- `node scripts/prototypes.mjs sync quick-navigator`: validate all inputs, update only the embedded data block, preserve authored HTML outside it. Missing/duplicate block, path escaping the repo, invalid JSON/schema or a changed source during write refuses the update.
- `node scripts/prototypes.mjs check`: read-only validation of registered JSON companions, fixture references, embedded parity, IDs, status/reference rules and offline containment. Empty/missing expected catalog is not a passing suite.
- `node scripts/prototypes.mjs verify quick-navigator`: check first, then use an isolated agent-browser session to exercise A's scenarios and capture representative wide/short views. Exit nonzero on scenario/assertion/driver failure; save reports under build or a fresh temp directory, never call a missing browser check passed. Close only the owned session.

Node/browser checks remain separate from scripts/test.sh and the production app build. No new npm package, browser install, hosted gallery, CI workflow, daemon or general scenario language is part of this plan. The suite README makes prototype check/verify mandatory for changes to its files; browser installation, if missing, is an explicit prerequisite rather than an automatic download.

#### Shared scenarios and evidence authority

The fixture file contains synthetic, explicitly named row sets and a fixed reference time. The HTML uses that time for ages; Core classification tests receive it where supported. Production row views currently format ages with Date(), so native captures record their time and do not promise pixel-identical ages. Do not refactor production clocks merely to support the prototype. Use the existing Codable Core row shapes for radar/inbound/pulse; retain their real flags rather than duplicating a competing kind string. The test adapter narrows JSON into those exact Core types. It does not feed this display-row format into FixtureLoader's notification/GraphQL/search decoders.

A scenario record names an ID, label, fixture row set, initial query/session state, browse preferences, freshness state, and independently authored expected local row IDs/count, walk and selected result. Required fields cannot silently default to “keeper”. Expected outcomes are not calculated by the JavaScript code being tested. Shared matching/destination cases are checked with production JumpQuery; full visibility/selection expectations become native-controller assertions in their owning U9/U10 units.

Keep these existing scenario IDs: quiet, draft, held, fold, mixed, none, empty, loading, offline, browse, mouse. Add stable number, branch, repo-number, GitHub-link, prefix-return and clear-restore cases as needed; never rename an ID just because its label changes. Use at least 25 synthetic rows across the populated fixture so overflow is real. A synthetic keeper title is sufficient; no actual repository/title/author/URL from the temporary artifact is needed.

The selector and checker enumerate the same catalog. Safe deep links carry only declared scenario ID and normal/short viewport; arbitrary typed query contents are not persisted into the URL or storage. Invalid deep-link IDs show an explicit choice/error, not a silently substituted scenario. Free typing stays interactive over synthetic data; only declared cases claim parity, and the page says so.

| Meaning | Authority | Other representation / guard |
|---|---|---|
| Selected design and its history | Companion JSON | HTML renders embedded copy; sync/check detects divergence |
| Fixture row facts and clock | Synthetic fixture JSON | Browser copy and native typed adapter; source hash and decode checks |
| Expected scenario outcomes | Declared scenario records plus approved plan | Browser and native assertions both compare independently; neither grades its own computed output |
| Production matching/destination | Swift JumpQuery / PlainWords | JavaScript is a bounded prototype mirror; declared case parity is required |
| Native editing, geometry, focus, open effects | AppKit implementation and native/live tests | Browser simulation explicitly cannot certify these |
| Historical revisions | Git | History entries explain why; no redundant version counter |

The HTML uses no external requests or native/global input. Result Return/click creates a “would open” receipt, never a real URL open or clipboard write. Embed data as inert JSON, escape it safely, render row/query strings as text, and disallow external connections/forms. Actual browser-native editing is still not evidence of AppKit IME, focus acquisition or field-editor lifetime.

#### Program obligations

- **O11:** one narrowed result supplies search arrays, local IDs and totals; local ID concatenation uses the same lane and array order as rendering.
- **O12:** search never consults browse visibility/grouping preferences to remove or reorder matches, and never writes those preferences.
- **O13:** the search discriminator is the existing whitespace-aware query emptiness; raw editor text still owns first-Escape clearing.
- **O14:** an actual text change resets result selection; a caret/selection move, result arrow, peek, resize, or unchanged-text callback does not.
- **O15:** no query update replaces the native header/editor or uses a saved text copy to overwrite native selection/composition.
- **O16:** assertions compare actual rendered actionable rows with the full walk in order; subset checks against raw arrays are insufficient.
- **O17:** companion JSON is the sole metadata/scenario/history authority; rendered copies and selectors derive from it.
- **O18:** schema version, lifecycle states, IDs and referenced paths are validated; unknown or malformed inputs fail explicitly before generation/verification.
- **O19:** fixture rows are synthetic and time-frozen; no live account import path survives promotion. Browser/native cases use the same declared inputs and independent expectations.
- **O20:** generated payload parity and implementation freshness are checked without self-referential hashes or future commit IDs.
- **O21:** browser reports distinguish scenario verification from native proof; no browser success automatically changes design approval or implementation status.
- **O22:** the prototype is standalone offline, has no real navigation/clipboard/global-key effects, and leaves no unrelated process/session cleanup.

#### State and action contract

All query/presentation changes below are synchronous on the existing UI thread. Poll data still waits in the live model until session exit.

| Action / state | User-visible result | Stored state / effects | Ordering and repeat behavior | Locking test |
|---|---|---|---|---|
| Summon with empty query | Existing browse layout and native editor | Capture snapshot; no preference writes | Existing acquisition/refusal rules | browse-at-summon |
| Type text matching a hidden row | Direct local row, positive count, then GitHub | No preference writes or network request | First local result selected after each actual edit | hidden-match-reachable |
| Prefix has zero matches, later has matches | GitHub-only becomes local results plus GitHub | Selection resets, not retained on GitHub | One reset per changed text value | fallback-to-local |
| Arrow to GitHub without editing | GitHub selected and Return may open it | No query or preference change | Resize/peek preserve selected ID | explicit-fallback-stays |
| First Escape on text, including whitespace | Empty query and original browse layout | Native edit clears raw text; preferences unchanged | No session exit; native undo remains session-scoped | clear-restores-browse |
| Undo clear or edit | Presentation follows restored native text | No model preference mutation | Same field/editor; text-change selection rule applies | undo-restores-results |
| Poll/theme during search | Captured results remain | Existing owed-update flags only | Coalesced, no new timer/render owner | search-snapshot-stays |
| Second Escape / Return / key loss | Existing release/collapse/open behavior | Teardown then existing final transition applies live state | Late callbacks cannot restart search | search-exit-unchanged |

Empty source arrays, whitespace-only input, and zero matches are distinct covered cases. Real IME candidate behavior is not redesigned: keep the approved native composition priority and existing tests.

#### U12. Establish the living selected-A prototype suite

- **Goal:** make selected A durable, interactive, safe to commit, and traceable before app implementation.
- **Requirements:** R16–R20; preserves R9–R14 as the selected design contract.
- **Dependencies:** none; A selection is already supplied by the owner.
- **Files:** create the six suite files listed above, plus modify `Tests/GithudAppSnapshots/run.sh` and its `main.swift` to compile/read the test-only adapter; link the suite from README and this agenda. No production app files.
- **Approach:** promote A's authored HTML with wholly synthetic data; remove Current/B code and personal labels. Establish canonical JSON, typed fixtures, sync/check/verify commands and history UI in the same usable slice. Keep dated mocks untouched.
- **Patterns:** existing standalone mocks, existing native runner, Node standard libraries and installed agent-browser. Do not import a web framework or make Core tests require a browser.
- **Tests:** *happy:* A opens offline with selected status and synthetic scenarios, Core matching agrees with declared query cases. *edge:* fixed-clock repeatability, empty/loading/no-match distinct, unknown hash/scenario IDs rejected, null implementation valid while selected. *error:* malformed/unsupported JSON, duplicate IDs, escaped paths, duplicate generated blocks, stale payload and false implemented records fail without rewriting HTML. *integration:* selector/checker catalog equality, scripts remain usable from a clean checkout with documented dev tools, sync is idempotent, expected outcomes survive a deliberately broken matcher test.
- **Verification:** no account-derived strings/data remain; all declared browser cases pass; metadata and fixture mirrors agree; native adapter decodes and checks existing Core matching. Future AppKit search visibility is not claimed before U9/U10.
- **Runtime evidence:** new tooling/adapter unexecuted; temporary sketch's 33 combinations only prove its earlier browser interactions.
- **Checkpoint:** auto — schema/negative tests, offline browser verification, Core and app-build scripts, and native decode checks. Missing browser prerequisite holds this unit's verification, not safe app research; never auto-install it.
- **Rollback:** remove only newly authored suite files via an explicit revert; no app persistence or account data is migrated.

#### U9. Draw all query matches directly

- **Goal:** make every counted match visible and reachable without changing browse preferences.
- **Requirements:** R9, R10, R12, R13, R14, R15.
- **Dependencies:** U12 and landed U6/U5.
- **Files:** modify `Sources/GithudCore/JumpQuery.swift`, `Sources/GithudCore/KeySession.swift`, `Sources/GithudApp/HUDPanelController.swift`, `Sources/GithudApp/IslandContentView.swift`, `docs/TOPOLOGY.md`, `README.md`; test both existing main.swift runners.
- **Approach:** direct search rows and walk derive from the narrowed arrays; preserve the browse branch untouched. Update L1/L2/L3, operator scope and E1 with their assertions in this commit. Search emits no collapse/fold controls or lens eye.
- **Patterns:** existing row-view factories and shared makeBody/updateJump; existing JumpSnapshot capture and teardown; U12's shared synthetic cases and test-only adapter.
- **Tests:** quiet-only, draft-only, held-back-only, folded-owner-only, merged-fold and mixed-lane matches appear once with ordered walk equality; zero matches shows only fallback/no-match; clear and whitespace restore saved browse shape; unavailable/nil-url behavior remains the existing row behavior, with no invented resolver.
- **Verification:** positive local count equals rendered local rows and local walk length; clearing restores preferences byte-for-byte; both scripts and native runner pass. U10's selection default is not claimed yet.
- **Runtime evidence:** proposed integration unexecuted; use production controller/native fixtures to compare real row views, IDs, count and editor identity.
- **Checkpoint:** auto — native hidden-match fixtures plus Core and app-build checks; no red commit.

#### U10. Reset selection only when query text changes

- **Goal:** Return opens the first local result after typing, including after a zero-match prefix.
- **Requirements:** R11, R14, R15.
- **Dependencies:** U9.
- **Files:** modify `Sources/GithudApp/HUDPanelController.swift`, `Sources/GithudCore/KeySession.swift` only if an existing primitive needs extension, `README.md`; test the two existing runners.
- **Approach:** on actual changed text, initialize selection from the current result walk. Retain ordinary stable-ID rebuild for layout-only updates; guard unchanged-text callbacks. Native editor selection is not result selection.
- **Patterns:** KeySelection initializer for first result; existing rebuild for non-text changes.
- **Tests:** no-match prefix → local match selects local; explicit Down to GitHub stays until text changes; a disappearing selected local row chooses first remaining local; same-text/caret/resize do not reset; clear and undo preserve editor/undo identity.
- **Verification:** result default and explicit arrow choice both hold through the real controller; Core, native runner and app build pass.
- **Runtime evidence:** proposed selection policy unexecuted; fixture sequence through native editor callbacks and captured opener settles it.
- **Checkpoint:** auto — prefix/selection regressions and build checks; no red commit.

#### U11. Record topology regression evidence

- **Goal:** demonstrate A on the actual island, then link the living prototype to that verified implementation.
- **Requirements:** R9–R20.
- **Dependencies:** U12, U9, U10.
- **Files:** extend `Tests/GithudAppSnapshots/main.swift` if required; update this amendments section, README and the prototype JSON/embedded payload; create only `loop/evidence/wp6k-search-results.md` and `loop/evidence/wp6k-search-results.manifest.json` for current proof. Do not rewrite earlier evidence.
- **Approach:** use U12's shared cases to capture search, selected local open, and clear-to-browse. Pin source/binary/artifacts and record browser/native differences. Only after native proof passes, set implementation metadata to an existing tested app commit, the design fingerprint and this new evidence path; add one implementation history entry and re-sync. If proof exposes app defects, land and verify their corrective code commit before the final metadata/proof commit; no self-referencing commit field.
- **Patterns:** `Tests/GithudAppSnapshots/run.sh`; `loop/evidence/wp6k-native-input.manifest.json` and its documented contained live driver.
- **Tests:** both themes; mixed lane walk; long query and short screen; editor selection/undo across browse/search; unchanged saved preferences; synthetic global summon/typing/Return/Escape/mouse boundaries.
- **Verification:** actual quiet match instead of a caption; selected local URL opens; clearing restores browse; all shared browser/native cases and both scripts pass; implemented metadata resolves to matching design evidence. State unavailable human-only observations rather than treating them as parity.
- **Runtime evidence:** unverified — implementation and new fixture captures are required; older recording does not prove this redesign.
- **Checkpoint:** auto under the existing scoped native-capture grant — verify permissions, fixture process and disposable foreground document first. Current recording plus automated checks → commit/push evidence and metadata. Missing permissions/identity holds only live exercise/final proof and implemented status; finish independent local work. Never send input into an unidentified app.

#### System-wide impact

No new production data source, persistence migration, dependency, timer, editor, hotkey or root-view refactor. Admission/classifier and browse presenters remain authoritative for their existing scopes. Source errors/freshness retain current presentation; zero search matches never imply no outstanding work. Direct result rows retain their existing pointer, peek, open and AX behavior.

The suite adds a repo authoring format, not app state. File → validator → embedded payload → browser is new; fixture JSON → typed test adapter → real Core/AppKit checks is the test bridge. Browser tooling remains opt-in and separate from app packaging. Bad authoring inputs produce tool errors, never app defaults; generation refuses unsafe targets and keeps authored bytes outside the data block. Historical mocks are not schema consumers and do not acquire compatibility obligations.

#### Risks, dependencies and disconfirming evidence

| Disconfirming case | Required assertion / response |
|---|---|
| Query counts a draft but draws nothing | Actual view local rows equal all matching arrays; fail U9 |
| Folded owner or held-back filter still hides a match | Mixed nondefault-preference fixture; fail U9 |
| Clearing leaves an owner unfolded or drafts enabled | Preference equality and native browse round-trip; fail U9 |
| Typing a branch leaves GitHub selected after local rows return | Prefix transition and captured opener; fail U10 |
| Result refresh resets caret/undo or focus | Native identity/range/history assertions; fail the owning unit |
| Direct array order differs between walk and drawing | Ordered equality over real actionable views, not a set/subset assertion |
| Broad matching yields many results | Existing capped scroll panes and screen fitting; no new result cap that hides counted rows |
| Cached private data survives promotion | Replace whole data source and account labels, inspect all promoted bytes; generator reads only committed synthetic fixture paths |
| HTML changes while metadata still says implemented | Design fingerprint mismatch fails check; clear linkage/reverify, never silently update proof |
| JS matcher and native behavior agree only with themselves | Both compare declared expectations; shared cases run real Swift matching and controller output |
| Same schema drifts across Node/Swift/browser | Typed decoding and catalog/fixture parity checks; unknown schema/IDs fail |
| Browser is unavailable or network is attempted | Nonzero verification result; selected design remains selected, not implemented |
| Screenshot ages change every week | Freeze HTML fixture ages and Core test time; native screenshots record capture time and do not claim age-pixel equality |
| A maintenance-only history edit invalidates itself | Exclude status/history/implementation from design fingerprint; no full-HTML self-hash |

#### Bug-trace and confidence cross-check

| User problem / requirement | Contract that addresses it | Expected result |
|---|---|---|
| 1 of 24 but only gone quiet caption | R9/R10; U9 direct-result branch | Local match is a real row and walk entry |
| Fallback survives a later local match | R11; U10 text-edit reset | First local result selected |
| Search changes my browse settings | R12; no preference writes | Clear restores original browse shape |
| Temporary artifact cannot be reused or found | R16/R20; stable HTML plus index | Offline prototype at one repo path |
| Design evolution loses rationale | R17; JSON history plus Git | Read what/why/who beside exact revisions |
| Prototype falsely claims current implementation | R18/R19; fingerprint and native evidence | Selected until independently verified |

Source inspections establish the current boundaries, not the viability of new tooling. New browser/Swift adapters and lifecycle guards remain unverified until their owning units run. No unrelated source finding is promoted into this build.

#### Build execution contract

- **Closed decisions:** A is selected; direct search rows, all captured current-row categories, unchanged browse, first-local selection after text edits, no receipts/suppressed data/new fetch, unchanged native input/snapshot lifecycle. The living page presents A, not reopened A/B choices.
- **Builder-owned:** helper placement within named owners, synthetic fixture values, test names, minimal layout constraints and focused validators. Record decisions the spec does not cover. No prototype framework, alternate metadata authority, action DSL, importer or automatic approval.
- **Verify at contact:** ensure both controller construction paths use the search contract; row factories register actionable IDs and preserve full repo context; snapshot arrays contain browse-hidden categories; unchanged-text callbacks can be distinguished. If a fact differs, use the existing typed boundary and add a regression before changing consumers. If required rows are not captured, do not fetch or widen admission silently—return the concrete scope conflict.
- **Authority after Build approval:** use this checkout on main; preserve pre-existing untracked files; no branch/PR or real secret values. In addition to earlier Sources/Tests/README/TOPOLOGY/agenda authority, this combined plan names docs/design/prototypes and scripts/prototypes.mjs plus the existing native runner as its new suite scope. Only U11's two named proof files may be added under loop. Commit serially and push after green units; laws and assertions change with behavior. No CI or global skill/config edits.
- **Expected gates:** U12 passes prototype sync/check/verify, Core/app-build and native fixture decoding/matching checks; it does not claim future AppKit search behavior. U9/U10 additionally check their actual native visibility/selection contracts and keep prototype checks green. U11 needs complete current browser/native/live evidence before implemented metadata. No red unit commits and no missing tool reported as a pass.
- **Human inventory:** A selection is resolved by the owner's quote; do not ask again. Approval to build this combined plan is pending. Existing native-capture consent applies only with verified permissions and fixture/disposable-document identities. Synthetic fixtures replace human/private content; real IME/VoiceOver sensory assessment remains separate. A browser-tool prerequisite may need installation by the owner; continue local checks but hold browser certification if unavailable. No new taste gate is invented for the already selected A.
- **Stop conditions:** observed schema/fixture mismatch without a safe typed adapter, inability to preserve native editor/snapshot boundaries, or missing authority/permissions for a required external effect. A missing temp sketch is not a blocker: the selected contract and new synthetic fixtures are sufficient. Record reversible implementation choices and continue.

#### Scope boundaries and deferred work

Out of scope: redesigning browse, walking disclosure controls, G3 receipt traversal, ranking/deduplication, live query polling, changed composition shortcuts, new preferences, generalized prototype platform, automatic app-to-HTML generation, whole-repo prototype migration, hosting, CI changes, or migrating historical mock files. No requested portion is deferred; unrelated historical limitations remain in their existing records.
## Plan

**Objective:** a PR you own, or any row the island already holds, reachable in three keystrokes
after ⌃⌥G, with a branch name or a number as the handle; and an honest way out when the
island does not hold it. **Depth:** Standard, 5 units. **Origin:** the decision record above.

### Naming ledger

| Role / meaning | Existing repo term | Chosen name | Owner / placement | Status | GR6 sibling disposition |
|---|---|---|---|---|---|
| the typed text, what kind of handle it is, which rows it selects, and where it points when nothing matches | none (the signal classifier "filters"; TOPOLOGY says "fold, not filter") | `JumpQuery` | `Sources/GithudCore/JumpQuery.swift` | new | no sibling; "narrow" is the verb used everywhere, never "filter" |
| the kind of handle the text parses as | none | `JumpQuery.Handle` (`number`, `repo`, `repoNumber`, `branch`, `link`, `text`) | same file | new | — |
| the header slot while a query is live: the text, a caret glyph, the `N of M` count | `makeHeader` title + count badge | `JumpLineView` | `Sources/GithudApp/IslandContentView.swift` | new | sibling of the header stack; replaces title+badge only while a query is live |
| the trailing row that opens the query's GitHub destination | `InboxLinkView` (footer link), `ClearedRowView` (opens a URL) | `JumpDestinationRowView` | `Sources/GithudApp/IslandContentView.swift` | new | in `keyRows` under the fixed id `jump:github`, last in the walk |
| a PR's head branch, as fetched | none (`headRefName` is GitHub's field name) | `headBranch` on `PullRequestPulse` and `PulseRow` | `Sources/GithudCore/PullRequestPulse.swift`, `PulsePresenter.swift` | new | — |
| the widened key-session intents | `KeySession.Intent` | `KeySession.Intent` gains `type(Character)`, `deleteBackward`, `clearQuery`; `intent(forKeyCode:characters:hasQuery:)` | `Sources/GithudCore/KeySession.swift` | rename (signature) | the old `intent(forKeyCode:)` is removed, not kept as an overload; its test suite is rewritten |

### Architecture Decision

**Approach.** One pure Core value, `JumpQuery`, is the only thing that knows what the typed
text means. The controller owns it beside `keySelection` (both live exactly as long as a
⌃⌥G session). On every render and on every session key, the controller narrows the three
row arrays through `JumpQuery.narrow(...)` **once** and hands the narrowed arrays to both
`IslandContentView.init` and `KeySession.actionableIDs`, so the view and the keyboard walk
cannot disagree (L2, L3). The panel's `keyDown` override stays the single router: `KeySession`
gains typing intents and the controller accumulates characters into the query, then re-renders
through the existing `render()` pass, whose carry stashes (scroll, peeks, selection-by-id)
already survive a rebuild. There is no text field on the glass (D1).

**Rationale.** Consistency first: the codebase already has one router (`HUDPanel.keyDown` →
`handleSessionKey` → `KeySession.intent`), one rebuild path with carry stashes, and one
agreement seam (both consumers call the same Core presenters). The design adds one Core value
and one narrowing call upstream of that seam rather than threading a predicate through the
lens layout or introducing a second responder. The rejected alternative, an `NSTextField` in
the header, would move ↑↓⏎esc into `doCommandBy` and split the ratified key map across two
homes (`LedgerCardView.swift:290-301` shows the cost).

**Trade-offs.** A full island rebuild per keystroke (same cost as a poll tick; ~25 rows).
No caret movement or selection inside the query. Branch matching reaches Your PRs only (D3).

**Approval criteria.** Approving means: (1) narrowing happens once in the controller and
feeds both consumers; (2) the key map widens inside the existing router with the context rule
in D4 for space; (3) L1 and L2 gain the narrowing boundary text in the same PR, with their
assertions; (4) the GitHub row opens a URL and makes no request.

### Program obligations

- **O1.** The narrowed row arrays passed to `IslandContentView.init` and to
  `KeySession.actionableIDs` are the same values, produced by one call per render or key.
  A test asserts the walk ids are a subset of the drawn row ids for a narrowed island.
- **O2.** `JumpQuery` never performs I/O and never imports AppKit; its destination is a
  `String` URL the App layer opens.
- **O3.** The `GITHUD_DEBUG` key log never contains query characters — it logs the query
  length and the handle kind only (the ratified invariant: keystroke contents structurally
  cannot appear in the log).
- **O4.** The header never renders `0 of M` (L4); the nothing-matches line replaces the count.
- **O5.** With an empty query the narrowed arrays are identical (`==`) to the inputs, so the
  empty-query render is byte-for-byte today's island (AC9).

### High-Level Technical Design

Directional, for review only.

```
⌃⌥G ── beginKeySummonSession ──► jumpQuery = JumpQuery("")   keySelection = walk(narrow(rows, ""))
key ─► HUDPanel.keyDown ─► handleSessionKey ─► KeySession.intent(code, chars, hasQuery)
        .type(c) / .deleteBackward / .clearQuery ─► jumpQuery mutates ─► render()
        .moveUp/.moveDown/.open/.peek/.dismiss ─► as today
render() ─► narrowed = jumpQuery.narrow(radar, inbound, pulse)
         ─► keySelection.rebuild(ids: actionableIDs(narrowed…) + [jump:github if query non-empty])
         ─► IslandContentView(rows: narrowed.radar, inbound: narrowed.inbound, pulse: narrowed.pulse,
                              jump: jumpQuery, …)   // header → JumpLineView; tail → JumpDestinationRowView
⏎ on jump:github ─► NSWorkspace.open(jumpQuery.destination) ─► endKeySummonSession; setExpanded(false)
esc ─► hasQuery ? clearQuery (render) : dismiss (as today)
```

Handle table (the parser's contract; the sketch's table, verified against the row strings):

| text | handle | narrow rule | destination |
|---|---|---|---|
| `214`, `#214` | number | `repo` string contains `#214` exactly at a token boundary, else substring over the line | `github.com/search?q=214+is:pr+author:@me` (`author:@me` only when `selfLogin` is known; else no author term) |
| `githud 214`, `pro-vi/githud#214` | repoNumber | repo suffix or full name match **and** number | `github.com/<owner>/<repo>/pull/214` when owner known from the island; else search with `repo:` term |
| `pro-vi/githud` | repo | `repo` string begins with it | `github.com/pro-vi/githud` |
| contains `/` and is not a known repo, or matches `^[a-z]+-\d+` | branch | `headBranch` contains it (case-insensitive); other lanes: substring over the line | `github.com/search?q=is:pr+head:<branch>` |
| `github.com/…` | link | exact `url` match | the link itself |
| anything else | text | substring over `title`, `repo`, `subtitle` (the displayed line without the age) | `github.com/search?q=<text>` |

### Implementation Units

#### U1. `JumpQuery` — parse a handle, narrow rows, name a destination

- **Goal:** the whole meaning of the typed text lives in one tested Core value.
- **Requirements:** AC 1, 2, 3, 6, 10; D2, D3
- **Dependencies:** None
- **Files:**
  - Create: `Sources/GithudCore/JumpQuery.swift`
  - Modify: `Sources/GithudCore/PlainWords.swift` (jump-line strings: count `N of M`, nothing-matches line, destination row titles/subtitles, placeholder)
  - Test: `Tests/GithudCoreTests/main.swift` (new suites beside the KeySession block)
- **Approach:** `struct JumpQuery: Equatable, Sendable { var text: String }` with `handle`
  (computed), `narrow(radar:inbound:pulse:) -> Narrowed` where `Narrowed` carries the three
  arrays plus `matched` and `admitted` counts, and `destination(selfLogin:knownRepos:) -> String`.
  Matching uses `RadarPresenter.displayLine`'s parts without the age. Empty text returns the
  inputs unchanged (O5). Whitespace-only text is empty.
- **Patterns to follow:** `PeekReveal.swift` (small pure value with a decision rule and a
  test suite); `PlainWords.swift` header comment (Core decides the words); `PulsePresenter.sections`
  as the shape of a pure regroup.
- **Test scenarios:**
  - *Happy path:* `"214"` over a fixture with `pro-vi/githud #214` → one pulse row, `matched 1`; `"feat/per-org-quiet-tails"` → the row whose `headBranch` is that, via `.branch`.
  - *Handle kinds:* each table row above parses to its kind; `"githud"` with a known repo `pro-vi/githud` parses to `.repo` (bare name); `"provi/eng"` parses to `.branch`, not `.repo`.
  - *Edge cases:* empty and whitespace-only → inputs returned `==`; upper/lower case matches; `"#"` alone is text; a number that matches nothing still narrows by substring (e.g. `"90"` matches `Coverage decreased on #90`).
  - *Destinations:* branch → `search?q=is:pr+head:…` with percent-encoding; link → itself; text → `search?q=` percent-encoded.
  - *Error path:* a query with characters needing encoding (`|`, spaces, `#`) yields a valid URL string.
- **Verification:** the suites pass under `scripts/test.sh`; `JumpQuery.swift` imports Foundation only.
- **Proven through:** the pure functions themselves; fixture rows built the sanctioned way (`main.swift:4392-4405`).
- **Checkpoint:** `auto — scripts/test.sh`

#### U2. Head branch on the pulse

- **Goal:** every row in Your PRs carries its head branch, fetched at no extra cost.
- **Requirements:** AC 2; D3
- **Dependencies:** None
- **Files:**
  - Modify: `Sources/GithudCore/PullRequestPulse.swift` (query string, `PRNode.headRefName`, `PullRequestPulse.headBranch`, `toPulse`), `Sources/GithudCore/PulsePresenter.swift` (`PulseRow.headBranch`, `row(for:)`)
  - Modify: `Tests/Fixtures/*.json` for the GraphQL pulse fixture (add `headRefName` to nodes), `Tests/GithudCoreTests/main.swift` (decode assertions)
- **Approach:** add the scalar `headRefName` to `openPRsQuery`'s node list; decode it as
  `String?` (optional-defensive, like `createdAt`), surface as `headBranch: String?`. Every
  `PullRequestPulse(...)` call site in tests gains the parameter with a default of `nil`.
- **Patterns to follow:** `PullRequestPulse.swift:197-213` (`createdAt` optional-defensive decoding); `PulsePresenter.swift:179-200`.
- **Test scenarios:**
  - *Happy path:* the GraphQL fixture with `headRefName` decodes into pulses whose `headBranch` is set; `PulsePresenter.row` carries it through.
  - *Edge case:* a node without `headRefName` decodes with `headBranch == nil` (no throw).
  - *Integration:* `changeSignature` is unchanged by a branch (a renamed branch does not force a redraw; document the choice in the test name).
- **Verification:** `scripts/test.sh` green; `grep headRefName Sources/` finds exactly the query and the DTO.
- **Runtime evidence:** `unverified — run the app with a PAT and GITHUD_DEBUG=1 and confirm the pulse still decodes (the field is documented on GitHub's PullRequest object; a typo in the query string degrades the whole pulse per the honesty rule at PullRequestPulse.swift:170-178)`.
- **Checkpoint:** `auto — scripts/test.sh, then scripts/build-app.sh`

#### U3. Typing reaches the header

- **Goal:** after ⌃⌥G, printable keys, ⌫, ⌘V, esc build and clear a query the header draws. Lanes do not narrow yet.
- **Requirements:** AC 4 (both halves), 7, 9; D1, D4, D6, D7; O3
- **Dependencies:** U1
- **Files:**
  - Modify: `Sources/GithudCore/KeySession.swift` (`Intent` cases; `intent(forKeyCode:characters:hasQuery:)`)
  - Modify: `Sources/GithudApp/HUDPanelController.swift` (`jumpQuery` beside `keySelection`; `handleSessionKey` accumulates; `beginKeySummonSession` seeds an empty query; `endKeySummonSession` clears it; `render()` passes it to the view; debug log per O3)
  - Modify: `Sources/GithudApp/HUDPanel.swift` (`performKeyEquivalent`: during a list session, ⌘V reads `NSPasteboard.general.string(forType: .string)` and calls the controller's paste hook instead of the `NSText.paste` probe)
  - Modify: `Sources/GithudApp/IslandContentView.swift` (`JumpLineView`; `makeHeader` swaps title+badge for it while the query is non-empty; `init` takes `jump: JumpQuery?`)
  - Test: `Tests/GithudCoreTests/main.swift` (the key-map suite at `main.swift:4456` rewritten for the new signature)
- **Approach:** the intent rule, in Core: printable single-character `characters` with no
  modifiers → `.type(c)`; 51 → `hasQuery ? .deleteBackward : .passthrough`; 49 →
  `hasQuery ? .type(" ") : .peek`; 124 → `hasQuery ? .peek : .passthrough`; 53 →
  `hasQuery ? .clearQuery : .dismiss`; 126/125/36 unchanged; 76, 48, ⌘/⌥ chords →
  `.passthrough`. The controller mutates `jumpQuery` and calls `render()`; the query is
  controller state, so it survives the rebuild for free (AC 8's text half). The header view is
  the existing header stack with the title label and count badge replaced by `JumpLineView`
  (13pt medium `inkPrimary` text, a 1pt-wide caret glyph in `inkSecondary`, the `N of M`
  count on the trailing side in 11pt `inkTertiary` monospaced-digit) — same insets, same
  gear and chevron, so the island's height does not change.
- **Patterns to follow:** `HUDPanelController.swift:658-690` (the switch); `HUDPanel.swift:84-99` (the ⌘ probe — add the session branch before it); `IslandContentView.swift:698-742` (header stack); `LedgerCardView.swift:187-241` for the ink tiers of text on glass, not the well.
- **Test scenarios:**
  - *Key map:* `a` with `hasQuery: false` → `.type("a")`; 49 → `.peek` / `.type(" ")` by `hasQuery`; 124 → `.passthrough` / `.peek`; 53 → `.dismiss` / `.clearQuery`; 51 → `.passthrough` / `.deleteBackward`; 76 and 48 → `.passthrough` both ways; a ⌘-modified `v` never reaches `intent` (the controller's modifier guard; test the guard's rule if it is lifted into Core).
  - *Edge cases:* a multi-character `characters` (dead keys, IME) → `.passthrough`; control characters → `.passthrough`.
  - *Integration (manual, recorded in the pause of U4):* ⌃⌥G, type, see the text; esc clears; esc again hides; mouse-summoned island ignores letters.
- **Verification:** with a query typed, the header shows it and the lanes are unchanged; `scripts/build-app.sh` succeeds; the key-map suite is green under its new signature.
- **Proven through:** Core suite for the map; `scripts/build-app.sh` for the shell; the human exercise in U4.
- **Checkpoint:** `auto — scripts/test.sh && scripts/build-app.sh`

#### U4. Narrowing, the count, and the GitHub row

- **Goal:** the query narrows all three lanes for both the view and the keyboard walk, the header counts, and a trailing GitHub row is the way out.
- **Requirements:** AC 1, 3, 5, 6, 8; D2; O1, O4, O5
- **Dependencies:** U1, U2, U3
- **Files:**
  - Modify: `Sources/GithudApp/HUDPanelController.swift` (`render()` and `beginKeySummonSession` narrow once and feed both consumers; `.open` on `jump:github` opens the destination through the same end-and-collapse path)
  - Modify: `Sources/GithudCore/KeySession.swift` (`actionableIDs` gains `includeDestination: Bool` appending `jump:github` last)
  - Modify: `Sources/GithudApp/IslandContentView.swift` (`JumpDestinationRowView` registered in `keyRows`; zero-match lanes omitted; nothing-matches line; `N of M` fed from `Narrowed`)
  - Modify: `Sources/GithudCore/PlainWords.swift` (already added in U1; wire)
  - Test: `Tests/GithudCoreTests/main.swift` (walk ⊆ drawn for narrowed islands; `jump:github` last only when the query is non-empty; selection survives a rebuild that narrows away the selected row by clamping)
- **Approach:** narrowing is one call in the controller, its result used for both
  `KeySelection.rebuild(ids:)` and `IslandContentView(...)`. `JumpDestinationRowView` mirrors
  `ClearedRowView` (an `IslandClickableView & KeySessionActionable` whose open is
  `NSWorkspace.shared.open`); its glyph is `magnifyingglass` (or `xmark.circle` when the
  last poll failed, per `Freshness`), title and subtitle from `PlainWords`. The lane
  assembly omits a lane whose narrowed array is empty; when all three are empty the
  nothing-matches line renders above the GitHub row and the header shows no count (O4).
- **Patterns to follow:** `HUDPanelController.swift:1055-1063` (rebuild by stable id); `IslandContentView.swift:2059-2070` (`ClearedRowView`); `KeySession.swift:27-75` (the walk).
- **Test scenarios:**
  - *Happy path:* narrowed fixture → `actionableIDs(...)` equals the ids of the drawn rows plus `jump:github`; empty query → no `jump:github`.
  - *Edge cases:* the selected row narrows away → index clamps (existing `rebuild` rule) and never lands on an undrawn id; all lanes empty → walk is `[jump:github]` only; a poll tick that adds a matching row → it appears and the selection stays by id.
  - *Integration:* in the app, ⌃⌥G → `214` → ⏎ opens `…/pull/214` and hides; `xq-zeta` → ⏎ opens a github.com search URL; a branch name of your own PR narrows with no network activity (watch `GITHUD_DEBUG` for no extra fetch).
- **Verification:** AC 1, 3, 5, 6, 8 hold in the running app; O1's subset assertion is green.
- **Proven through:** Core suite for the agreement rule; the human exercise below for the end-to-end path.
- **Runtime evidence:** `unverified — scripts/build-app.sh && scripts/run-app.sh, then the three flows above at the keyboard`.
- **Checkpoint:** `pause — the human runs the built app: ⌃⌥G, type a number, a branch of their own PR, and free text; ⏎ on each; esc twice; a mouse-summoned island ignores letters.`
- **Pause warrant:** *new evidence:* whether a full rebuild per keystroke is visibly laggy on the real island, and whether the pasteboard path and the space rule feel right at the keyboard. *Human decision:* keep the per-keystroke rebuild or move to an in-place narrowing; keep D4 or amend it (recorded in the amendments log). *Affected tail:* U5's law wording (if narrowing changes shape) and the proof recording. *Why unavailable earlier:* the feel of typing into a rebuilt island exists only once U3+U4 run on the glass.

#### U5. Laws, README, and the input-routing proof

- **Goal:** the documents that promise behaviour say the new behaviour, and the merge condition the loop's doctrine names is met.
- **Requirements:** AC 10, 11, 12; D5
- **Dependencies:** U4
- **Files:**
  - Modify: `docs/TOPOLOGY.md` (L1 lines 36-37 and the boundaries list 45-54: a third boundary, "Narrowing"; L2 lines 56-58: the narrowed lane vs. the counting surfaces, header count as disclosure; L3's gloss: the GitHub destination row is walked, so it is not a G3 case)
  - Modify: `Tests/GithudCoreTests/main.swift` (the law assertions the agent could not locate by name — find the suites that grade L1–L3 by their behaviour and extend them with a narrowed case; if none exist for L1/L2 as such, add one suite per touched law, named for the law)
  - Modify: `README.md:185-197` (add "Jump to a row — type after ⌃⌥G"; `esc` "clears what you typed, then puts it away")
  - Create: the input-routing proof artifact for the widened session, wherever the WP-6k proof lives (`loop/evidence/wp6k-key-session.manifest.json` is the precedent; `scripts/ax-drive.swift` exists untracked and may be the driver)
- **Approach:** law text first, then the assertions, then the README, then the proof. The
  proof shows that with a foreground editor active, ⌃⌥G + typing lands in the island and the
  editor's caret receives nothing, and that after esc/⏎ key returns to the editor.
- **Patterns to follow:** `docs/TOPOLOGY.md:15-16` (the forcing function); `docs/design/2026-07-06-designer-session-agenda.md:191-196` (what the proof recorded last time).
- **Test scenarios:** *Laws:* a narrowed island's drawn rows + the header count account for every admitted row (L1 with the new boundary); walk ⊆ drawn (L3); never `0 of M` (L4). *Test expectation for README and proof:* none — prose and a recorded artifact.
- **Verification:** `scripts/test.sh` green; TOPOLOGY diff touches L1, L2 and the boundary list; README table has the new line; the proof artifact exists and its manifest names the recording.
- **Runtime evidence:** `unverified — the proof recording is the evidence; it requires a human at the machine with a second app in the foreground`.
- **Checkpoint:** `auto — scripts/test.sh; the proof is reviewed by the human at merge time`

### Scope Boundaries

- No text field, no second responder, no new hotkey, no network request from the app on any key.
- No matching on Needs-you or Inbound branches (they have none), no fuzzy matching, no highlight of the matched substring in rows.
- The collapsed pill, the mouse-summoned island, and the empty-query island are unchanged.
- The sketch file is a design record, not a spec for pixel values; the header keeps its current geometry.

#### Deferred to Follow-Up Work

- In-app resolution of a handle on ⏎ (one search call, land on the PR): a separate agenda entry, after this ships and the URL fallback has been used for a while.
- Copy chords (⌘⏎ link, ⌘B branch, ⌘K checkout): follow-up on the same session machinery.
- Match highlighting in row text through `RadarPresenter.displayLine`.
- G3 (departure receipts not walked) remains open; this plan does not touch it.

### System-Wide Impact

- **Interaction graph:** `SummonHotkey` → `beginKeySummonSession` (seeds the query) → `HUDPanel.keyDown` → `handleSessionKey` → `render()`; `setExpanded(false)` and `endKeySummonSession` clear the query (every collapse path already funnels through them). `HUDPanel.performKeyEquivalent` gains one branch ahead of the ⌘ probe, active only while `keySelection != nil`.
- **Error propagation:** none new; the GitHub row opens a URL, and a pulse decode failure keeps last-good rows exactly as today (the branch field is optional).
- **State lifecycle risks:** the query must die with the session in every teardown path (`endKeySummonSession` is the choke point; `setExpanded(false)` calls it). A stale query surviving into a mouse-summoned island would violate D6: the assertion is that `jumpQuery != nil iff keySelection != nil`.
- **API surface parity:** VoiceOver: the header's AX label speaks the query and the count; the GitHub row is a button with the destination as its label.
- **Integration coverage:** the human exercise in U4; the proof in U5.
- **Unchanged invariants:** `KeySelection` movement rules (clamp, no wrap, rebuild by id); the five original key meanings when the query is empty; the never-key resting state outside a session; the redraw-on-change-only contract on poll ticks (a keystroke is a user change, so its rebuild is honest).

### Build Execution Contract

- **Closed decisions:** D1–D7 above; narrowing happens once in the controller and feeds both consumers; `JumpQuery` is Core and I/O-free; no timers.
- **Builder autonomy (record and continue):** exact caret glyph and ink tier; the destination row's SF Symbol; whether `Narrowed` is a struct or a tuple; the order of new suites in `main.swift`; the fixture file chosen for `headRefName`; splitting U3's `HUDPanel` change into its own commit.
- **Verify at contact:**
  - `headRefName` is a scalar on GitHub's `PullRequest` object → check GitHub GraphQL docs or run a query with the PAT → if absent, use `headRef { name }` and decode the nested shape.
  - `HUDPanel.keyDown` receives printable keys during a session (no responder ahead of it) → `GITHUD_DEBUG=1` and press a letter after ⌃⌥G; the existing log shows nothing today because letters are passthrough, so add the O3-safe log line first → if a responder swallows them, make the panel's first responder `nil` explicitly at session begin.
  - `NSPasteboard.general.string(forType: .string)` returns the branch name an agent's terminal copied → paste a value; if the pasteboard holds RTF only, fall back to `.rtf` → plain conversion or skip paste with a log line.
  - The law tests exist as named suites → grep `main.swift` for "conservation", "linearization", "no zero"; if graded only implicitly, add one suite per touched law (U5 says so).
- **Stop conditions:** `scripts/build-app.sh` fails for a reason outside the touched files; the pulse decode throws with the new field present in the fixture (meaning the DTO shape is wrong and the honesty rule would blank Your PRs); a keystroke after ⌃⌥G reaches the foreground app instead of the panel (the routing proof fails).
- **Authority boundaries:** no push to `main`; no edits under `loop/` except the new proof artifact and its manifest (CONTRIBUTING reserves `loop/` for the maintainer, who is the builder's principal here); no real PAT in any fixture or log; the release/tag flow is not this plan's.
- **Expected gate map:** U1 → `scripts/test.sh` green. U2 → `scripts/test.sh` green; `scripts/build-app.sh` green. U3 → both green; the rewritten key-map suite is the only test whose expectations changed, and each changed line names the new rule. U4 → both green; new subset/last-row suites green. U5 → both green; TOPOLOGY diff present.
- **Pause warrants:** U4 only (recorded above).

### Risks & Dependencies

| Risk | Mitigation |
|---|---|
| Full rebuild per keystroke feels laggy on the glass | U4 pause measures it at the keyboard; fallback is in-place narrowing inside `IslandContentView` fed by the same `Narrowed` value (the seam stays) |
| A responder ahead of the panel swallows printable keys | Verify-at-contact item 2; `makeFirstResponder(nil)` at session begin |
| `headRefName` typo blanks Your PRs (honesty rule) | Fixture-driven decode test in U2; runtime check with a PAT before merge |
| Space rule (D4) surprises at the keyboard | U4 pause; amend D4 in the amendments log rather than silently |
| Law text and assertions drift | U5 edits both in one commit; the forcing function at `TOPOLOGY.md:15` |
| The proof recording needs a human and a foreground app | Named as the merge condition in U5; the package parks unmerged without it, per `loop/PRESSURE.md:22-37` |
