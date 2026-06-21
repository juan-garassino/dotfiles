#!/usr/bin/env bash
# backup_env.sh — refresh tracked env snapshots, secret-scan, commit & push the dotfiles repo.
# Part of Juan's environment-replication kit. Safe-by-default: ABORTS if any secret is detected.
#
#   Usage: backup_env.sh [--no-push]
#
# What's already live via symlinks (no copy needed): zshrc, zshenv, aliases, gitconfig,
# p10k.zsh, claude/statusline-command.sh. This script refreshes the things that are
# snapshots rather than symlinks (Brewfile, claude/settings.json), then commits & pushes.
# Secrets are NEVER captured — they live in ~/.secrets (chmod 600, outside any repo).

set -euo pipefail

REPO="$HOME/Code/000-config/001-dotfiles"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

cd "$REPO"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

say "🍺 Refreshing Brewfile..."
if command -v brew >/dev/null 2>&1; then
  brew bundle dump --file="$REPO/Brewfile" --force >/dev/null 2>&1 && echo "  ✅ Brewfile updated"
else
  echo "  ⚠️  brew not found — skipping"
fi

say "🤖 Re-sanitizing Claude settings snapshot..."
if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p "$REPO/claude"
  jq '(.permissions.allow) |= map(select((test("AZURE_OPENAI_API_KEY|sk-[A-Za-z0-9]{20}|AKIA|ghp_|/Users/")) | not))' \
     "$CLAUDE_SETTINGS" > "$REPO/claude/settings.json"
  echo "  ✅ claude/settings.json refreshed (secrets + personal-path allow entries stripped)"
else
  echo "  ⚠️  settings.json or jq missing — skipping"
fi

say "🧩 Refreshing Claude skills/agents snapshot..."
if command -v rsync >/dev/null 2>&1; then
  rsync -a --delete --exclude '.DS_Store' ~/.claude/skills/  "$REPO/claude/skills/"  2>/dev/null
  rsync -a --delete --exclude '.DS_Store' ~/.claude/agents/ "$REPO/claude/agents/" 2>/dev/null
  echo "  ✅ skills/agents synced"
fi

say "🔎 Secret scan (high-signal, aborts on any hit)..."
# Match secret *values* (not keyword names) so the scanner doesn't flag itself or docs.
PATTERN='sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"private_key"|AZURE_OPENAI_API_KEY[ "]*=[ "]*[A-Za-z0-9]{20,}'
hits="$(git ls-files -com --exclude-standard | while IFS= read -r f; do
  case "$f" in custom_scripts/backup_env.sh|*.png|*.jpg|*.jpeg|*.gif|*.pdf|*.lock|*.ico) continue;; esac
  [ -f "$f" ] && grep -IlE "$PATTERN" "$f" 2>/dev/null || true
done)"
if [ -n "$hits" ]; then
  echo "  ❌ SECRET DETECTED in:"; printf '%s\n' "$hits" | sed 's/^/       /'
  echo "  Move the key into ~/.secrets (and source it from zshrc), remove it from the file, then re-run."
  exit 1
fi
echo "  ✅ no secrets found"

say "📦 Committing..."
git add -A
if git diff --cached --quiet; then
  echo "  ℹ️  nothing to commit"
else
  ts="$(date '+%Y-%m-%d %H:%M')"
  git commit -q -m "env backup: refresh dotfiles + claude config + Brewfile ($ts)"
  echo "  ✅ committed"
fi

if [ "$PUSH" = 1 ]; then
  say "🚀 Pushing..."
  git push -q && echo "  ✅ pushed to $(git remote get-url origin)" || { echo "  ⚠️  push failed"; exit 1; }
else
  say "⏭️  --no-push: staged & committed locally, not pushed."
fi

say "✅ Environment backed up."
