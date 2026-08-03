# WP 2026-07-22-001 — the g takes the bar: constant mark, working eye

*Ratified 2026-07-22 ("i see the bar thing.. it looks ok to me"). Session record:
seed 2026-07-12-002 + gallery docs/design/2026-07-12-mark-settings-mocks.html,
top section ("the g takes the bar", label halflid-in-the-bar). This RETIRES the
arcs constant-mark instrument (D-glyph) in favor of the Glyphling g with eye
states, and gives the pill's unconfirmed-clear placeholder its final form. The
gesture pack becomes the state vocabulary: probing / sidelong / half-lid at
ease, each on the state where it is true.*

## Scope — two surfaces

### 1. Status-item glyph (StatusItemController) — the g replaces the arcs

Constant mark, 18×18 template (alpha-only), all vectors in an 18-box (y-down;
the existing flipped:true draw handler matches):

- **Bowl** (every state except critical): even-odd — disc c(9,7.5) r4.8 with
  sclera knockout r2.78 same center.
- **Tail** (every state except critical): stroke 2.1, round caps:
  M12.3 10.5 C13.4 12.45 12.98 14.7 10.7 15.4 C9.75 15.7 8.85 15.45 8.25 14.9.
- **States** (replacing the current `draw(_:)` bodies):
  - `.loading` — the g + dilated pupil: disc r1.7 c(9,7.5). Whole mark at
    **α 0.55** (the waking register — dimmed identity, echoing the pill's
    inkTertiary waking face and preserving the pre-first-poll-is-tentative
    cue the old α0.40 arcs carried). SPEC DECISION, disclosed as amendable.
  - `.clearUnconfirmed(degraded:)` — the g + sidelong pupil: disc r1.45
    c(9.65,6.85). FULL alpha (never dimmed — the A2 lesson: unconfirmed is
    form-distinct, not alpha-distinct).
  - `.clear(degraded:)` — the g **at ease**: half-lid = the filled upper
    segment of the sclera above the chord y=6.525 (M6.4 6.525
    A2.78 2.78 0 0 1 11.6 6.525 Z) + resting pupil disc r1.2 c(9,8.35).
    Full alpha. (The pack's at-ease face — identical anatomy to the future
    app icon.)
  - `.action(count:, degraded:)` — the g + locked pupil: disc r1.45 c(9,7.5),
    full alpha. The count TEXT plumbing (imageLeading + title) is UNTOUCHED —
    text presence remains the structural separator from loading.
  - `.critical` — UNTOUCHED: the shield supersedes the g entirely, including
    its own degraded flanking-arc rule.
  - degraded composition (non-critical states): the dashed arcs return as
    FLANKING chrome around the g — reuse the existing `strokeArcs(dashed:true,
    outwardOffset:)` mechanism (dash 2.25/1.6, stroke 1.5, round caps) with an
    outward offset chosen so the arcs clear the g's silhouette (the
    critical+degraded flanking precedent; ≈2.2–2.5, builder verifies visually
    against the bowl's x-span 4.2–13.8 and pins the chosen constant).
- The pre-descriptor fallback glyph (`dot.radiowaves…`) and count-title
  behavior ("no title when clear/loading") stay byte-identical.

### 2. Collapsed pill (CollapsedPillView) — the eye alone for unconfirmed

- `.checkUnconfirmed` placeholder (dimmed light checkmark) → the **eye alone**,
  24-box drawn at the same ~13pt slot, code-drawn like WakingFaceView:
  iris ring stroke 2.0 c(12,12) r5.2 (no fill) + sidelong night pupil disc
  r2.2 c(12.9,11.1). Tint: theme.inkTertiary FULL alpha (form-distinct).
- `.check` (the earned ✓) and every other pill glyph: byte-identical. Width
  parity pins (unconfirmed check == check width) must keep holding.
- Accessibility strings unchanged on both surfaces (the marks carry the eye,
  the words are already ratified).

## Constraints (binding)

- Code-drawn vectors (NSBezierPath/CGPath), template behavior; NO new timers,
  NO animation (animated probing is explicitly NOT in scope — separate
  ratification). No Core state changes: StatusGlyphDescriptor/Presenter and
  PillMorph fingerprints are untouched; this WP is draw-bodies only, plus any
  test pins on drawn geometry that exist.
- All existing A2 pins hold: confirm flip 0ms same-mark, degraded composes,
  width parity, count-text rules.

## Proof obligations

- `swift build` clean; `bash scripts/test.sh` exit 0 (report baseline → final).
- Grep: no Timer/animation/key-window code in the diff.
- Render-check note in the report: at 1x (non-Retina) the sclera annulus runs
  ~1.2pt — builder eyeballs an exported 18px raster of all five states and
  reports honestly (a known accepted risk, recorded in the gallery; not a
  build blocker).
- App bundle rebuilds.

## Recorded decisions

- Retires the arcs constant-mark (audited instrument) → FULL three-lens panel
  before merge, not a focused pass.
- Loading dimmed to α0.55 (spec decision, amendable one-line).
- The two surfaces diverge at confirmed on purpose: bar = half-lid at ease
  (the watcher rests), pill = the earned ✓ (the reading concludes).
- Dogfood watches: eye-state legibility at 1x; loading/action adjacency in
  real use; the half-lid's sleepy read on the bar; first live unconfirmed →
  confirmed flip on glass.

## Landing record (2026-07-22)

LANDED at `d2535bd` (feat) + `328d24d` (fix round), ff-merged to main; **1433
checks** green at merged HEAD; app rebuilt + relaunched. Gauntlet: Opus builder
(worktree, raster-verified its own geometry at 1x/2x) → FULL 3-lens panel →
**MERGE ×3, zero mandatory findings** → six-nit fix round → focused re-verify
**LAND** (all six confirmed in code; glyph-proof exits clean over 9 states × 2
scales).

**Panel highlights:** the half-lid arc sweep independently derived and
confirmed correct; action proven structurally unable to render without count
text (one construction site, rows non-empty) — loading/action separate on two
axes; the fail-closed clear/unconfirmed gate byte-verified in Core; the α0.55
Core-constant deviation RATIFIED; the pill's eye called a doctrine improvement
over the alpha-distinct placeholder. 1x risk milder than recorded (bowl ring
≈2pt, not 1.2).

**Fix round:** uniform loading alpha via transparency layer (numerically
pinned: flat α0.549 plateau, tail-seam gone); Core + test doc sweeps off the
retired arcs vocabulary; dormant a11y label restored on the pill eye; clearance
comment honest (0.7pt equator / 0.19pt lower endpoints); dead alpha params
removed (the layer is the sole dimmed path).

**Dogfood watches:** eye-state legibility at 1x; loading/action adjacency in
real use; the half-lid's sleepy read on the bar; the first live unconfirmed →
confirmed flip on glass; the flanking arcs' near-kiss at their lower endpoints.
