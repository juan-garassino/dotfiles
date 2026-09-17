#!/bin/zsh
###############################################################################
# 🎒 stage_handcarry.sh — the hand-carry list as executable truth
#
# The single source of the MIGRATION.md Phase-1 hand-carry inventory.
#   --check (default): verify every item exists, print sizes + total.
#   --to <dir>       : rsync everything onto the target (plugged SSD),
#                      preserving home-relative structure under <dir>/handcarry/.
#
# NEVER routes through any git repo. Secrets stay chmod 600 at the target.
###############################################################################
set -u
MODE=check; TARGET=""
if [ "${1:-}" = "--to" ]; then MODE=copy; TARGET="${2:?usage: stage_handcarry.sh --to /Volumes/<SSD>}"; fi

# item format: "path|required|note"  (paths home-relative)
ITEMS=(
  ".secrets|req|API keys env file"
  ".secrets-cheatsheet.md|req|repo→keys→source map"
  ".ssh/id_ed25519_personal|req|personal key"
  ".ssh/id_ed25519_personal.pub|req|"
  ".ssh/id_ed25519_work|req|work key"
  ".ssh/id_ed25519_work.pub|req|"
  ".ssh/google_compute_engine|opt|GCE key"
  ".ssh/google_compute_engine.pub|opt|"
  ".ssh/dc_trader|opt|legacy key"
  ".ssh/known_hosts|opt|host trust"
  "Code/000-config/002-gcp-credentials|req|GCP app-cred JSONs (NEVER to a repo)"
  ".claude|req|projects memory/standing/plans — irreplaceable (~1.3G)"
  ".config/gcloud|req|gcloud auth"
  ".aws|req|work aws"
  ".azure|req|work azure"
  "env-snapshots|req|manifests, pgdump, vscode-ext, scorecards"
  "Library/Application Support/Claude/claude_desktop_config.json|opt|Claude Desktop MCPs"
  # loose non-git dirs (verified 2026-09-17 — git-status ground truth)
  "Code/006-research-prototypes/OTH-candidate-assistant|req|loose src 306M"
  "Code/006-research-prototypes/GRAPH-graphrag-integration|req|loose src 82M"
  "Code/006-research-prototypes/GRAPH-custom-graphrag|req|loose src 33M"
  "Code/006-research-prototypes/GRAPH-chroma-rag|opt|loose src"
  "Code/006-research-prototypes/DIF-emoji-generation|opt|loose notebooks 116M"
  "Code/006-research-prototypes/DIF-adversarial-diffusion|opt|loose notebooks 64M"
  "Code/006-research-prototypes/OTH-orchestration-coreo|opt|loose src 58M"
  "Code/006-research-prototypes/AGT-multiagent-orchestrator|opt|loose src"
  "Code/006-research-prototypes/SQL-nlsql|opt|loose src"
  "Code/005-products/001-assessment|opt|loose src 9M"
  "Code/004-lewagon-spiced/spiced/ds-book-template|req|local-only commit on neuefische origin (also bundled)"
  "git-bundles|req|26+ verified bundles incl. engenious no-remote repos"
)

typeset -i missing=0
total_kb=0
echo "🎒 Hand-carry ${MODE} ($([ $MODE = copy ] && echo "→ $TARGET" || echo 'existence+size')):"
for it in "${ITEMS[@]}"; do
  p="${it%%|*}"; rest="${it#*|}"; req="${rest%%|*}"; note="${rest#*|}"
  src="$HOME/$p"
  if [ -e "$src" ]; then
    kb=$(du -sk "$src" 2>/dev/null | awk '{print $1}')
    total_kb=$((total_kb + ${kb:-0}))
    printf "  ✅ %-70s %8s  %s\n" "$p" "$(du -sh "$src" 2>/dev/null | awk '{print $1}')" "$note"
    if [ "$MODE" = copy ]; then
      dest="$TARGET/handcarry/$p"
      mkdir -p "${dest:h}"
      rsync -a "$src" "${dest:h}/" || echo "     ⚠️ rsync failed for $p"
    fi
  else
    if [ "$req" = req ]; then printf "  ❌ MISSING (required) %s\n" "$p"; ((missing++))
    else printf "  ⚪ absent (optional) %s\n" "$p"; fi
  fi
done
echo ""
echo "Total payload: $(( total_kb / 1024 / 1024 )) GB ($(( total_kb / 1024 )) MB)"
if [ "$MODE" = copy ]; then
  chmod 600 "$TARGET/handcarry/.secrets" "$TARGET/handcarry/.secrets-cheatsheet.md" 2>/dev/null
  echo "Staged under $TARGET/handcarry/ (secrets chmod 600)."
fi
[ "$missing" -eq 0 ] && { echo "✅ all required items present"; exit 0; } || { echo "❌ $missing required item(s) missing"; exit 1; }
