# Living prototypes

- [Quick navigator](quick-navigator.html) — interactive search and browse behavior.
  [Metadata and scenarios](quick-navigator.json) ·
  [Implementation plan](../2026-09-04-quick-navigator-agenda.md#quick-navigator-build)

Open the HTML directly. It includes its data and needs no server or network.
Row clicks and Return display a destination receipt; they do not open GitHub.
The page's status and history come from its JSON companion, not this index.

## Editing and checking

From the repository root, with Node and `agent-browser` installed:

```sh
node scripts/prototypes.mjs sync quick-navigator
node scripts/prototypes.mjs check
node --test Tests/PrototypeChecks/main.mjs
node scripts/prototypes.mjs verify quick-navigator
```

Edit HTML layout, styles and interaction code outside the `prototype-data` block.
Edit metadata, scenarios and meaningful decision history in the JSON companion.
Edit synthetic rows in the referenced fixture file, never in the generated block.
Then run sync, check and verify. Sync only replaces that block; check never writes.

The browser verifier uses its own session and saves a report and screenshots to
a fresh local directory. Missing tools or failed checks are errors, not passes.
It never installs a browser or closes another session.

For app changes, also run:

```sh
scripts/test.sh
zsh Tests/GithudAppSnapshots/run.sh
scripts/build-app.sh
```

## What lives where

- Git records exact revisions and authors. Keep one evolving HTML file per ID.
- The JSON companion owns current metadata, stable scenario IDs and decision history.
- The fixture file owns synthetic row facts and a fixed reference time.
- Swift owns production query meaning. Native tests read the same cases and check
  declared outcomes; browser checks alone do not certify the app.
- The agenda owns the build contract. HTML is an interactive design reference,
  not another implementation specification.

The prototype freezes displayed ages. Native row views use the actual clock, so
their captures record time rather than promise identical age pixels. Browser
focus, IME and editing are not AppKit or WindowServer input-routing evidence.

## Evolution

Add history for a changed interaction contract, accepted variant, changed scope,
implementation verification or supersession. Record the date, actor, what changed,
why, and its source. Do not invent an owner's rationale from an architect's opinion.
Spacing-only edits can rely on their Git commit.

Use `exploring`, `selected`, `implemented` or `superseded` for the current design
revision. `implemented` requires an existing app commit, current design fingerprint,
and native evidence. It describes that commit and covered scenarios—not every later
app version. A design edit invalidates that link; clear it and return to selected or
exploring until verification is renewed. Browser toggles never approve a design.

Scenario IDs survive label changes. Links may carry a scenario ID and normal/short
viewport; arbitrary typed queries are never saved to the URL or storage. Add expected
results before fixing an implementation. Never calculate expected values with the
matcher being tested.

To add another prototype, add its HTML, JSON companion and synthetic fixture, then
link it here. Keep the format and tooling small. Do not copy personal cached data,
add a remote data importer, or migrate dated historical mocks into the suite by bulk.

## Build-time choices

Schema version 1 represents row sets using existing Core Codable display-row shapes.
Scenario preferences use explicit booleans and owner lists; the test-only Swift
adapter constructs the existing preference types, which are not Codable. Initial
session and freshness values are closed vocabularies. This avoids changing production
types merely to support a prototype.

The fixture rows and named cases are newly authored synthetic data.
Existing endpoint fixtures and the personal-data temporary sketch were not imported.
