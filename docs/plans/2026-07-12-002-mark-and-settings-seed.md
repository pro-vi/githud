# Session seed 2026-07-12-002 — the mark (menu bar + loading) and the settings surface

*User direction, 2026-07-12 (verbatim intent): focus on "the loading and the logo,
the logo in the menu bar"; and "the settings menu is probably re-thinkable — whether
it deserves the UI, like integrated setting … or the pop menu, like a good one
actually." The drag-the-island idea from the same conversation was explicitly
set aside by the user ("ignore the drag") — recorded, not designed.*

## Thread 1 — the mark

The insight that makes this a design brief and not just "make a logo": the mark's
first-class rendering target is the **pill's loading state** — ~13px of monochrome
ink inside the menu-bar capsule (today: a dim dot, deliberately claim-free).
Loading is the one state with nothing true to display, so identity is the honest
filler (a mark asserts nothing about the inbox — doctrine-clean). Precedent: the
island header already shows the bare "githud" wordmark when no radar titles it.

Constraint set (binding for any mark candidate):
- Legible + characterful at **13px** first; app icon (128/512) and README second.
- Monochrome ink (template image: black-on-light, white-on-dark). Never depends
  on color (color-doctrine: color is spent on alerts, not decoration).
- Must not collide with the app's spent SF-Symbol vocabulary (tray = door queue,
  shield = protection), nor read octocat-adjacent / git-fork-generic.
- Sits beside SF Symbols without pretending to be one.

Session: 3 Opus designers × 2 directions each, three angles — letterform (g/gh),
instrument (radar/island/HUD geometry), system-native (SF-optical, one degree of
deviation). Gallery renders every candidate at real 13px in a menu-bar mock, in
the loading pill in situ, and at icon scale, both appearances.

## Thread 2 — the settings surface

Today's inventory (StatusItemController, right-click or gear):
- **Surface…** submenu — the trust-critical config (which reasons surface) +
  "Your PRs:" reveal toggles + "Inbound:" held-back toggle
- **Theme** submenu — a blind pick (no preview — inconsistent with the ratified
  config-with-preview doctrine)
- **Pill style…** — opens the island chooser card (the D-pill precedent)
- **Launch at Login** · **Hide/Show island** · **Quit githud**

The tension the user is naming: the menu now mixes three kinds of item —
system verbs (Quit/Hide/Login), quick toggles (now ALSO reachable in-island via
(show)/(hide) — the gear copies are second handles), and preview-bearing config
(Theme, Pill style) of which one got the card treatment and one didn't. D-pill's
ratification ("config with actual visual preview") is a standing philosophy;
Theme is exactly its material.

Options for the gallery (mocked, honest):
- **A — a good menu**: keep the pop menu, restructure it properly (grouping,
  no blind submenus for preview material). Limit: menus cannot preview.
- **B — one settings card**: generalize the pill-style chooser into a single
  island Settings card (theme swatches live, pill styles live, surface reasons,
  reveal toggles); the menu shrinks to verbs (Hide, Launch at Login, Quit,
  Settings…). The doctrinally-aligned extension of D-pill.
- **C — hybrid tuning**: menu stays the toggle home; only Theme graduates to a
  card beside Pill style (two cards, no unified surface).

## Round two (2026-07-14) — warmth

Round one set aside by the user ("not happy on the logos"), preceded by an
octocat probe ("play on the octocat theme but with octo something else") —
declined on GitHub brand terms (Octocat derivatives prohibited; the association
IS the derivation) + accessory-positioning + 13px physics; the user accepted.
Diagnosis: the impulse behind octocat = wanting LIFE/character; round one was
the logo equivalent of the "very AI" copy the plain-words session killed.

Round two: 3 new Opus designers × 2 directions — creature-from-githud's-world
(The Watch owl / The Sweep lighthouse-with-beam), pixel-era favicon idiom
designed AT 13px (The Keeper pixel lighthouse / At Your Door keeper's cottage
with the door notched from the bottom edge + pulsable half-tone windows), and
humanist letterform (Quill broad-nib italic g / Inkwell upright g with ball
terminal). Gallery updated in place (round two leads; round one demoted to a
comparison section). Also recorded: drag-the-island set aside by the user.

## Round three (2026-07-14) — the ratified direction

User picked a synthesis off round one's Bead g: "lets build on bead g and go a
bit cthulu with tentacles and horns and a bit like mercury sign" — horns above
the bowl (☿'s crescent), tentacle descenders where Mercury wears its cross.
Ownable (Mercury + Lovecraft = public commons; zero Octocat adjacency). Round
two thereby superseded, kept in the gallery for comparison.

Executed as a refinement round: 3 Opus designers × 2 variants (sigil / creature
/ letter-first emphases) + 1 variant by the runner itself (user request:
"you should also make 1 urself considering subagents are all opus") —
render-verified at 256px via qlmanage before inclusion. Seven variants arranged
letter→creature→sigil: Horned Bead g, Deep g, Mercury's Imp, The Warden
(runner's), The Familiar, Hermes Hook, Grimoire ☿. The decision is a dial (how
far toward the otherworld), hybrids cheap. Gallery updated in place.

## Round four (2026-07-14) — the living glyph

User shared an alphabet-creature reference (Unown; "something like this!! but G
shaped"): the letter whose counter is a big EYE. Translates natively to template
ink (solid bowl / knocked-out sclera / ink pupil / highlight-knockout at scale).
IP handled plainly: the letter-with-an-eye move is generic; our g is drawn from
our own Bead g, nothing traces Nintendo's creature.

Executed by the runner directly (standing user preference from round three) —
three cuts, each qlmanage-render-verified: Glyphling g (clean lowercase, eye
only), Glyphling G (uppercase ring+bar, floating pupil — closest to the
reference's composition), The Warden awake (round three's horns+tentacles with
the eye opened — the full synthesis). Suggested split recorded: Glyphling g in
the bar / Warden-awake as icon+README. Pupil-blink-on-poll noted as an honest
loading-pulse candidate.

## Round five (2026-07-16) — Glyphling g, fine cuts

User ratified round four's Glyphling g base ("i like the 1st one") and asked
for six subtle variations. Runner-made, one trait per cut, all
qlmanage-render-verified: 1 Wide-eyed (sclera 4.1), 2 Night pupil (2.1,
dilated), 3 Sidelong (gaze up-right), 4 Half-lid (calm lid, top third),
5 Heavy tail (3.4, reference limb weight), 6 One horn (single Warden wedge,
asymmetric). Awaiting the cut pick (combinations invited) — that pick unlocks
the loading-pill WP.

## The gesture pack (2026-07-16)

User: "2 3 4 feels like a coherent gesture pack" — recognized correctly: cuts
2/3/4 vary only the GESTURE (pupil dilation / gaze / lid) on identical anatomy,
so they form one creature's expression vocabulary. Proposed doctrine-shaped
mapping (one face per home, no mixing, no idle animation, never inside live
pill states): waking (night pupil) → the loading pill; noticing (sidelong) →
reader-facing surfaces (README/social/welcome card); at ease (half-lid) → the
app icon. Awaiting one-line ratification of pack+mapping; that unlocks the
loading-pill WP with the night-pupil face.

## RATIFIED (2026-07-16) — the mark thread closes

User ratified the gesture pack as mapped (waking→loading pill / noticing→README
printed / at-ease→app icon), SKIPPED the live-state extension ("so maybe skip
this" — the ✓ stays; assessed idle=confirmed-check-state answer recorded in the
gallery + transcript), and added: the WEBSITE eye follows the cursor (live demo
now in the gallery; impossible in a GitHub README — GitHub strips scripts, so
the README gets the printed sidelong face). Loading-pill WP spec:
docs/plans/2026-07-16-001-loading-face-wp.md. Settings thread (A/B/C) remains
open.

Eye-tracking rule (2026-07-16, settled in THREE beats on the live demo — the
anatomy the user holds: light disc = IRIS, dark dot = PUPIL, the seeing part):
(1) runner welded dot to iris at a fixed up-left offset — user: doesn't track;
(2) runner tried the animator's fixed-catchlight — user overruled ("the dot is
the eye"); (3) user's screenshot nailed it: looking bottom-right, the dot still
aimed top-left. RATIFIED: double articulation — the iris shifts toward the
cursor (clamp 1.5u) and the dot slides ACROSS the iris the same direction
(0.9u), LEADING the gaze, aimed at the visitor. Binding for the landing page;
the static 13pt template is unaffected (highlight dropped at that scale).

Polarity note (the root of the three-beat confusion, settled 2026-07-16): the
dot is a KNOCKOUT in a template mark, so its read flips with the ground — on
light grounds it renders as a light fleck (glint); on dark grounds as a dark
dot on a light disc (pupil). RATIFIED READING: it is the PUPIL, everywhere;
behavior follows (leads the gaze). Icon/README/landing renderings must honor
the pupil reading regardless of ground.

## Process

Designers → gallery artifact (in-situ mocks, both threads) → one-line user
ratification per thread → build gauntlet. Marks are aesthetic candidates: no
refuter pass on taste, but every structural claim (13px survival, template
rendering, SF-collision check) renders honestly in the gallery for the user's
own eyes.
