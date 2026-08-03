---
title: "Just cleared" — a departure receipt on the island
objective: A row leaving "Needs you" gets an on-glass receipt the user can reveal — answering "it disappeared, where did it go?" without ever showing a not-needed thing unasked
type: feat
status: completed
date: 2026-07-21
origin: dogfood 2026-07-18 ("it showed a comment for a quick second and disappeared.. i think that was valid - where did it go?") → six-direction adversarial pass 2026-07-21 killed the dim-in-place form and produced this in-family heir; user ratified existence + caption B1 from the mockup gallery
---

## Background (read cold)

Rows leave "Needs you" through several doors — read on GitHub, review submitted (discharge),
subject merged/closed (verdict), plain feed departure — and today they vanish without receipt.
The suppressed set audits *demotions* but not *reads* (`applyThreadsRead` removes the thread from
the reading entirely), so the one question dogfood actually asked ("where did it go?") has no
on-glass answer and no off-glass one either for the read path.

The adversarial pass killed the Gitify-style dim-in-place row on four grounds (reason unknowable
for plain feed drops; the consolidated latch is deliberately reason-blind; a self-expiring ghost
fights the one-transition-per-burst morph rule; duplicate home). The surviving form is this plan:
one reveal-line in the ratified revealed-header family.

## Architecture Decision

**Approach:** a session-scoped departure buffer in `RadarReading` (Core, tested — every departure
door already flows through it), surfaced as ONE caption line in the ratified family —
**"N just cleared (show)"** (caption B1, user-ratified 2026-07-21) — revealing a "Just cleared
(hide)" band of dimmed one-line rows. Display-only ghosts OUTSIDE `radarRows`: the band can never
block, delay, or fake the affirmation, and never enters the pill/glyph/spoken counts.

**Reason honesty:** a row's reason suffix appears ONLY when githud actually knows it —
`read ✓` (thread read-check), `review submitted ✓` (discharge), `merged` / `closed` (verdict).
A plain feed departure shows NO suffix, never a guess. This is the load-bearing difference from
the killed form: unknown-reason rows are acceptable in a revealed audit band; they were the
design-language violation as unlabeled in-place corpses.

**Rejected alternatives:** dim-in-place (killed, above); widening `consumeResolutions` to carry
per-departure reasons (blast radius into the deliberately-minimal latch; the buffer needs no
reducer change at all); persistence in `Snapshot` (a "just cleared" band that survives relaunch
is stale tense — session-scoped is the honest scope, and the suppressed set remains the durable
audit).

**Trade-offs:** synthetic review-owed departures are deferred (v1 captures real-thread doors
only — the discharge door covers the CLI-review case, which is the one that needed the receipt);
count-capped at 8 (oldest fall off silently — the cap IS disclosed by the band being "recent",
not a ledger).

## Implementation Units

### U1 — the departure buffer (Core)
`RadarReading.recentlyCleared: [ClearedEntry]` — `ClearedEntry { thread: NotificationThread,
why: ClearedWhy? }`, `enum ClearedWhy { read, reviewSubmitted, merged, closed }`. Capture sites,
all in `RadarReading` (surfaced-only — a departure of an already-suppressed thread is not a
"cleared from Needs you"):
- `applyThreadsRead` → `.read`
- `applySubjectVerdict` (terminal, thread was surfacing pre-verdict) → `.merged`/`.closed`
- discharge binding creation (`reconcileDischarges`) → `.reviewSubmitted`
- `adopt200` — old surfaced threads absent from the new feed → why nil
Cap 8, newest first, dedup by thread id (re-capture replaces). Session-scoped, never persisted.
Tests: each door captures with the right why; suppressed departures don't capture; cap + dedup;
re-arrival (thread returns to the feed) removes its entry.

### U2 — display rows (Core)
`ClearedRow` (repo, title, effectiveReason, whyText: String?, id) + a presenter fn (PlainWords
strings: caption `justClearedCaption(n:)` = "N just cleared", header "Just cleared", why texts).
Tests: why-text mapping, no-suffix-on-nil, caption pluralization.

### U3 — seam + model (App)
Scheduler captures `source.recentlyCleared`-derived rows queue-side per tick (the
`resolvedSelfLogin` pattern), delivers via `onCleared` → `model.setCleared` (change-guarded
notify). `RadarSource` gains the read accessor. Reveal pref `showJustCleared` follows the
`showHeldBackInbound` store pattern (persisted, gear-owned; the caption is a button flipping it).

### U4 — the band (App)
Caption line + revealed header "(hide)" + dimmed one-line rows in the revealed-header family
(the `IslandContentView` pattern the Drafts/gone-quiet bands use). Rows: dimmed ink, reason
suffix right-aligned, click = Open on GitHub (the action ceiling). VO: one stop per row, caption
speaks count + state. No animation beyond the band's existing reveal grammar.

## Scope Boundaries
- No persistence; no Snapshot change; no reducer/latch change; no pill/glyph/count change.
- The affirmation's inputs are untouched (band rows live outside `radarRows`).
- Synthetic review-owed departures: deferred (below).

## Deferred to Follow-Up Work
- Synthetic-row departures entering the buffer (needs a StandingReviews diff hook).
- Time-based expiry (session cap-8 first; add a clock only if dogfood shows stale-tense rows).
- The mark/logo path may restyle the dimmed rows; the band's structure is independent of it.
