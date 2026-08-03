# WP: the inbound sweep — standing "at your door" lane (issues + incoming PRs)

*Distillation brief + package spec (substrate seam, 2026-07-09). Written so a fresh
session can pick this up with zero prior context.*

## Intent (the user's words)

> "i want to work on catching issues and incoming prs (separated from mine) first"

A **standing** surface for open issues/PRs that OTHERS opened on repos the user owns —
separated from "Your PRs" (the pulse lane, which is the user's own authored PRs). This
completes what the event channel structurally cannot do: show what is *already open*
regardless of notification read-state or watch history.

## Load-bearing state

- **User decisions (ratified 2026-07-09):** own repos only (org/allowlist = future
  config); default ON; its own surface, separated from "Your PRs".
- **Why the event channel isn't enough (live-diagnosed):** the user's repos were
  unwatched until today (61 repos subscribed 2026-07-09 — future events now flow into
  the landed `inbound` derived reason, 81df372); notifications are unread-only and
  event-shaped — the 8 pre-existing open items (incl. a Dec-29 human PR on mcp-filter)
  can never appear through it.
- **Transport:** ONE authenticated search — `GET /search/issues?q=user:{selfLogin}+is:open+-author:{selfLogin}`
  — returns issues AND PRs (`pull_request` key distinguishes), with `user.login`/`user.type`
  (bot detection is DIRECT — no enrichment pass needed), `html_url`, timestamps, `draft`.
  Search bucket: 30 req/min authenticated (separate from core REST + GraphQL). Poll at
  the pulse cadence (~60s tick) = well under budget. No reliable 304s on search — accept
  the full GET; eventual consistency (seconds-to-minutes lag) must be reflected honestly
  in freshness semantics, never fabricated away.
- **selfLogin:** the pipeline resolves it via `/user` (`RadarPipeline.resolveSelfIfNeeded`);
  the sweep QUERY needs the literal login — no login resolved → no sweep (never guess;
  same honest degradation the derived reason uses). Login is `pro-vi`.
- **One-home rule — SUPERSEDED AT BUILD (recorded in the agenda):** this spec
  recommended filtering the radar's derived rows; the build chose DUAL-PRESENCE instead
  (event row = arrival announcement, dies on read; queue row = standing debt, persists —
  the review_requested-in-radar+pulse precedent). The panel's trust lens ratified it as
  "two facts, not redundancy". `review_requested` rows stay on the radar either way.
- **Bot policy:** same demotion doctrine — human items lead; bot items (login `[bot]` /
  `user.type == "Bot"`) collapse to a quiet caption (the stale-PRs pattern: "3 bot PRs ·
  gear → Show bots"), default-off toggle.
- **Current live truth (for proofs):** 8 open inbound items on pro-vi/*: mcp-filter#1
  (PR, @arun, 2025-12-29), #2+#3 (issue+PR, @kesh), agent-dice#1 (issue),
  designer#110 (PR, @tomo) + designer#109/#111/#112 (bots).

## Target conventions (this repo's)

- Gauntlet: build → 3-lens adversarial panel (**Opus subagents** — standing user
  directive) → fix round → focused re-verify → ledger records → commit with PRESSURE
  burdens → push (private pro-vi/githud; push authorized).
- Pure Core (`Sources/GithudCore`, zero-dep test runner `bash scripts/test.sh`, 966
  checks at 81df372) / AppKit shell (`Sources/GithudApp`, NO test runner — app-side
  logic must be declared untested in commits).
- Doctrine: never fabricate a state (a failed search ≠ "0 open" — freshness/pulse-honesty
  precedent applies to the new lane's mappers, per-cell tests); ink by default, color
  only on changed-next-move; calm never busy; Open-on-GitHub is the action ceiling;
  motion maps 1:1 to user action or real change.
- Model the lane on the PULSE lane (PullRequestPulse/PulsePresenter/PulseRow →
  IslandContentView section with header + capped scroll pane), NOT on the notifications
  machinery.
- Ledger homes: docs/design/2026-07-06-designer-session-agenda.md (amendments section),
  docs/plans/2026-07-02-002-runner-elegance-roadmap.md (Runner State table),
  loop/PRESSURE.md (signal-trust re-audit on any new feed source — this IS one).

## Do NOT carry (contamination from the event-channel package)

- The reason taxonomy (`effectiveReason`, `SurfacePreferences` reasons, novelty doors) —
  the sweep has no reasons; it is a search-result model.
- The enrichment passes (subject-state / comment-author) — search results carry author
  + state directly; nothing to enrich.
- The era-stamped preference migration — the sweep's toggle is a NEW preference
  (default on), no legacy snapshot exists.
- `NotificationThread` — the sweep gets its own Core model + decoder.

## Next move

Build the Core model first: `InboundItem` (decode from search JSON) +
`InboundPresenter` (human/bot split, WAITING-LONGEST-first — a triage queue, corrected
from this line's original "newest-first"; age-at-render, honest empty-vs-failed states) + tests against a committed fixture cut from the REAL search response; then the
poll plumbing (pulse-cadence tick, selfLogin-gated), then the island section ("Inbound"
header between the radar and "Your PRs"), then the gauntlet.
