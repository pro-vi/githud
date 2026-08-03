# WP 2026-07-16-001 — the waking face: Glyphling g replaces the loading dot

*Ratified 2026-07-16 (mark session, seed 2026-07-12-002; gallery
docs/design/2026-07-12-mark-settings-mocks.html, "gesture pack" section). The
user ratified the gesture pack as mapped and explicitly SKIPPED any live-state
extension ("so maybe skip this") — the creature appears in the bar ONLY during
loading. The ✓ and every other pill glyph stay exactly as ratified.*

## Scope — one piece

The collapsed pill's **loading state** (pre-first-poll; today an 0.38-alpha dim
dot) renders the **waking face**: Glyphling g, night-pupil cut (round five #2).

Vector (viewBox 0 0 24 24, drawn at 13pt in the pill, template ink):
- Bowl: solid disc c(12,10) r6.4, sclera knockout r3.7 (same center).
- Pupil: ink disc r2.1 c(12,10); highlight knockout r0.65 c(11.15,9.75) —
  sub-pixel at 13pt; the builder may drop it from the template drawing IF
  disclosed (it exists for future scale reuse).
- Tail: stroke 2.8, round caps: M16.4 14.0 C17.9 16.6 17.3 19.6 14.3 20.5
  C13 20.9 11.8 20.6 11 19.9.

Constraints (binding):
- Drawn in code (NSBezierPath / CGPath — CLT-only repo, no asset catalogs),
  tinted with the theme's ink like every pill glyph; template behavior across
  themes and appearances.
- STATIC. No animation, no blinking, no idle motion. The face appears with the
  loading state and leaves with it, on the existing state-change repaint.
- Core shape untouched where possible: `Glyph.loading` stays the fingerprint
  case; if width must change, it changes in `PillMorph.width(for:)` (pure Core)
  with a pinned value — the face is ~13pt square vs the dot's smaller footprint,
  so the loading pill may widen slightly; pick the minimal honest width.
- Spoken value for loading unchanged.
- Reduce Motion: nothing to zero (static), assert nothing regresses.

## Proof obligations

- `swift build` clean; `bash scripts/test.sh` exit 0 (baseline: current main;
  add/update pins only where Core changes — width pin if the formula changes).
- Grep: no new Timer/animation/key-window code.
- Fingerprint/width/spoken stay in lockstep (resolve() untouched or minimally
  extended).
- App bundle rebuilds (`bash scripts/build-app.sh`).

## Recorded decisions

- Gesture pack mapping (ratified): waking → loading pill (THIS WP); noticing
  (sidelong) → README/social/welcome, printed; at ease (half-lid) → app icon.
  Icon + README faces ride the launch package, NOT this WP.
- Live-state extension SKIPPED by the user: no thinking-on-poll (poll-clock
  motion = attention theft), no half-lid-for-✓. Idle-as-confirmed-check was
  assessed and set aside; the record lives in the session transcript + gallery.
- Website eye follows the cursor (landing page, launch package); impossible in
  a GitHub README (script-stripped) — README gets the printed sidelong face.

## Landing record (2026-07-16)

LANDED at `c4f4209`, ff-merged to main; **1175 checks** (unchanged by design —
zero Core files in the diff), CI green, app rebuilt from main and relaunched at
the canonical bundle path. Gauntlet: Opus builder (worktree) → focused Opus
re-verify **LAND** (vector traced by hand incl. the y-flip transform; scope =
one file; static grep-proven; theme/appearance rebuild path verified real at
HUDPanelController:143/246/903; F5 loading width pin 52 holds incl. the
stale-prefix edge — separate chassis cells can't overlap).

Disclosed deviation (spec-sanctioned): the r0.65 highlight knockout dropped
from the 13pt template (sub-pixel); it survives in this spec's vector for
icon/README scale reuse.

Dogfood watch: the face's first live appearance rides the next cold launch
(loading is pre-first-poll only — a running app never shows it); eyeball the
dim-ink face on both appearances when it happens.
