#!/usr/bin/env bash
# bootstrap.sh — git, clone, claude. The only command a fresh machine needs:
#
#   curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh | bash
#
# Installs git + curl + zsh + perl (+ openssh-server on Linux), clones this repo to its canonical
# path, installs Claude Code (native installer), then opens Claude in the repo with the setup
# prompt pre-filled. Claude takes it from there (CLAUDE.md / MIGRATE.md) and stops
# only for passwords, logins and secrets. Safe to re-run.
#
#   DOTFILES_BRANCH=<branch|tag>   what to check out (default main). A tag is checked out
#                                  detached (tags can't be `pull --ff-only`ed); a branch is
#                                  fast-forwarded. Works for a fresh clone and a re-run.
set -eu
BRANCH="${DOTFILES_BRANCH:-main}"
DEST="$HOME/Code/000-config/001-dotfiles"
REPO="${DOTFILES_REPO:-https://github.com/juan-garassino/dotfiles}"
SUDO="sudo"; [ "$(id -u)" = 0 ] && SUDO=""

echo "🛠️  bootstrap — git, clone, claude"
case "$(uname)" in
  Linux)
    # zsh: install.sh is #!/bin/zsh (without it: "bad interpreter").
    # perl: the migration's code_manifest.pl needs Digest::SHA — debian/ubuntu images only ship perl-base.
    if command -v apt-get >/dev/null 2>&1; then
      $SUDO apt-get update -y && DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y git curl zsh perl openssh-server
    elif command -v dnf >/dev/null 2>&1; then
      $SUDO dnf install -y git curl zsh perl openssh-server
    else
      echo "⚠️  no apt/dnf — install git, curl, zsh, perl and openssh-server yourself, then re-run"
    fi ;;
  Darwin)
    xcode-select -p >/dev/null 2>&1 || { xcode-select --install; echo "Finish the Xcode CLT install, then re-run."; exit 1; } ;;
esac

# --- clone / update the dotfiles at $BRANCH (branch or tag) -------------------------------
if [ -d "$DEST/.git" ]; then
  if git -C "$DEST" fetch -q --tags --force origin; then
    if git -C "$DEST" show-ref -q --verify "refs/remotes/origin/$BRANCH"; then
      # a branch: switch to it (track origin) and fast-forward only
      git -C "$DEST" checkout -q "$BRANCH" 2>/dev/null || git -C "$DEST" checkout -q -b "$BRANCH" "origin/$BRANCH"
      git -C "$DEST" pull -q --ff-only origin "$BRANCH" || echo "⚠️  $BRANCH could not be fast-forwarded (local commits?) — left as is"
    elif git -C "$DEST" show-ref -q --verify "refs/tags/$BRANCH"; then
      # a tag: detached checkout — nothing to pull
      git -C "$DEST" checkout -q --detach "refs/tags/$BRANCH"
      echo "📌 dotfiles at tag $BRANCH (detached HEAD)"
    else
      echo "⚠️  '$BRANCH' is neither a branch nor a tag on origin — staying on $(git -C "$DEST" rev-parse --abbrev-ref HEAD)"
    fi
  else
    echo "⚠️  git fetch failed (offline?) — using the dotfiles already in $DEST"
  fi
else
  mkdir -p "$(dirname "$DEST")"
  # `git clone -b` accepts a tag too (→ detached HEAD) — one path for both
  git clone -b "$BRANCH" "$REPO" "$DEST"
fi
echo "📂 dotfiles: $(git -C "$DEST" describe --tags --always 2>/dev/null) ($(git -C "$DEST" rev-parse --abbrev-ref HEAD 2>/dev/null))"

# --- Claude Code ------------------------------------------------------------------------------
if ! command -v claude >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/claude" ]; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
export PATH="$HOME/.local/bin:$PATH"

PROMPT="Read CLAUDE.md and README.md in this repo. Then ask me (one question) whether this is (a) a fresh setup of an empty machine or (b) a migration from another machine (Mac or Linux), and run the matching runbook end to end: (a) the 'Full machine setup' checklist in CLAUDE.md, (b) MIGRATE.md. Verify each step and stop only for passwords, logins and secrets."

cd "$DEST"
echo "🤖 Starting Claude Code (log in when asked)..."
# stdin is this piped script — hand Claude the real terminal
exec claude "$PROMPT" < /dev/tty
