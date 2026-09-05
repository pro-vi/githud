---
title: Quick navigator — filter the island (type-to-jump)
date: 2026-09-04
status: RATIFIED 2026-09-04 — user picked thesis A ("lets do A first"); the two build-time
  forks below (input model, fallback row) were delegated to the runner ("go figure it out")
  and are decisions D1/D2 here, amendable at build with a recorded note.
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

After the U4 pause, the owner reported “the white thing looks ugly on open and no inline input on invoke” and requested screenshots and fixes. This amends AC9 for keyboard summons: the header shows an empty “Type to jump…” line as soon as the session acquires key; mouse summons keep the ordinary header. Selection uses a stronger background highlight instead of the white edge strip. D1 still holds: no editable field. The no-match state keeps one sentence; its extra paragraph was removed after a native render showed horizontal overflow. Native AppKit view renders cover mouse, empty-session, number, no-match, and long-query states in two themes. They do not prove global shortcut delivery or foreground-app focus return. The computer-use runtime failed before capture with `process is not defined`. D4 and the per-keystroke rebuild remain unchanged pending the keyboard exercise.

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
