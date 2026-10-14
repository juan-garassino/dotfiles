#!/usr/bin/env bash
# bootstrap.sh — git, clone, claude. The only command a fresh machine needs:
#
#   curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh | bash
#
# Installs git + curl (+ openssh-server on Linux), clones this repo to its canonical path,
# installs Claude Code (native installer), then opens Claude in the repo with the setup
# prompt pre-filled. Claude takes it from there (CLAUDE.md / MIGRATE.md) and stops
# only for passwords, logins and secrets. Safe to re-run.
set -eu
BRANCH="${DOTFILES_BRANCH:-main}"
DEST="$HOME/Code/000-config/001-dotfiles"
REPO="https://github.com/juan-garassino/dotfiles"

echo "🛠️  bootstrap — git, clone, claude"
case "$(uname)" in
  Linux)
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y git curl openssh-server
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y git curl openssh-server
    fi ;;
  Darwin)
    xcode-select -p >/dev/null 2>&1 || { xcode-select --install; echo "Finish the Xcode CLT install, then re-run."; exit 1; } ;;
esac

if [ -d "$DEST/.git" ]; then
  git -C "$DEST" fetch -q origin && git -C "$DEST" checkout -q "$BRANCH" && git -C "$DEST" pull -q --ff-only || true
else
  mkdir -p "$(dirname "$DEST")" && git clone -b "$BRANCH" "$REPO" "$DEST"
fi

if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
export PATH="$HOME/.local/bin:$PATH"

PROMPT="Read CLAUDE.md and README.md in this repo. Then ask me (one question) whether this is (a) a fresh setup of an empty machine or (b) a migration from another machine (Mac or Linux), and run the matching runbook end to end: (a) the 'Full machine setup' checklist in CLAUDE.md, (b) MIGRATE.md. Verify each step and stop only for passwords, logins and secrets."

cd "$DEST"
echo "🤖 Starting Claude Code (log in when asked)..."
# stdin is this piped script — hand Claude the real terminal
exec claude "$PROMPT" < /dev/tty
