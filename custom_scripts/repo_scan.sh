#!/bin/zsh
# repo_scan.sh — scan ~/Code structure and emit JSON
#
# Usage: ./repo_scan.sh [dir]
#   dir defaults to ~/Code
#
# Structure assumed:
#   ~/Code/
#     <container>/          ← direct child, no .git → groups projects
#       <project>/          ← direct child of container → always reported
#         .git?             ← if present: full git status
#                           ← if absent:  flagged as "needs-git-init"
#
# Skips: node_modules, .venv, venv, .web, hidden dirs (dot-prefixed)
# Output: JSON array to stdout

set -euo pipefail

CODE_DIR="${1:-${HOME}/Code}"

SKIP_DIRS=(node_modules .venv venv .web dist build __pycache__)

is_skip() {
  local name="$1"
  for s in "${SKIP_DIRS[@]}"; do
    [ "$name" = "$s" ] && return 0
  done
  [[ "$name" == .* ]] && return 0
  return 1
}

if [ ! -d "$CODE_DIR" ]; then
  echo "[]"
  exit 0
fi

echo "["
first=true

for container in "$CODE_DIR"/*/; do
  [ -d "$container" ] || continue
  container_name=$(basename "$container")
  is_skip "$container_name" && continue

  for project in "$container"*/; do
    [ -d "$project" ] || continue
    project="${project%/}"
    project_name=$(basename "$project")
    is_skip "$project_name" && continue

    rel="${project#$CODE_DIR/}"

    if [ -d "$project/.git" ]; then

      branch=$(git -C "$project" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

      remote_url=$(git -C "$project" remote get-url origin 2>/dev/null || echo "")
      [ -z "$remote_url" ] && remote_url="no-remote"

      dirty=$(git -C "$project" status --porcelain 2>/dev/null)
      [ -n "$dirty" ] && repo_status="dirty" || repo_status="clean"

      staged=$(git -C "$project" diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
      unstaged=$(git -C "$project" diff --name-only 2>/dev/null | wc -l | tr -d ' ')
      untracked=$(git -C "$project" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

      sync="no-remote"
      ahead=0
      behind=0
      if [ "$remote_url" != "no-remote" ]; then
        git -C "$project" fetch --quiet origin "$branch" 2>/dev/null || true
        ahead=$(git -C "$project" rev-list --count "origin/${branch}..HEAD" 2>/dev/null || echo 0)
        behind=$(git -C "$project" rev-list --count "HEAD..origin/${branch}" 2>/dev/null || echo 0)

        if   [ "$ahead" = "0" ] && [ "$behind" = "0" ]; then sync="up-to-date"
        elif [ "$ahead" != "0" ] && [ "$behind" = "0" ]; then sync="ahead:${ahead}"
        elif [ "$ahead" = "0" ] && [ "$behind" != "0" ]; then sync="behind:${behind}"
        else sync="diverged"
        fi
      fi

      last_commit=$(git -C "$project" log -1 --format="%ar|%s" 2>/dev/null || echo "?|?")
      last_when="${last_commit%%|*}"
      last_msg="${last_commit#*|}"
      last_msg="${last_msg//\"/\\\"}"

      [ "$first" = true ] && first=false || echo ","
      printf '  {\n'
      printf '    "container": "%s",\n'       "$container_name"
      printf '    "path": "%s",\n'            "$rel"
      printf '    "name": "%s",\n'            "$project_name"
      printf '    "kind": "git",\n'
      printf '    "branch": "%s",\n'          "$branch"
      printf '    "status": "%s",\n'          "$repo_status"
      printf '    "staged": %s,\n'            "$staged"
      printf '    "unstaged": %s,\n'          "$unstaged"
      printf '    "untracked": %s,\n'         "$untracked"
      printf '    "remote": "%s",\n'          "$remote_url"
      printf '    "sync": "%s",\n'            "$sync"
      printf '    "ahead": %s,\n'             "$ahead"
      printf '    "behind": %s,\n'            "$behind"
      printf '    "last_commit_ago": "%s",\n' "$last_when"
      printf '    "last_commit_msg": "%s"\n'  "$last_msg"
      printf '  }'

    else
      # no .git at top level — check if nested deeper (mono-repo / miscategorised)
      nested_git=$(find "$project" -maxdepth 3 -name ".git" -type d 2>/dev/null | head -1)
      [ -n "$nested_git" ] && nested_note="nested .git at: ${nested_git#$project/}" || nested_note=""

      [ "$first" = true ] && first=false || echo ","
      printf '  {\n'
      printf '    "container": "%s",\n'   "$container_name"
      printf '    "path": "%s",\n'        "$rel"
      printf '    "name": "%s",\n'        "$project_name"
      printf '    "kind": "no-git",\n'
      printf '    "status": "needs-git-init",\n'
      printf '    "sync": "no-remote",\n'
      printf '    "branch": "",\n'
      printf '    "remote": "no-remote",\n'
      printf '    "staged": 0,\n'
      printf '    "unstaged": 0,\n'
      printf '    "untracked": 0,\n'
      printf '    "ahead": 0,\n'
      printf '    "behind": 0,\n'
      printf '    "last_commit_ago": "",\n'
      printf '    "last_commit_msg": "",\n'
      printf '    "note": "%s"\n'         "$nested_note"
      printf '  }'
    fi

  done
done

echo ""
echo "]"