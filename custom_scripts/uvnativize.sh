#!/bin/zsh
###############################################################################
# 📦 uvnativize.sh — convert ONE owned repo to uv-native (pyproject.toml + uv.lock)
#
#   uvnativize.sh <repo-path>            # auto: requirements / poetry / lock-only
#   uvnativize.sh <repo-path> --finish   # pyproject already written (setup.py lift
#                                        #   done by hand/agent) → lock+commit+push
#   uvnativize.sh <repo-path> --no-push  # commit locally, skip push (e.g. no remote)
#
# Emits ONE machine-readable line:  RESULT|<repo>|<type>|<status>|<note>
#   status: PASS (pyproject+lock committed+pushed) · PASS-NOLOCK (pyproject committed,
#   lock unresolvable — hand-fix) · NEEDS-HAND (setup.py lift required) · SKIP · FAIL
#
# HARD GUARDS: aborts on 002-engenious (WORK — zero writes ever), 001-archives,
# official-content (upstream Le Wagon), sandbox reference clones.
# Commits ONLY the manifest files it created — never pre-existing dirt.
###############################################################################
set -u
REPO="${1:?usage: uvnativize.sh <repo-path> [--finish|--no-push]}"
FINISH=0; PUSH=1
for a in "${@:2}"; do case "$a" in --finish) FINISH=1;; --no-push) PUSH=0;; esac; done

res(){ echo "RESULT|$REPO|$1|$2|$3"; exit "${4:-0}"; }

RP=$(cd "$REPO" 2>/dev/null && pwd -P) || res "?" SKIP "path does not exist"
case "$RP" in
  */002-engenious/*|*/002-engenious) res "?" SKIP "ENGENIOUS — work repo, hard-excluded" 2 ;;
  */001-archives/*)                  res "?" SKIP "archives — read-only" ;;
  */official-content/*)              res "?" SKIP "upstream Le Wagon — pull-only" ;;
  */007-sandbox/CopilotKit*|*/007-sandbox/001-OmniParser*) res "?" SKIP "reference clone" ;;
esac
cd "$RP" || res "?" FAIL "cd failed"
[ -e .git ] || res "?" SKIP "not a git repo root"

# ── classify ─────────────────────────────────────────────────────────────────
TYPE=none
if [ -f pyproject.toml ]; then
  if grep -q '^\[tool\.poetry\]' pyproject.toml; then TYPE=poetry
  elif grep -q '^\[project\]' pyproject.toml; then TYPE=pep621
  else TYPE=pyproject-other; fi
elif [ -f requirements.txt ]; then TYPE=req
elif [ -f setup.py ]; then TYPE=setuppy
fi
[ $FINISH -eq 1 ] && { [ -f pyproject.toml ] || res "$TYPE" FAIL "--finish but no pyproject.toml"; TYPE=finish; }

# python version: plain .python-version hint, else 3.12 (floor 3.10)
PYV=$(grep -Eo '^[0-9]+\.[0-9]+' .python-version 2>/dev/null | head -1)
case "$PYV" in ""|3.[0-9]) PYV=3.12 ;; 3.10|3.11|3.12|3.13) ;; *) PYV=3.12 ;; esac

# ── convert ──────────────────────────────────────────────────────────────────
NOTE=""
case "$TYPE" in
  none|pyproject-other) res "$TYPE" SKIP "no convertible manifest" ;;
  setuppy) res "$TYPE" NEEDS-HAND "lift setup.py → pyproject, then re-run with --finish" ;;
  pep621|finish)
    : ;;  # manifest already right — just lock below
  poetry)
    uvx migrate-to-uv >/dev/null 2>&1 || res "$TYPE" FAIL "uvx migrate-to-uv errored"
    NOTE="migrated from poetry; " ;;
  req)
    if [ ! -f pyproject.toml ]; then
      NAME=$(basename "$RP" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/^[0-9-]*//')
      [ -n "$NAME" ] || NAME=project
      DEPS=$(grep -vE '^\s*(#|$|-r|-e|--)' requirements.txt | grep -vE '^git\+' \
             | sed 's/[[:space:]]*#.*$//; s/[[:space:]]*$//' | awk 'NF{printf "  \"%s\",\n", $0}')
      SKIPPED=$(grep -cE '^(git\+|-e)' requirements.txt 2>/dev/null | tr -d ' ')
      [ "${SKIPPED:-0}" -gt 0 ] && NOTE="${SKIPPED} git+/-e line(s) not migrated; "
      cat > pyproject.toml <<PYEOF
[project]
name = "$NAME"
version = "0.1.0"
requires-python = ">=$PYV"
dependencies = [
$DEPS]

[tool.uv]
package = false
PYEOF
    fi ;;
esac

# ── lock + sync (the proof the manifest resolves) ────────────────────────────
LOCKED=1
uv lock -q >/dev/null 2>&1 || LOCKED=0
if [ $LOCKED -eq 1 ]; then
  uv sync -q >/dev/null 2>&1 || NOTE="${NOTE}lock OK but sync failed (env not built); "
else
  NOTE="${NOTE}uv lock unresolvable — committing pyproject WITHOUT lock; "
  rm -f uv.lock
fi

# ── gitignore hygiene (never commit the env) ─────────────────────────────────
grep -qE '(^|/)\.venv' .gitignore 2>/dev/null || { echo ".venv/" >> .gitignore; }

# ── branch + surgical commit + push ──────────────────────────────────────────
CUR=$(git branch --show-current 2>/dev/null); [ -n "$CUR" ] || CUR=main
git switch -q build/uv-native 2>/dev/null || git switch -qc build/uv-native || res "$TYPE" FAIL "cannot create branch"
git add pyproject.toml .gitignore 2>/dev/null
[ -f uv.lock ] && git add uv.lock
# drop requirements.txt only when converted AND nothing references it
if [ "$TYPE" = req ] && [ $LOCKED -eq 1 ]; then
  typeset -a refs; refs=( Dockerfile*(N) docker-compose*(N) compose*(N) Makefile(N) .github(N) .gitlab-ci.yml(N) )
  if (( ${#refs} )) && grep -rqs "requirements" "${refs[@]}" 2>/dev/null; then
    NOTE="${NOTE}requirements.txt kept (referenced by build/CI); "
  else
    git rm -q --cached requirements.txt 2>/dev/null && rm -f requirements.txt && NOTE="${NOTE}requirements.txt removed; "
  fi
fi
if git diff --cached --quiet; then
  git switch -q "$CUR"
  res "$TYPE" PASS "already uv-native — nothing to commit"
fi
git commit -qm "build(uv): adopt pyproject.toml + uv.lock" || { git switch -q "$CUR"; res "$TYPE" FAIL "commit failed"; }
PUSHED="local-only"
if [ $PUSH -eq 1 ] && git remote get-url origin >/dev/null 2>&1; then
  git push -qu origin build/uv-native >/dev/null 2>&1 && PUSHED="pushed" || PUSHED="PUSH-FAILED"
fi
git switch -q "$CUR"
[ $LOCKED -eq 1 ] && res "$TYPE" PASS "${NOTE}${PUSHED}" || res "$TYPE" PASS-NOLOCK "${NOTE}${PUSHED}"
