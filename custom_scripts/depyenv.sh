#!/bin/zsh
###############################################################################
# 🧹 depyenv.sh — one-time pyenv retirement helper (OLD machine only)
#
# Phase A  Snapshot: pip-freeze every pyenv env → ~/env-snapshots/<env>.txt
#          (read-only insurance before the machine is retired).
# Phase B  Sweep ~/Code .python-version files that name pyenv virtualenvs:
#            - tracked in a repo NOT owned by Juan (pull-only upstream, e.g.
#              Le Wagon taxifare-env)      → LEAVE, report only
#            - untracked, or tracked in a Juan-owned repo → prompt:
#              [d]elete / [r]eplace with the env's base Python version / [s]kip
#
# SAFETY: --dry-run is the DEFAULT. Phase B never modifies tracked files in
# non-owned repos, never runs git add/commit, and asks per file. The current
# pyenv-based autoenv depends on these files — do NOT --apply until migration
# week (per MIGRATION.md).
#
# Usage:
#   ./depyenv.sh                  # Phase A + Phase B report (no changes)
#   ./depyenv.sh --apply          # Phase B interactive fixes (migration week)
#   ./depyenv.sh --force-snapshots  # re-freeze even if snapshot exists
###############################################################################
set -u

APPLY=false
FORCE_SNAPSHOTS=false
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=true ;;
    --dry-run) APPLY=false ;;
    --force-snapshots) FORCE_SNAPSHOTS=true ;;
    *) echo "Usage: depyenv.sh [--dry-run|--apply] [--force-snapshots]"; exit 1 ;;
  esac
done

SNAP_DIR="$HOME/env-snapshots"
REPORT="$SNAP_DIR/depyenv-report.txt"
PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
mkdir -p "$SNAP_DIR"

echo "🧹 depyenv — mode: $([ "$APPLY" = true ] && echo APPLY || echo DRY-RUN)"

###############################################################################
# Phase A — snapshots (read-only toward everything except ~/env-snapshots)
###############################################################################
echo ""
echo "📸 Phase A — pip-freeze snapshots → $SNAP_DIR"
if [ ! -d "$PYENV_ROOT/versions" ]; then
  echo "  ℹ️  No pyenv at $PYENV_ROOT — skipping Phase A."
else
  ls "$PYENV_ROOT/versions" > "$SNAP_DIR/_pyenv-versions.txt"
  # Envs live at versions/<base>/envs/<name>; symlinks at versions/<name>.
  # Iterate the real env dirs to avoid freezing each env twice.
  for envpath in "$PYENV_ROOT"/versions/*/envs/*(N/); do
    envname="${envpath:t}"
    out="$SNAP_DIR/$envname.txt"
    if [ -f "$out" ] && [ "$FORCE_SNAPSHOTS" = false ]; then
      echo "  ✅ $envname (snapshot exists)"
      continue
    fi
    if "$envpath/bin/python" -m pip freeze > "$out" 2>/dev/null; then
      echo "  📄 $envname → $(wc -l < "$out" | tr -d ' ') packages"
    else
      echo "  ⚠️  $envname — freeze failed (broken env?)"
    fi
  done
fi

###############################################################################
# Phase B — .python-version sweep
###############################################################################
echo ""
echo "🔍 Phase B — sweeping ~/Code for .python-version files..."
: > "$REPORT"
echo "# depyenv report — $(date '+%Y-%m-%d %H:%M')" >> "$REPORT"
echo "# path | content | class | tracked | owned | action" >> "$REPORT"

typeset -i n_ok=0 n_left=0 n_fixed=0 n_todo=0

find "$HOME/Code" -name .python-version -type f \
    -not -path '*/.venv/*' -not -path '*/node_modules/*' -not -path '*/site-packages/*' \
    2>/dev/null | sort | while IFS= read -r f; do
  dir="${f:h}"
  content=""
  content=$(tr -d '[:space:]' < "$f")

  # Plain version strings are uv-compatible — nothing to do.
  if [[ "$content" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    echo "$f | $content | version | - | - | OK" >> "$REPORT"
    ((n_ok++)); continue
  fi

  # Env-name content — classify ownership.
  tracked=no; owned=no
  if git -C "$dir" ls-files --error-unmatch .python-version >/dev/null 2>&1; then
    tracked=yes
    origin=""
    origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    [[ "$origin" == *github.com*juan-garassino* || "$origin" == *github.com*engenious* ]] && owned=yes
    [ -z "$origin" ] && owned=yes   # tracked but no remote → local-only repo, Juan's
  fi

  if [ "$tracked" = yes ] && [ "$owned" = no ]; then
    echo "$f | $content | envname | yes | no | LEAVE (upstream)" >> "$REPORT"
    ((n_left++)); continue
  fi

  # Fixable (untracked, or in a Juan-owned repo)
  if [ "$APPLY" = false ]; then
    echo "$f | $content | envname | $tracked | $owned | TODO (run --apply)" >> "$REPORT"
    ((n_todo++)); continue
  fi

  # Resolve the env's base Python version for the [r]eplace option
  base=""
  cfg="$PYENV_ROOT/versions/$content/pyvenv.cfg"
  [ -f "$cfg" ] && base=$(awk -F' *= *' '$1=="version"||$1=="version_info"{print $2; exit}' "$cfg" | cut -d. -f1-2)
  echo ""
  echo "  ⚙️  $f  (env '$content'${base:+, base $base})"
  echo -n "     [d]elete / [r]eplace with ${base:-3.12} / [s]kip ? "
  # non-interactive runs (no usable tty): DEPYENV_ANSWER=d|r|s answers every prompt
  if [ -n "${DEPYENV_ANSWER:-}" ]; then
    choice="$DEPYENV_ANSWER"; echo "$choice (auto)"
  else
    read -r choice < /dev/tty 2>/dev/null || { choice=s; echo "s (no tty)"; }
  fi
  case "$choice" in
    d|D) rm "$f";                    echo "$f | $content | envname | $tracked | $owned | DELETED" >> "$REPORT"; ((n_fixed++)) ;;
    r|R) echo "${base:-3.12}" > "$f"; echo "$f | $content | envname | $tracked | $owned | REPLACED ${base:-3.12}" >> "$REPORT"; ((n_fixed++)) ;;
    *)                               echo "$f | $content | envname | $tracked | $owned | SKIPPED" >> "$REPORT" ;;
  esac
done

echo ""
echo "📋 Report → $REPORT"
grep -c "| OK$" "$REPORT" 2>/dev/null | xargs -I{} echo "  ✅ plain-version (fine): {}"
grep -c "LEAVE" "$REPORT" 2>/dev/null | xargs -I{} echo "  ⏸  upstream, left alone: {}"
grep -c "TODO" "$REPORT" 2>/dev/null | xargs -I{} echo "  📝 fixable (needs --apply): {}"
grep -cE "DELETED|REPLACED" "$REPORT" 2>/dev/null | xargs -I{} echo "  🔧 fixed this run: {}"
echo ""
echo "Done. Re-runnable anytime; fixed files reclassify as plain-version."
