#!/usr/bin/env bash
# Leak gate. githud is dogfooded on real work data, and captured API responses get
# pasted into Tests/Fixtures/ — which is how a private employer repo, its internal
# ticket IDs, and a colleague's handle once ended up tracked in this repo. In a
# public repo that is permanent, so the check runs in CI and fails the build.
#
# Scope: the tracked working tree. Run it before publishing anything.
#
#   scripts/leak-check.sh            # scan the tree
#   scripts/leak-check.sh --history  # also scan every commit (slow; pre-publish)
#
# Placeholders this project uses instead: acme / acme-core / helios-oss / popular /
# yours for orgs and repos, alice / tomo / mira / kesh / arun for people.

set -uo pipefail
cd "$(dirname "$0")/.."

# One pattern per line: an extended regex. Keep the reason next to it.
PATTERNS=(
  'xbanker'                 # employer org, both spellings
  'x-root'                  # employer monorepo
  'ENG-[0-9]{3,}'           # employer Linear ticket ids (no \b — macOS ERE lacks it)
  'kong00lx|Lingxukong'     # colleagues' GitHub handles / branch names
  '@minna'                  # colleague handle in design mocks
  'ghp_[A-Za-z0-9]{20,}'    # a real classic PAT (the ghp_+AAA… test filler is shorter)
  'github_pat_[A-Za-z0-9_]{20,}'   # a real fine-grained PAT
  # The author's own PRIVATE repos. Public ones (designer, agent-dice, mcp-filter,
  # worldcup) are deliberately fine to name; these are not.
  'philemon|wezpup|lube-ai|fract-ai|dota-market|freekick'
)

fail=0
scan_tree() {
  for p in "${PATTERNS[@]}"; do
    # -I skips binary; the pathspec keeps the gate from matching its own pattern list.
    if git grep -nIE "$p" -- . ':!scripts/leak-check.sh' 2>/dev/null; then
      echo "  ^ leak-check: pattern /$p/ must not appear in tracked files" >&2
      fail=1
    fi
  done
}

# Scans EVERY commit reachable from any ref, plus every commit message. In a repo
# that still has pre-scrub branches this will (correctly) report them — the check
# that matters is a fresh clone of what you are about to publish.
#
# No pipelines in the conditions: `set -o pipefail` plus `head` closing the pipe
# makes git exit non-zero, which silently turned this whole scan into a no-op.
scan_history() {
  echo "leak-check: scanning all commits (this is slow)…"
  local revs hits msgs
  revs=$(git rev-list --all)
  [ -z "$revs" ] && return 0
  for p in "${PATTERNS[@]}"; do
    # shellcheck disable=SC2086
    hits=$(git grep -lIE "$p" $revs -- . ':!scripts/leak-check.sh' 2>/dev/null || true)
    if [ -n "$hits" ]; then
      printf '%s\n' "$hits" | head -20 >&2
      echo "  ^ leak-check: pattern /$p/ appears in history" >&2
      fail=1
    fi
    # -i and -E must be separate flags; `-iE` is not a valid git log argument.
    msgs=$(git log --all -i -E --grep="$p" --oneline 2>/dev/null || true)
    if [ -n "$msgs" ]; then
      printf '%s\n' "$msgs" | head -20 >&2
      echo "  ^ leak-check: pattern /$p/ appears in a commit message" >&2
      fail=1
    fi
  done
}

scan_tree
[ "${1:-}" = "--history" ] && scan_history

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "leak-check FAILED — private data must not reach a public repo." >&2
  echo "Replace it with a placeholder (see the header of this script)." >&2
  exit 1
fi

echo "✓ leak-check clean"
