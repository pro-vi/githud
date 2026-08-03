# githud loop

> **This directory is a dev log, not documentation, and you cannot run it.**
> githud was built by an autonomous AI build loop. `loop/` is that loop's working
> state — the driving prompt, an append-only iteration log, the self-grading rubric,
> and machine-generated evidence manifests. It is kept because it is an honest record
> of how the app was made, not because it is useful to a contributor.
>
> The commands below need a private toolchain that is not part of this repo, so they
> will not work for you. Nothing in `loop/` is needed to build, test, or change
> githud — see [`CONTRIBUTING.md`](../CONTRIBUTING.md) for that, and
> [`docs/TOPOLOGY.md`](../docs/TOPOLOGY.md) for the rules the app follows today.
>
> Every statement in here was true on the day it was written and was never updated.

A `/loopgen`-composed **green-field discovery loop** that builds *githud* — a
native AppKit macOS HUD overlay for GitHub power users — from zero. The loop
discovers the product and its feel without grading its own homework.

## Fire it

```
/goal read loop/PROMPT.md and execute as the githud greenfield discovery loop.
```

The kick-off is a **stable pointer** — re-send it verbatim every iteration. All
rules (which file is the goal, where state lives, the bootstrap gate) live in
`loop/PROMPT.md`; the loop is re-entrant and self-gates one-time setup on
`loop/STATE.md`.

## Before the loop can do everything — two user-owned preloop gates

The loop can scaffold the app, get a blank glass island on screen, and ratify the
rubric **right now**. To unlock real GitHub data and visual evidence, flip these
in `loop/STATE.md` when done (binary `yes`, or it stays blocked):

1. **`github_classic_pat_ready`** — create a **classic** Personal Access Token
   (scope `notifications`; add `repo` for private-repo enrichment) at
   <https://github.com/settings/tokens> and store it where the loop reads it
   (Keychain item `githud.github.pat`, or a path you record in STATE). The
   Notifications API does **not** accept fine-grained PATs or GitHub App tokens.
2. **`screen_recording_permission`** — grant your terminal/host **Screen
   Recording** (System Settings → Privacy & Security → Screen Recording) so
   `screencapture` can produce HUD evidence frames. Until then, visual rubric
   criteria cap at 2.

## Tune it

- **Rubric** — `loop/RUBRIC.md`. Edit anchors / evidence rules. Raising the bar =
  a **new `rubric_version`** with score quarantine, not a stricter restatement.
- **Intent** — `loop/INTENT.md`. Three live hypotheses (H1 inbox / H2 ambient
  presence / H3 full-client-trap). Reframing the target is a first-class move.
- **Pressure** — `loop/PRESSURE.md` (rendered from STATE `pressure_objects`). The
  weather the criteria are read in: focus-non-theft, idle-footprint, native-feel,
  classic-PAT-only.
- **Parameters** — in STATE `frontload.defaulted`: quiet-signal N=8, stuck N=3,
  user-look ~25 iters, consult ~10 iters.

## Halt it

The loop is **manual-gated** — it runs until you stop it. Set `Next action: HALT`
(owner: user) in `loop/STATE.md`, or let it reach `stone-converged` (your call:
the artifact landed on your reframed target). Shared halts (`derivation-gap`,
`signal-starvation`, `genuine-escalate`, `wrong-loop`) are session pauses, **not**
product completion — they report the work as OPEN.

## Milestones

- **Ramp (T0→T3):** build/run/test commands work → baseline → smoke validator →
  discriminative signal (focus / Spaces / notification-diff) → traces.
- **Bootstrap done:** blank vibrancy island on screen, RUBRIC v0.1 ratified,
  `score_lock` released.
- **MVP (H1):** menu-bar agent + island showing high-signal threads, hover-expand,
  click-inspector with Open-on-GitHub, conditional polling, Keychain auth.
- **North star (H2):** ambient repo-pulse presence — the reframe to watch for.

## Provenance

Archetype `greenfield` (pure, distance 0) · consult `tier-3` · evaluator `T0`
(ramp) · 4 seeded pressure rows. Architecture decided by a GPT-Pro Extended-Pro
consult (2026-06-15): native AppKit-first over Tauri. Re-run `/loopgen` (don't
hand-edit `PROMPT.md`) if intent, sources, or environment change.
