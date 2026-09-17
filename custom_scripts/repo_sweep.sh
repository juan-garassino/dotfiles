#!/bin/zsh
###############################################################################
# 🔍 repo_sweep.sh — the reclone-readiness gate (MIGRATION.md Phase 0.1)
#
# Scans every git repo under ~/Code and reports anything that would LOSE WORK
# on a clean-rebuild reclone: dirty working trees, unpushed commits, repos
# with no remote. Read-only; exit 1 if anything needs attention.
#
# Usage: repo_sweep.sh [root=~/Code]           # safety gate (reclone-readiness)
#        repo_sweep.sh --branches [root]       # deep-clean audit: branch sprawl
#
# Allowlist: repos whose ROOT-relative path is listed (exact match, one per
# line, '#' comments ok) in  $ROOT/.sweepignore  or  ~/.sweepignore  are
# skipped in BOTH modes — for by-design no-remote scratch and vestigial
# never-committed git-init shells that are not real repos.
#
# Persist convention: this prints to stdout only; capture with
#   repo_sweep.sh | tee ~/env-snapshots/repo-sweep-$(date +%F).txt
###############################################################################
set -u
MODE=gate
if [ "${1:-}" = "--branches" ]; then MODE=branches; shift; fi
ROOT="${1:-$HOME/Code}"

# --- allowlist: exact ROOT-relative paths to skip -----------------------------
typeset -a IGNORE
for f in "$ROOT/.sweepignore" "$HOME/.sweepignore"; do
  [ -f "$f" ] || continue
  while IFS= read -r line; do
    line="${line%%#*}"; line="${line## }"; line="${line%% }"
    [ -n "$line" ] && IGNORE+=("$line")
  done < "$f"
done
_ignored() { (( ${IGNORE[(Ie)$1]} )) }   # zsh: exact-match index, 0 if absent

if [ "$MODE" = "branches" ]; then
  # CLEANLINESS layer: list repos with branch sprawl — local branches besides
  # main/master, flagged [unmerged] (not in main) and [local-only] (no upstream).
  echo "🌿 Branch audit under $ROOT (repos with >1 local branch)..."
  find "$ROOT" -name .git -maxdepth 6 \( -type d -o -type f \) \
      -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sort | while IFS= read -r g; do
    d="${g:h}"
    _ignored "${d#$ROOT/}" && continue
    main=$(git -C "$d" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|origin/||')
    main=${main:-$(git -C "$d" branch -l main master --format='%(refname:short)' 2>/dev/null | head -1)}
    branches=$(git -C "$d" branch --format='%(refname:short)' 2>/dev/null)
    n=$(echo "$branches" | grep -c . )
    [ "$n" -le 1 ] && continue
    print -P "%F{cyan}${d#$ROOT/}%f  (default: ${main:-?})"
    echo "$branches" | while IFS= read -r b; do
      [ "$b" = "$main" ] && continue
      flags=""
      if [ -n "$main" ] && ! git -C "$d" merge-base --is-ancestor "$b" "$main" 2>/dev/null; then
        flags+=" [unmerged]"
      fi
      git -C "$d" rev-parse --abbrev-ref "$b@{upstream}" >/dev/null 2>&1 || flags+=" [local-only]"
      echo "    - $b$flags"
    done
  done
  echo ""
  echo "Recipes: merge → git checkout \$main && git merge <b> && git push && git branch -d <b>"
  echo "         keep  → git push -u origin <b>       drop → git branch -D <b>"
  exit 0
fi

typeset -i n_repos=0 n_bad=0
echo "🔍 Sweeping git repos under $ROOT ..."

find "$ROOT" -name .git -maxdepth 6 \( -type d -o -type f \) \
    -not -path '*/node_modules/*' -not -path '*/.venv/*' 2>/dev/null | sort | while IFS= read -r g; do
  d="${g:h}"
  _ignored "${d#$ROOT/}" && continue
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
  _ignored "${d#$ROOT/}" && continue
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
