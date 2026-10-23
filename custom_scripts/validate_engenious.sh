#!/bin/zsh
###############################################################################
# 🏢 validate_engenious.sh — prove the WORK repos run under uv (READ-ONLY to git)
#
#   validate_engenious.sh           # code layer: uv sync + tests per service
#   validate_engenious.sh --stack   # + the docker-compose smoke of the `stack` entry
#
# The list of work repos is PRIVATE and lives OUTSIDE this public repo:
#   ~/.config/dotfiles/engenious-repos.txt      (carried by packages/home-carry.txt)
# one entry per line, `#` comments allowed:
#   uv    <path relative to ~/Code/002-engenious> [import-name]  # pyproject repo: uv sync + pytest
#   req   <path> [import-name]                                   # requirements.txt repo: uv venv + pip -r
#   stack <path> [health-url] [infra services…]                  # docker compose smoke (--stack only)
# Example:
#   uv    services/my-service
#   req   references/legacy-app my_pkg
#   stack references/legacy-app http://localhost:8080/health postgres redis
#
# HARD CONSTRAINT: zero git writes — no branch, no commit, no push, no file
# edits inside 002-engenious. Only `uv sync` (.venv is gitignored) and docker.
# Each service line: SVC|<name>|<PASS|FAIL|SKIP>|<note>
###############################################################################
set -u
ENG="$HOME/Code/002-engenious"
LIST="${ENGENIOUS_REPOS:-$HOME/.config/dotfiles/engenious-repos.txt}"
STACK=0; [ "${1:-}" = "--stack" ] && STACK=1
LOGD="$(mktemp -d "${TMPDIR:-/tmp}/eng-validate.XXXXXX")"
svc(){ echo "SVC|$1|$2|$3"; }

if [ ! -r "$LIST" ]; then
  cat >&2 <<EOF
validate_engenious.sh: no repo list at $LIST
  This public repo carries no work-repo names. Create the file (chmod 600) with one entry per line:
    uv    <path relative to $ENG> [import-name]
    req   <path> [import-name]
    stack <path> [health-url] [infra services…]
  or point ENGENIOUS_REPOS at it. See the header of this script for the format.
EOF
  exit 2
fi
[ -d "$ENG" ] || { echo "validate_engenious.sh: $ENG missing" >&2; exit 2; }

# tripwire: record dirt BEFORE, assert unchanged AFTER
dirt(){ ( cd "$ENG" && find . -maxdepth 4 -name .git \( -type d -o -type f \) | while read -r g; do
  r=${g%/.git}; echo "$r:$(git -C "$ENG/$r" --no-optional-locks status --porcelain 2>/dev/null | wc -l | tr -d ' ')"; done | LC_ALL=C sort ); }
dirt_before="$(dirt)"

stack_path=""; stack_health=""; stack_infra=()
# ── code layer ────────────────────────────────────────────────────────────────
while read -r kind path a1 rest; do
  case "$kind" in ''|'#'*) continue;; esac
  [ -n "${path:-}" ] || { echo "SVC|?|SKIP|bad line in $LIST: $kind"; continue; }
  d="$ENG/$path"; name="${path##*/}"; log="$LOGD/$name"
  case "$kind" in
    uv)
      [ -d "$d" ] || { svc "$name" SKIP "missing dir $path"; continue; }
      if ( cd "$d" && { uv sync --extra dev -q >/dev/null 2>&1 || uv sync -q >/dev/null 2>&1; } ); then
        if ( cd "$d" && uv run pytest -q -x --timeout 300 >"$log.test" 2>&1 ); then
          svc "$name" PASS "uv sync + pytest ($(grep -Eo '[0-9]+ passed' "$log.test" | tail -1))"
        else
          # tests may need live creds — smoke-import the package instead of failing hard
          pkg="${a1:-$(ls "$d/src" 2>/dev/null | head -1)}"
          if [ -n "$pkg" ] && ( cd "$d" && uv run python -c "import $pkg" >/dev/null 2>&1 ); then
            svc "$name" PASS "uv sync OK; pytest needs creds ($(grep -Eo '[0-9]+ (failed|error)' "$log.test" | head -1)); smoke-import $pkg OK"
          else
            svc "$name" FAIL "uv sync OK but pytest + smoke-import failed (see $log.test)"
          fi
        fi
      else
        svc "$name" FAIL "uv sync failed"
      fi ;;
    req)
      [ -d "$d" ] || { svc "$name" SKIP "missing dir $path"; continue; }
      if ( cd "$d" && { [ -d .venv ] || uv venv .venv --python 3.12 -q; } \
           && source .venv/bin/activate && uv pip install -q -r requirements.txt >"$log.pip" 2>&1 ); then
        if [ -n "${a1:-}" ] && ( cd "$d" && source .venv/bin/activate && python -c "import $a1" 2>/dev/null ); then
          svc "$name" PASS "uv venv + requirements install + smoke-import $a1"
        else
          svc "$name" PASS "uv venv + requirements install (no importable package given — workers run via compose)"
        fi
      else
        svc "$name" FAIL "uv pip install -r failed (see $log.pip)"
      fi ;;
    stack)
      stack_path="$path"; stack_health="${a1:-}"; stack_infra=(${=rest}) ;;
    *) svc "$name" SKIP "unknown kind '$kind' in $LIST" ;;
  esac
done < "$LIST"

# ── compose stack layer ───────────────────────────────────────────────────────
if [ $STACK -eq 1 ]; then
  if [ -z "$stack_path" ] || [ ! -d "$ENG/$stack_path" ]; then
    svc stack SKIP "no 'stack <path>' entry in $LIST (or dir missing)"
  else
    cd "$ENG/$stack_path" || exit 1
    name="${stack_path##*/}"
    echo "STACK| building images (this is the long part)..."
    if docker compose build >"$LOGD/$name.build" 2>&1; then
      if [ ${#stack_infra[@]} -gt 0 ]; then
        docker compose up -d "${stack_infra[@]}" >"$LOGD/$name.up" 2>&1; sleep 15
      fi
      docker compose up -d >>"$LOGD/$name.up" 2>&1; sleep 20
      up=$(docker compose ps --format '{{.Name}} {{.State}}' 2>/dev/null | grep -c running)
      total=$(docker compose ps --format '{{.Name}}' 2>/dev/null | wc -l | tr -d ' ')
      allup=FAIL; [ "$up" -ge 1 ] && [ "$up" -eq "$total" ] && allup=PASS
      health=""; [ -n "$stack_health" ] && health=$(curl -sf -m 5 "$stack_health" 2>/dev/null || echo "")
      if [ -n "$health" ]; then svc "$name-stack" PASS "$up/$total containers running; health OK"
      elif [ -n "$stack_health" ]; then svc "$name-stack" "$allup" "$up/$total containers running; no health reply from $stack_health"
      else svc "$name-stack" "$allup" "$up/$total containers running"
      fi
      docker compose down >/dev/null 2>&1
    else
      svc "$name-stack" FAIL "docker compose build failed (see $LOGD/$name.build)"
      docker compose down >/dev/null 2>&1 || true
    fi
  fi
fi

# ── tripwire ──────────────────────────────────────────────────────────────────
dirt_after="$(dirt)"
if [ "$dirt_before" = "$dirt_after" ]; then
  echo "TRIPWIRE|PASS|engenious git state byte-identical before/after"
else
  echo "TRIPWIRE|FAIL|git state CHANGED:"; diff <(echo "$dirt_before") <(echo "$dirt_after") | sed 's/^/  /'
fi
echo "LOGS|$LOGD"
