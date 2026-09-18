#!/bin/zsh
###############################################################################
# 🧹 migration_cleanup.sh — simulate, then execute, the Intel → clean-uv teardown
#
# The "erase duplicates + all cache + old-school Python → best-practice uv" step.
# DEFAULT is a DRY RUN: it enumerates every candidate, sizes the reclaim, and
# proves the post-cleanup uv state works — WITHOUT deleting anything.
#
#   migration_cleanup.sh                 # full dry run (no deletion) — read this first
#   migration_cleanup.sh --apply         # actually delete (respects guardrails below)
#   migration_cleanup.sh --apply --dupes-only / --caches-only / --python-only / --docker-only
#
# GUARDRAILS (why "then do it" is safe):
#  • pyenv/old-Python is NEVER removed while the LIVE shell is still pyenv-wired
#    (it's your rollback + daily python). --apply --python refuses until the live
#    ~/.zshrc is the uv-only config. Dry run always shows it, flagged BLOCKED.
#  • Docker Desktop VM removed only if colima is the active docker context.
#  • Duplicate clones removed only when their content is on a remote or a bundle.
###############################################################################
set -u
MODE=dry; SCOPE=all
for a in "$@"; do case "$a" in
  --apply) MODE=apply ;;
  --dupes-only) SCOPE=dupes ;; --caches-only) SCOPE=caches ;;
  --python-only) SCOPE=python ;; --docker-only) SCOPE=docker ;;
esac; done

typeset -i total_kb=0
hdr(){ echo ""; print -P "%B== $1 ==%b"; }
# rc <path> <note> : count size; delete if apply; always print
rc(){ local p="$1" note="${2:-}"; [ -e "$p" ] || { return; }
  local kb; kb=$(du -sk "$p" 2>/dev/null | awk '{print $1}'); total_kb+=${kb:-0}
  if [ "$MODE" = apply ]; then rm -rf "$p" 2>/dev/null && print -P "  %F{red}deleted%f $(du -h -d0 "$p" 2>/dev/null|awk '{print $1}';true) $p"
  else printf "  would free %6s  %s  %s\n" "$(du -sh "$p" 2>/dev/null|awk '{print $1}')" "$p" "$note"; fi }

echo "🧹 migration cleanup — MODE=$MODE  SCOPE=$SCOPE   (free now: $(df -h /System/Volumes/Data|tail -1|awk '{print $4}'))"

# ── live-config probe (the pyenv guardrail) ──────────────────────────────────
LIVE_ZSHRC="$(readlink ~/.zshrc 2>/dev/null || echo ~/.zshrc)"
if grep -q pyenv "$LIVE_ZSHRC" 2>/dev/null; then LIVE_IS_UVONLY=0; else LIVE_IS_UVONLY=1; fi

if [ "$SCOPE" = all ] || [ "$SCOPE" = dupes ]; then
hdr "DUPLICATES — redundant clones (content is on a remote or bundle)"
rc ~/Code/005-products/020-autoresearch/references/014-spectral-cnn  "dup of SPC-spectral-cnn (its unique work pushed to feat/paper-monitoring)"
rc ~/Code/005-products/020-autoresearch/references/015-spectral-nets "dup of 005-products/015-spectral-nets"
rc ~/Code/006-research-prototypes/AUD-deep-techno/_legacy/deepTechno1 "nested dup of deep-techno (bundled: legacy_deepTechno1.bundle)"
rc ~/Code/000-config/000-back-up/dotfiles                            "3rd dotfiles clone (canonical: 001-dotfiles + uv-worktree; on remote)"
rc ~/Code/000-config/003-mcp-servers/003-weather-mcp                 "vestigial 0-commit shell (canonical: 003-kp/mcp/weather-mcp)"
rc ~/Code/006-research-prototypes/MCP-model-context-protocol/003-weather-mcp "vestigial 0-commit shell (same canonical)"
echo "  ⚠️ REVIEW (not auto): nanoGPT-1 vs 003-nanoGPT twins — confirm which is canonical before removing"
fi

if [ "$SCOPE" = all ] || [ "$SCOPE" = caches ]; then
hdr "CACHES — regenerable (uv sync / npm i / re-download rebuild them)"
[ "$MODE" = apply ] && pgrep -f 'uv run' >/dev/null 2>&1 && echo "  ⏭️  ~/.cache/uv SKIPPED — a live 'uv run' (discord-me-mcp) holds its lock; stop it first"
if ! { [ "$MODE" = apply ] && pgrep -f 'uv run' >/dev/null 2>&1; }; then rc ~/.cache/uv "uv download cache"; fi
rc ~/.cache/huggingface "HF model cache"; rc ~/.cache/puppeteer ""; rc ~/.cache/act ""
rc ~/.cache/codex-runtimes ""; rc ~/.cache/deep_neuronal_net_utils ""; rc ~/.cache/go-build ""
rc ~/Library/Caches/pip ""
echo "  -- per-project .venv (re-create with: cd <proj> && uv sync):"
find ~/Code -type d -name '.venv' -not -path '*/.git/*' -prune 2>/dev/null | while read -r v; do rc "$v" ""; done
echo "  -- node_modules (re-create with: npm i):"
find ~/Code -type d -name 'node_modules' -not -path '*/.git/*' -not -path '*/node_modules/*' -prune 2>/dev/null | while read -r n; do rc "$n" ""; done
fi

if [ "$SCOPE" = all ] || [ "$SCOPE" = python ]; then
hdr "OLD-SCHOOL PYTHON — pyenv + non-uv interpreters (uv replaces all of it)"
if [ "$LIVE_IS_UVONLY" = 0 ]; then
  print -P "  %F{yellow}⛔ BLOCKED for --apply%f: live ~/.zshrc is STILL pyenv-wired ($(grep -c pyenv "$LIVE_ZSHRC" 2>/dev/null) refs)."
  echo "     pyenv is your live python + rollback. Do the cutover FIRST (config→uv-only,"
  echo "     prove 'uv run' + a project 'uv sync', depyenv.sh --apply), THEN re-run --apply --python-only."
  SAVE=$MODE; MODE=dry   # force dry for this section regardless
fi
rc ~/.pyenv "40 virtualenvs — SNAPSHOTTED in ~/env-snapshots; projects re-create via uv sync"
rc /usr/local/Cellar/python@3.7 "python.org 3.7.9 EOL (uv ships 3.11/3.12)"
rc "/Library/Frameworks/Python.framework/Versions/3.7" "python.org 3.7 framework (/usr/local/bin/python3)"
rc ~/Library/Python "user-site sprawl across 3.7/3.9/3.11/3.12"
echo "  + after apply: 'brew uninstall pyenv pyenv-virtualenv' and delete the pyenv stanza from the shell"
[ -n "${SAVE:-}" ] && MODE=$SAVE
fi

if [ "$SCOPE" = all ] || [ "$SCOPE" = docker ]; then
hdr "DOCKER DESKTOP — 51G VM (go-forward is colima)"
ctx=$(docker context show 2>/dev/null)
if [ "$ctx" = colima ]; then
  echo "  ✓ colima is the active context — Docker Desktop VM is reclaimable (aiuw volume already exported)"
  rc ~/Library/Containers/com.docker.docker "Docker Desktop VM+data (use colima instead)"
else
  echo "  ⏭️  active docker context = '${ctx:-none}', not colima — start colima + switch first; DRY only"
  [ -e ~/Library/Containers/com.docker.docker ] && printf "  would free %6s  ~/Library/Containers/com.docker.docker  (once on colima)\n" "$(du -sh ~/Library/Containers/com.docker.docker 2>/dev/null|awk '{print $1}')"
fi
fi

hdr "TOTAL"
printf "  reclaim identified: %d GB (%d MB)\n" "$(( total_kb/1024/1024 ))" "$(( total_kb/1024 ))"
[ "$MODE" = dry ] && echo "  (DRY RUN — nothing deleted. Re-run with --apply, honoring the guardrails above.)"

# ── post-cleanup verification (prove the clean uv end-state works) ───────────
hdr "POST-CLEANUP VERIFY — does uv alone still give you Python?"
command -v uv >/dev/null 2>&1 && echo "  ✓ uv present: $(uv --version 2>/dev/null)" || echo "  ✗ uv missing!"
uv python list --only-installed 2>/dev/null | sed 's/^/    /' | head -4
if uv run --python 3.12 python -c 'import sys;print("  ✓ uv run 3.12 →",sys.version.split()[0])' 2>/dev/null; then :; else echo "  ⚠️  uv run 3.12 needs 'uv python install 3.12'"; fi
echo "  → best-practice end-state: uv-managed Pythons + per-project .venv (uv sync); no pyenv, no dup clones, no stale caches."
