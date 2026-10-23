#!/usr/bin/env bash
# backup_env.sh — refresh tracked env snapshots, secret-scan the STAGED diff, commit & push.
# Part of Juan's environment-replication kit. The remote is a PUBLIC fork of lewagon/dotfiles
# (it cannot be made private), so everything this script stages is published. Safe-by-default:
# ABORTS BEFORE COMMITTING if any secret is detected in what would be committed.
#
#   Usage: backup_env.sh [--no-push]
#
# What's already live via symlinks (no copy needed): zshrc, zshenv, aliases, gitconfig,
# p10k.zsh, claude/statusline-command.sh. This script refreshes the things that are
# snapshots rather than symlinks (claude/settings.json, Warp settings, the allow-listed
# Claude skills + agents), stages explicit paths (never `git add -A`), scans the staged
# diff (gitleaks via Docker when available, always the regex below), then commits & pushes.
# Secrets are NEVER captured — they live in ~/.secrets (chmod 600, outside any repo).

set -euo pipefail

# The checkout this script lives in (live symlinks may point at a worktree).
REPO="${DOTFILES_REPO:-$(cd "$(dirname "$0")/.." && pwd)}"
CLAUDE_SETTINGS="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
SKILLS_ALLOW="$REPO/claude/skills.public"       # one skill dir name per line; ONLY these are published
CANON_HOME="/Users/juan-garassino"              # canonical home in the snapshot; install.sh rewrites it
PUSH=1
[ "${1:-}" = "--no-push" ] && PUSH=0

cd "$REPO"
say() { printf '\033[1m%s\033[0m\n' "$*"; }

say "🍺 Checking Brewfile drift (report-only)..."
# The Brewfile is hand-curated (leaves only, commented) — never `brew bundle dump` over it.
if command -v brew >/dev/null 2>&1; then
  drift="$(brew bundle cleanup --file="$REPO/packages/Brewfile" 2>/dev/null | grep -vE '^Would|^Run' || true)"
  if [ -n "$drift" ]; then
    echo "  ⚠️  installed but not in Brewfile (add by hand if wanted):"; printf '%s\n' "$drift" | sed 's/^/       /'
  else
    echo "  ✅ Brewfile matches installed leaves"
  fi
else
  echo "  ⏭️  brew not found — skipping"
fi

say "🤖 Re-sanitizing Claude settings snapshot (whitelisted keys only)..."
if [ -f "$CLAUDE_SETTINGS" ] && command -v jq >/dev/null 2>&1; then
  mkdir -p "$REPO/claude"
  # Whitelist, never blacklist: `permissions` (allow/deny/ask carry repo names, paths and secret
  # names), `autoMode` (infra recon) and anything unknown are DROPPED. `env` keeps only names that
  # are Claude Code switches and never look like a credential.
  jq '{theme, statusLine, hooks, enabledPlugins, model, modelSettings, effortLevel,
       autoMemoryEnabled, verbose, agentPushNotifEnabled, switchModelsOnFlag,
       skipWorkflowUsageWarning, skipAutoPermissionPrompt,
       env: ((.env // {}) | with_entries(
               select((.key | test("^(MCP_TIMEOUT|CLAUDE_CODE_[A-Z0-9_]+|DISABLE_[A-Z0-9_]+|BASH_[A-Z0-9_]+)$"))
                      and ((.key | test("KEY|TOKEN|SECRET|PASS|AUTH")) | not))))}
      | with_entries(select(.value != null))' \
     "$CLAUDE_SETTINGS" | sed "s#$HOME#$CANON_HOME#g" > "$REPO/claude/settings.json"
  echo "  ✅ claude/settings.json refreshed ($(jq -r 'keys | join(", ")' "$REPO/claude/settings.json"))"
else
  echo "  ⚠️  settings.json or jq missing — skipping"
fi

say "🖥️  Refreshing Warp settings snapshot..."
for f in "$HOME/.warp/settings.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/warp-terminal/settings.toml"; do
  [ -f "$f" ] && { mkdir -p "$REPO/terminal"; sed "s#$HOME#__HOME__#g" "$f" > "$REPO/terminal/warp-settings.toml"; echo "  ✅ from $f"; break; }
done

say "🧩 Refreshing Claude skills (allow-list) + agents snapshot..."
if command -v rsync >/dev/null 2>&1 && [ -d "$CLAUDE_HOME/skills" ]; then
  if [ ! -f "$SKILLS_ALLOW" ]; then
    echo "  ❌ $SKILLS_ALLOW missing — nothing copied. List the skills that may be PUBLISHED, one per line."
    exit 1
  fi
  mkdir -p "$REPO/claude/skills"
  n=0
  while IFS= read -r skill; do
    case "$skill" in ''|'#'*) continue;; esac
    case "$skill" in */*|.*) echo "  ⚠️  bad entry '$skill' (plain dir name only) — skipped"; continue;; esac
    if [ -d "$CLAUDE_HOME/skills/$skill" ]; then
      rsync -a --delete --exclude '.DS_Store' "$CLAUDE_HOME/skills/$skill/" "$REPO/claude/skills/$skill/"; n=$((n+1))
    else
      echo "  ⚠️  listed skill '$skill' not found in $CLAUDE_HOME/skills — left as tracked"
    fi
  done < "$SKILLS_ALLOW"
  # Opt-in: anything local but unlisted is reported, never copied (new private skills stay private).
  unlisted="$(for d in "$CLAUDE_HOME"/skills/*/; do b="$(basename "$d")"; grep -qx "$b" "$SKILLS_ALLOW" || echo "$b"; done)"
  [ -n "$unlisted" ] && { echo "  ℹ️  local skills NOT published (add to claude/skills.public to publish):"; printf '%s\n' "$unlisted" | sed 's/^/       /'; }
  echo "  ✅ $n allow-listed skills synced"
  if [ -d "$CLAUDE_HOME/agents" ]; then
    rsync -a --delete --exclude '.DS_Store' "$CLAUDE_HOME/agents/" "$REPO/claude/agents/"
    echo "  ✅ agents synced"
  fi
fi

say "📦 Staging (explicit paths — never git add -A)..."
# Tracked files that changed (live symlink targets, docs, scripts) + the snapshot dirs this script owns.
git add -u -- .
git add -A -- claude/skills claude/agents packages/Brewfile claude/settings.json terminal 2>/dev/null || true
untracked="$(git ls-files -o --exclude-standard)"
[ -n "$untracked" ] && { echo "  ℹ️  untracked files NOT staged (git add them yourself if they belong here):"; printf '%s\n' "$untracked" | sed 's/^/       /'; }
if git diff --cached --quiet; then
  echo "  ℹ️  nothing to commit"
  exit 0
fi

say "🔎 Secret scan of the STAGED diff (aborts before commit on any hit)..."
# Match secret *values* (not keyword names) so the scanner doesn't flag itself or docs. Modern formats:
# Anthropic sk-ant-, OpenAI sk-proj-/legacy sk-, OpenRouter sk-or-v1-, GitHub fine-grained github_pat_ and
# classic ghp_/gho_/ghu_/ghs_/ghr_, NVIDIA nvapi-, Groq gsk_, Perplexity pplx-, HuggingFace hf_, Replicate r8_,
# AWS AKIA, Slack xox*, Google AIza, PEM private keys, GCP service-account JSON, Azure OpenAI assignments.
PATTERN='sk-ant-[A-Za-z0-9_-]{20,}|sk-proj-[A-Za-z0-9_-]{20,}|sk-or-v1-[0-9a-f]{20,}|sk-[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9]{20,}|nvapi-[A-Za-z0-9_-]{20,}|gsk_[A-Za-z0-9]{20,}|pplx-[A-Za-z0-9]{20,}|hf_[A-Za-z0-9]{20,}|r8_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[0-9A-Za-z_-]{30,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|"private_key"|AZURE_OPENAI_API_KEY[ "]*=[ "]*[A-Za-z0-9]{20,}'
abort() {
  echo "  ❌ SECRET DETECTED — nothing committed. Unstaging."
  git reset -q
  echo "  Move the key into ~/.secrets (sourced by zshrc), remove it from the file, rotate it if it was ever pushed, then re-run."
  exit 1
}
# 1) Regex over ADDED lines only (file:line, value redacted) — runs always.
hits="$(git diff --cached -U0 --no-color --diff-filter=ACMR -- . ':!custom_scripts/backup_env.sh' \
  | awk -v pat="$PATTERN" '
      /^\+\+\+ / { f=substr($0,7); next }
      /^@@/ { split($3,a,","); n=substr(a[1],2)+0; next }
      /^\+/ { if ($0 ~ pat) printf "%s:%d\n", f, n; n++ }' || true)"
if [ -n "$hits" ]; then
  echo "  regex hits (file:line):"; printf '%s\n' "$hits" | sed 's/^/       /'
  abort
fi
echo "  ✅ regex: no secrets in the staged diff"
# 2) gitleaks on the staged changes, via Docker, read-only mount — when Docker is up and this is a plain checkout.
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && [ -d "$REPO/.git" ]; then
  GL="ghcr.io/gitleaks/gitleaks:latest"
  gl_out="$(docker run --rm -v "$REPO:/repo:ro" -w /repo \
      -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' \
      "$GL" git --staged --redact --no-banner --exit-code 9 /repo 2>&1)" && gl_rc=0 || gl_rc=$?
  if [ "$gl_rc" = 9 ]; then
    echo "  gitleaks findings:"; printf '%s\n' "$gl_out" | sed 's/^/       /'; abort
  elif [ "$gl_rc" = 0 ]; then
    echo "  ✅ gitleaks: no leaks in the staged diff"
  else
    echo "  ⚠️  gitleaks could not run (rc=$gl_rc: image pull / old CLI?) — regex result stands"
    printf '%s\n' "$gl_out" | tail -3 | sed 's/^/       /'
  fi
else
  echo "  ⏭️  Docker not available (or worktree checkout) — regex result stands"
fi

say "📦 Committing..."
ts="$(date '+%Y-%m-%d %H:%M')"
git commit -q -m "env backup: refresh dotfiles + claude config ($ts)"
echo "  ✅ committed $(git rev-parse --short HEAD)"

if [ "$PUSH" = 1 ]; then
  say "🚀 Pushing..."
  git push -q && echo "  ✅ pushed to $(git remote get-url origin)" || { echo "  ⚠️  push failed"; exit 1; }
else
  say "⏭️  --no-push: committed locally, not pushed."
fi

say "✅ Environment backed up."
