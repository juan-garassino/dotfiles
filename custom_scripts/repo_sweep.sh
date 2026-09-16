#!/bin/zsh
###############################################################################
# 🔍 repo_sweep.sh — the reclone-readiness gate (MIGRATION.md Phase 0.1)
#
# Scans every git repo under ~/Code and reports anything that would LOSE WORK
# on a clean-rebuild reclone: dirty working trees, unpushed commits, repos
# with no remote. Read-only; exit 1 if anything needs attention.
#
# Usage: repo_sweep.sh [root=~/Code]
###############################################################################
set -u
ROOT="${1:-$HOME/Code}"

typeset -i n_repos=0 n_bad=0
echo "🔍 Sweeping git repos under $ROOT ..."

find "$ROOT" -name .git -maxdepth 6 \( -type d -o -type f \) \
    -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sort | while IFS= read -r g; do
  d="${g:h}"
  ((n_repos++))
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  ahead=$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | wc -l | tr -d ' ')
  remote=$(git -C "$d" remote 2>/dev/null | head -1)
  if [ "$dirty" != "0" ] || [ "$ahead" != "0" ] || [ -z "$remote" ]; then
    ((n_bad++))
    flags=""
    [ "$dirty" != "0" ] && flags+=" dirty=$dirty"
    [ "$ahead" != "0" ] && flags+=" unpushed=$ahead"
    [ -z "$remote" ]    && flags+=" NO-REMOTE"
    print -P "%F{yellow}⚠️  ${d#$ROOT/}%f —$flags"
  fi
done

# counters live in the pipeline subshell — recompute the verdict cheaply
bad=$(find "$ROOT" -name .git -maxdepth 6 \( -type d -o -type f \) \
        -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | while IFS= read -r g; do
  d="${g:h}"
  [ -n "$(git -C "$d" status --porcelain 2>/dev/null | head -1)" ] && { echo x; continue; }
  [ -n "$(git -C "$d" log --branches --not --remotes --oneline 2>/dev/null | head -1)" ] && { echo x; continue; }
  [ -z "$(git -C "$d" remote 2>/dev/null | head -1)" ] && echo x
done | wc -l | tr -d ' ')

echo ""
if [ "$bad" = "0" ]; then
  print -P "%F{green}✅ RECLONE-READY — every repo committed, pushed, and remoted.%f"
  exit 0
else
  print -P "%F{yellow}❌ $bad repo(s) need attention before a clean-rebuild migration.%f"
  exit 1
fi
