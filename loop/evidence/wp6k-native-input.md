# Native quick navigator — input-routing proof

Recorded on 2026-09-08 using the real app entry point with committed fixtures.
The owner authorized native macOS recording and synthesized global keyboard input
after the desktop automation service failed. No secret or clipboard values were used.

The [manifest](wp6k-native-input.manifest.json) pins the tested source files,
fixture binary, driver, screenshots, recording, and test logs by SHA-256.
Binary artifacts remain local under `build/quick-navigator-proof-GCCmVM/`;
they are not part of this commit.

## Live observations

| Check | Observed result | Evidence |
|---|---|---|
| Global summon | Control-Option-G takes key; TextEdit stays foreground; AX focus is the native text editor | `final/02-summon.json`, `final/app.log` |
| Number and branch | Full queries remain visible beside the count; matching fixture rows and the GitHub destination are drawn | `final/03-number.png`, `final/11-branch.png` |
| Native editing | Command-A selects the query; replacement, Option-Backspace, undo, redo and Shift-1 work | `final/04-select.json` through `final/09-punctuation.json` |
| Accessible selection | The destination row reports selected, not focused; the editor retains editing focus and its caret range | `final/12-destination.json` |
| No foreground input leak | TextEdit contents are identical at every checkpoint before dismissal | `final/00-ready.json` through `final/14-dismiss.json` |
| Escape hand-back | First Escape clears; second dismisses; subsequent global text reaches TextEdit | `final/13-clear.json` through `final/15-handback.json` |
| Mouse boundary | Clicking the pill opens a non-key island; subsequent global text still reaches TextEdit | `final/16-mouse.json`, `final/17-mouseinput.json` |
| Result commands | Option-Return peeks; Up/Down move selection; Return releases the editor and opens the browser | `final/20-peek.png` through `final/23-return.json`, `final/app.log` |

The synthetic repository URL opens GitHub's 404 page. This witnesses the browser
transition, not a successful fetch of a real pull request.

[Watch the 60-second recording](../../build/quick-navigator-proof-GCCmVM/final/input-routing.mov).

## Findings corrected before the final recording

The first live run showed only the last query character when the count appeared.
A flexible spacer competed with the editable field for width. Removing that spacer
left the field as the flexible header element. The final screenshots show the full
number and branch; the external AX editor reports a width of 384 points.

The selected row initially lacked an accessible selected state. It now exposes
`AXSelected` independently of the native text editor's `AXFocused` state.

Native regression assertions cover header width while count visibility changes,
selection transitions, and the actual controller's empty/whitespace/no-match/match
count behavior. The final runs passed 1,837 Core checks and 163 native checks;
`scripts/build-app.sh` passed. The first selection assertion used a legacy AX getter;
the modern getter and external AX query agree in the corrected test and live run.

## Limits and cleanup

Real IME candidate UI, foreground composition during summon, VoiceOver speech,
and a human-hand recut remain unwitnessed. Marked-text routing is exercised by the
native integration tests, not claimed from this recording. Clipboard contents were
not accessed. Poll/theme/display transitions are covered by native integration
checks, not this fixture recording.

The first recording was interrupted and discarded by macOS. The final recording
ran to its natural 60-second completion, exited successfully, and was inspected
through extracted frames as well as the checkpoint stills.

Both fixture processes were terminated. The disposable TextEdit document was saved
and closed; existing TextEdit documents were left alone. The rebuilt normal app was
restored at `build/githud.app` with bundle identifier `me.provi.githud` (PID 83867
at verification). Existing untracked files and unrelated application state were
preserved. The fixture browser tabs were left open.
