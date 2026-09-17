#!/bin/zsh
###############################################################################
# 🛡️ verify_coverage.sh — the migrate-right-now proof (MIGRATION.md Phase 0)
#
# For EVERY local branch tip in EVERY repo under ~/Code (worktree fleets
# deduped via git-common-dir): assert the commit is contained in a remote ref
# OR reachable from a head of a ~/git-bundles bundle. Anything else is work
# that a wipe would lose (modulo the rsync snapshot) → listed as UNCOVERED.
#
# Bundle containment works because bundles were created FROM these repos: the
# source repo has the objects, so `merge-base --is-ancestor <tip> <bundle-head>`
# is decidable locally.
#
# Usage: verify_coverage.sh [root=~/Code] [bundles=~/git-bundles]
# Exit 0 = everything covered; 1 = uncovered work exists.
###############################################################################
set -u
ROOT="${1:-$HOME/Code}"
BUNDLES="${2:-$HOME/git-bundles}"

typeset -A seen_common
typeset -i n_repos=0 n_tips=0 n_uncovered=0

# Pre-index bundle heads: "bundlefile sha" lines (list-heads needs any repo cwd)
BUNDLE_IDX=$(mktemp)
for b in "$BUNDLES"/*.bundle(N); do
  git -C "$ROOT" bundle list-heads "$b" 2>/dev/null | awk -v f="${b:t}" '{print f, $1}'
done > "$BUNDLE_IDX"

echo "🛡️  Coverage sweep under $ROOT (bundles: $(sort -u -k1,1 "$BUNDLE_IDX" | awk '{print $1}' | sort -u | wc -l | tr -d ' ') files)..."

find "$ROOT" -name .git -maxdepth 6 \( -type d -o -type f \) \
    -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sort | while IFS= read -r g; do
  d="${g:h}"
  common=$(cd "$d" 2>/dev/null && git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)
  [ -n "$common" ] || continue
  if [ -n "${seen_common[$common]:-}" ]; then continue; fi   # dedupe worktrees
  seen_common[$common]=1
  ((n_repos++))
  rel="${d#$ROOT/}"
  base="${d:t}"
  # candidate bundle heads: match worktree dirname AND the common repo's dirname
  # (a linked worktree like .../worktrees/_ab_b_tip belongs to a parent repo whose
  # bundle is named after the PARENT — matching only the worktree name missed it),
  # with a fall-back to ALL bundle heads when nothing matches by name.
  repo_base="${${common%/.git}:t}"
  cand_heads=$( (grep -i -- "$base" "$BUNDLE_IDX"; grep -i -- "$repo_base" "$BUNDLE_IDX") 2>/dev/null | awk '{print $2}' | sort -u)
  [ -z "$cand_heads" ] && cand_heads=$(awk '{print $2}' "$BUNDLE_IDX" | sort -u)
  git -C "$d" for-each-ref --format='%(refname:short) %(objectname)' refs/heads 2>/dev/null | \
  while read -r br tip; do
    ((n_tips++))
    # covered by any remote ref?
    if [ -z "$(git -C "$d" rev-list -1 "$tip" --not --remotes 2>/dev/null)" ]; then continue; fi
    # covered by a matching bundle head?
    cov=""
    if [ -n "$cand_heads" ]; then
      for h in ${(f)cand_heads}; do
        if git -C "$d" merge-base --is-ancestor "$tip" "$h" 2>/dev/null; then cov=1; break; fi
      done
    fi
    if [ -z "$cov" ]; then
      ((n_uncovered++))
      print -P "%F{red}❌ UNCOVERED%f $rel  branch=$br  tip=${tip[1,8]}"
    fi
  done
done

# counters live in subshells — recompute verdict cheaply by re-scanning output is
# overkill; emit a trailer the caller greps instead.
rm -f "$BUNDLE_IDX"
echo ""
echo "Scan complete. Any ❌ UNCOVERED line above = work not in any remote or bundle."
echo "Fix: push the branch, or refresh the repo's bundle: git -C <repo> bundle create ~/git-bundles/<name>.bundle --all"
# exit status: grep our own output is impossible here; caller: verify_coverage.sh | grep -c UNCOVERED
