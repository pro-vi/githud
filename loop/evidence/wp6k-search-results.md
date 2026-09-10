# WP-6k — direct search results

Verified 2026-09-09 against production commit `2dbd480`. Search draws browse-hidden
matches as rows, and each changed query selects the first local result. The
living prototype is linked to this code revision, not to every future revision.

## Evidence

- [Manifest](wp6k-search-results.manifest.json): source, binary and artifact hashes.
- Local artifacts: `build/quick-navigator-search-proof-XkBJFd/`. These binaries,
  screenshots and recording are retained locally, not committed to Git.
- `live/search-final.mov`: 25.001667 seconds, H.264, 1132 × 520; actual app window,
  synthetic input, natural recording completion. The sampled frame was inspected.
- `live/13-branch.png`: quiet keeper PR selected above GitHub after a no-match prefix.
- `live/16-clear.png`: native editor remains, original quiet disclosure returns.
- `live/37-mouse-type.png`: mouse-summoned browse has no jump field.
- `native/`: real AppKit row captures in both themes, including mixed results,
  no match, browse restoration, long query and a 400-point short island.
- `browser/report.json`: all 20 shared scenarios; browser screenshots are an
  offline interaction reference, not native focus or pixel-equivalence evidence.

Fresh checks: `scripts/test.sh` passed 1,841 checks; `scripts/build-app.sh` passed;
the native runner passed 455 checks; prototype tooling passed 44 checks, including
deliberately broken matcher and hidden-row controls. Search count, actual rendered
row IDs and walk order agree on the shared 25-row fixture. Native controller tests
cover clear/undo, saved preferences, same-text callbacks, caret, screen change,
editor identity and a captured local opener URL.

## Live input routing

The driver verified the fixture executable and bundle ID before acting. TextEdit
contained only the disposable synthetic document. Its exact path, document name,
front-window title and foreground process were checked before each input.
TextEdit's AX window list was empty, so its scripting interface supplied these
document checks; the fixture HUD's real AX tree supplied focus and selected rows.

The recorded sequence uses actual global events: summon, `feat` (no local match),
append `/keeper-rig` (local match selected), Down to GitHub, Escape, `keeper`,
Escape, undo, Return. Query input leaves the TextEdit document unchanged. Separate
checkpoints verify two-stage Escape, input handback, and letters reaching TextEdit
when the island was summoned by mouse. Return switches to the browser. The exact
local URL is independently asserted through the real controller's captured opener;
the live browser address was not inspected.

The live fixture uses three synthetic Pulse rows from the shared fixture, converted
to GitHub's wire shape. Dates are substituted and recorded; whole-second timestamps
are required by the existing presenter. The CLI has no fixture login, so its GitHub
search scope is not claimed identical to the shared fixture's `sample` login.
All three lanes and nondefault browse preferences are covered by the native suite.

## Limits and discarded attempts

- A three-lane search at an extreme 300-point height can reduce panes to zero in
  the existing size allocator. The verified short capture is 400 points, where
  all three panes retain at least one row. This work does not claim arbitrary-height
  support or change that pre-existing extreme-height fallback.
- Real IME candidate UI and human VoiceOver assessment were not performed.
- Offscreen AppKit captures use the existing solid test host, not live vibrancy.
- The browser's narrow viewport scrolls vertically; its initial image does not
  show the page bottom. Browser checks separately exercise result scrolling.
- Initial fractional-date fixture output incorrectly made an active row quiet;
  the converter was corrected before accepted captures. A wrong-display still was
  discarded. Videos started at collapsed-pill size are excluded from this record.
- U10's initial undo-test failure grouped setup insertion and Escape into one
  event-loop turn. Separating those actions restored native undo without app changes.

Only the fixture app was terminated and the disposable document closed without
saving. The normal app was restored. Synthetic GitHub tabs remain in the browser.
No PAT or clipboard content was handled; no unrelated files or processes were removed.
