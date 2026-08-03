# githud

[![CI](https://github.com/pro-vi/githud/actions/workflows/ci.yml/badge.svg)](https://github.com/pro-vi/githud/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

> `loop/` and `docs/plans/` are this project's AI-pairing dev log. They are a record of
> how each change was decided, not required reading. If you want the rules the interface
> follows today, read [`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) instead.

A native macOS menu-bar HUD that answers one question at a glance: **does GitHub need
me right now?**

It is not a mirror of your notifications. githud cuts the firehose down to the threads
that really need *your* action — review requests, mentions, assignments, and human replies
on your own PRs — and shows them in a calm island under the menu bar. Bots, CI, the
watch-the-repo noise, and threads where you already had the last word are suppressed. On a
real account that is usually **about 50 notifications down to a handful**.

> The moat is **signal quality + trust**, not the glass. The one thing that kills a
> tool like this is a **miss** — so githud is built to never silently hide something
> you needed, and to let you audit what it hid.

## What it does

- **Calm by default.** A small pill under the menu bar shows the most urgent kind and a
  count, for example a review arrow and `3`. When there is nothing, it is quiet. The
  all-clear mark is **earned**: if a source did not confirm this tick, the pill says
  "clear so far", not "clear". githud does not claim what it cannot check.
- **Summon on demand.** Click the menu-bar item to open the full list —
  repo · who · why · age, ranked by urgency. Click a row to **open it on GitHub**.
  githud never acts for you. It opens, you decide.
- **Needs you.** The first lane holds the threads that really need your action. It has
  two sources. One is your notifications, filtered. The other is a standing search for
  reviews you owe — because a review request stays owed after you read the notification,
  and a read notification is gone from the inbox forever. Without that search those PRs
  are invisible, which is a miss, and misses are the thing that kills this tool.
- **Just cleared.** When something leaves the lane, a small line keeps the receipt:
  `2 just cleared (show)`. Where the reason is known it says so — read, review submitted,
  merged, closed. Where it is not known it says nothing rather than guess.
- **Inbound.** A standing lane answers *"what is at my door?"* — every open issue and PR
  someone ELSE opened on repos you own, longest wait first. It is a triage queue, so the
  contributor who has waited since December leads. Bot and draft items hold back to a
  quiet count. One search per poll, no watch settings needed.
- **Your PRs.** Another lane answers *"how is my work doing?"* — every open PR rolled up
  to one state: **blocked** (CI failing, changes requested, or conflicts), **ready**
  (mergeable and approved), **waiting**, or **draft**. It never invents a state it cannot
  back: no checks is not passing, and "checking…" is not ready. When your inbox is clear
  the pill becomes a live gauge of your PRs instead of going blank.
- **Group your PRs by org.** With work across several orgs the lane can wear titles. Each
  org gets its own group, and each group ends with its own drafts and then its own
  gone-quiet PRs. You can fold an org you are not working on today, drag orgs into the
  order you want, and both settings stay on this machine. A fold **hides but still
  counts** — `acme · 4, 5 drafts, 2 gone quiet` — so nothing disappears silently.
- **Audit for misses.** The island links to your full GitHub inbox, so you can check
  whether anything githud hid actually needed you. Trust is earned, not assumed.
- **Ambient and cheap.** Conditional polling on GitHub's `X-Poll-Interval`, so a `304 Not
  Modified` costs nothing. Around 0% CPU between polls. It never takes focus from your
  work, and it shows over full-screen Spaces.
- **Settings on the glass.** Right-click the menu-bar item → *Settings…* opens a card
  inside the island. There you pick the theme, choose which reasons reach "Needs you",
  toggle the default-off sections, set launch at login, and open two more cards:
  - **Theme** — **Color** (default), **Geist Mono** (monochrome with grain), **GitHub**,
    **Dracula**, **Nord**, **Tokyo Night**, **Catppuccin**, **Solarized Dark** and
    **Light**. The monochrome themes carry state by glyph shape and weight, not by hue,
    so they stay calm and stay accessible.
  - **Pill style** — how the collapsed pill holds the inbound queue when nothing urgent
    needs you: **Door first**, **Side by side — quiet mark**, or **Side by side — with
    the count**. Each option previews with your own live data, never a fake queue.
  - **Lens** — which orgs lead and which are folded, plus the drag order.

## Setup

githud needs a **classic** GitHub Personal Access Token.

**Why classic, specifically?** This isn't a preference — it's a wall. GitHub's
Notifications API only recognizes classic PATs; fine-grained PATs and GitHub App
tokens are rejected (403 / empty response) regardless of scope. If GitHub ever
extends Notifications API support to fine-grained tokens, githud will move with it.

**What githud does with it.** Read-only, always. The token is used to poll
`/notifications` and read your open PRs — never to comment, react, merge, close, or
otherwise write anything back to GitHub. Same as everywhere else in githud: it opens
threads on github.com for you to act, and never acts on your behalf.

Create one at <https://github.com/settings/tokens> with the **`notifications`** scope. Add
**`repo`** too, so githud can tell a human reply apart from a bot on your private PRs, and
read the state of your private open PRs.

Then paste it into the app. On first run the island shows a **Connect GitHub** card with a
secure field — paste the token, press ⏎, and githud stores it in your login Keychain.

The card keeps a three-row ledger — Token, Keychain, GitHub — and a row only turns green
when the real call came back, so it never claims a step it did not do. When a step fails it
says what to do instead of just failing: a fine-grained token is refused before anything is
stored, a 401 asks for a fresh token, a 403 tells you to authorize SSO for the org.

If you would rather use the terminal, write the same Keychain item yourself. Use the
**interactive** `-w` (no value on the command line) so the token is typed at a hidden prompt
and never lands in your shell history or process list:

```sh
security add-generic-password -s githud.github.pat -a github -w
# → prompts "password data for new item:" — paste the ghp_… token (input is hidden)
```

(Avoid `-w 'ghp_…'` with the token inline — that leaks it into shell history and `ps`.)

## Build & run

Swift 5.9 or newer, Command Line Tools only. Full Xcode is not needed:

```sh
scripts/build-app.sh        # build + assemble + ad-hoc-sign build/githud.app
scripts/run-app.sh          # launch it (menu-bar agent — look under the menu bar)
scripts/test.sh             # run the test suite
```

Inspect your real radar from the terminal without the UI:

```sh
# what needs you, and what got hidden (audit the hidden set for a MISS):
.build/debug/githud probe --show-items --show-suppressed
```

## How it's built

- **`Sources/GithudCore`** — pure logic, no AppKit, testable without a window server.
  `SignalClassifier` decides reason → action-required / fyi / noise, and knows about bots
  and about you. `RadarReading` holds all the state and policy of the "Needs you" lane.
  `PulsePresenter` does the same for your PRs, including the owner lens. `PlainWords` owns
  every user-facing string, so no two surfaces can word the same thing differently.
  Around thirty types in total; those four carry most of the decisions.
- **`Sources/GithudApp`** — the AppKit shell: a non-activating `NSPanel` overlay with an
  `NSVisualEffectView` island, `PollScheduler` for live polling, and the status item.
- **`Tests/`** — a zero-dependency runner. XCTest and swift-testing need full Xcode, which
  this project does not use, so the tests are a plain executable that exits non-zero on
  failure. About 1700 assertions today.

**[`docs/TOPOLOGY.md`](docs/TOPOLOGY.md) is the one document that describes what githud is
now.** It holds the rules the interface is built from — the operators, the laws they must
obey, and the exemptions. Read it before changing behaviour. This README lists features,
which change on every release; the topology holds the rules underneath, which do not.

The architecture decision (native AppKit over Tauri, REST notifications spine, classic-PAT
auth) and the product discovery are recorded under `loop/`.

## Status

All three lanes work: "Needs you", Inbound, and Your PRs. The loop is complete — live
polling, then signal and trust filtering, then the calm pill, then summon, then the list,
then open on GitHub.

macOS only. Read-only: githud never marks a thread read, replies, or merges. Read-only is
a deliberate limit, not a missing feature — marking read on your behalf can bury something
you needed, and GitHub stays the only authority on what you have read.

Not built yet: stars and forks, and a signed release. The build is ad-hoc signed, so
Gatekeeper blocks a plain double-click — right-click → **Open** the first time, or run
`xattr -d com.apple.quarantine githud.app`.
