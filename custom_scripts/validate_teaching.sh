#!/bin/zsh
###############################################################################
# 🎓 validate_teaching.sh — build + smoke + tear down all 4 teaching stacks
#
#   validate_teaching.sh [stack ...]     # default: spiced lewagon-ds lewagon-da lewagon-de
#
# Per stack: compose build → up -d → smoke → down. One stack at a time (heavy
# builds; Docker Desktop on Intel has wedged under parallel build pressure).
# Emits: STACK|<name>|<status>|<build-secs>|<note>
# Smoke: Jupyter /api reachable + core DS imports (jupyter stacks); pg_isready
# for the DE stack's Postgres. amd64 builds are throwaway (M5 rebuilds arm64) —
# the point is proving the DEFINITIONS build and run.
###############################################################################
set -u
TC="$HOME/Code/004-lewagon-spiced/teaching-containers"
STACKS=("${@:-spiced}" ); [ $# -eq 0 ] && STACKS=(spiced lewagon-ds lewagon-da lewagon-de)
res(){ echo "STACK|$1|$2|$3|$4"; }

for s in "${STACKS[@]}"; do
  f="$TC/$s/docker-compose.yml"
  [ -f "$f" ] || { res "$s" SKIP 0 "no docker-compose.yml"; continue; }
  t0=$SECONDS
  if ! docker compose -f "$f" build >"/tmp/teach-$s.build" 2>&1; then
    res "$s" BUILD-FAIL $((SECONDS-t0)) "see /tmp/teach-$s.build"; continue
  fi
  tb=$((SECONDS-t0))
  if ! docker compose -f "$f" up -d >"/tmp/teach-$s.up" 2>&1; then
    res "$s" UP-FAIL $tb "see /tmp/teach-$s.up"; docker compose -f "$f" down >/dev/null 2>&1; continue
  fi
  sleep 25   # healthcheck start period
  note=""
  ok=1
  svcs=$(docker compose -f "$f" config --services 2>/dev/null)
  main=$(echo "$svcs" | head -1)
  # jupyter smoke (any service publishing container port 8888)
  jport=""
  for sv in ${(f)svcs}; do
    p=$(docker compose -f "$f" port "$sv" 8888 2>/dev/null | awk -F: 'NF{print $NF}' | head -1)
    [ -n "$p" ] && { jport="$p"; main="$sv"; break; }
  done
  if [ -n "$jport" ]; then
    if curl -sf -m 10 "http://localhost:$jport/api" >/dev/null 2>&1; then note="jupyter:$jport OK; "
    else ok=0; note="jupyter:$jport UNREACHABLE; "; fi
    # per-stack import contract — each track ships a DIFFERENT env by design
    case "$s" in
      lewagon-ds) imports="pandas, numpy, sklearn, matplotlib, tensorflow" ;;
      lewagon-da) imports="numpy, pandas, matplotlib, seaborn, plotly" ;;
      lewagon-de) imports="pandas, sqlalchemy, psycopg2" ;;
      spiced)     imports="pandas, numpy, sklearn, matplotlib, notebook" ;;
      *)          imports="pandas, numpy" ;;
    esac
    if docker compose -f "$f" exec -T "$main" python -c "import $imports" >/dev/null 2>&1; then
      note="${note}imports($imports) OK"
    else ok=0; note="${note}imports FAILED"; fi
  fi
  # postgres smoke (DE stack or any db service)
  dbsvc=$(echo "$svcs" | grep -E 'postgres|db' | head -1)
  if [ -n "$dbsvc" ]; then
    if docker compose -f "$f" exec -T "$dbsvc" pg_isready >/dev/null 2>&1; then
      note="${note}${note:+; }pg_isready OK"
    else ok=0; note="${note}${note:+; }pg_isready FAILED"; fi
  fi
  # bare dev-box fallback (no jupyter, no db): prove python runs
  if [ -z "$jport" ] && [ -z "$dbsvc" ]; then
    if docker compose -f "$f" exec -T "$main" python -V >/dev/null 2>&1 \
       || docker compose -f "$f" exec -T "$main" python3 -V >/dev/null 2>&1; then
      note="python runs in $main"
    else ok=0; note="no smoke handle in $main"; fi
  fi
  docker compose -f "$f" down >/dev/null 2>&1
  res "$s" "$([ $ok -eq 1 ] && echo PASS || echo SMOKE-FAIL)" $tb "$note"
done
