# Contributing to githud

Standard PRs are welcome.

## The most valuable thing you can contribute

githud's entire premise is a trust bet: it never silently hides something you
needed, and it never cries wolf. The two issue templates —
[**missed notification**](.github/ISSUE_TEMPLATE/missed-notification.md) and
[**false alarm**](.github/ISSUE_TEMPLATE/false-alarm.md) — turn your daily use
into the signal that keeps the classifier honest. Filing one of those, even
without any code, is the single highest-leverage contribution to this project.

## Making a code change

1. Fork, branch, make your change.
2. Run the test suite — no PAT, no GitHub account, no Xcode required:
   ```sh
   scripts/test.sh
   ```
   (It builds and runs the zero-dependency `GithudCoreTests` runner; see
   `Tests/` for why this isn't plain `swift test`.)
3. If your change touches the app shell, also confirm it builds:
   ```sh
   scripts/build-app.sh
   ```
4. Open a PR describing what changed and why.

## `loop/` and `docs/plans/`

`loop/` and `docs/plans/` are this project's AI-pairing dev log — generated
working context for an iterative build process, not hand-authored
documentation. Please don't edit them in your PR; if a PR needs to reference
something in there, quote it in the PR description instead. `README.md`,
`Sources/`, and `Tests/` are the surfaces a contribution should touch.
