#!/bin/zsh
###############################################################################
# 🧪 try-uv.sh — opt-in trial subshell for the uv-only branch (OLD machine)
#
# Opens ONE interactive zsh whose config is the uv-only worktree's zshrc,
# via a throwaway ZDOTDIR. The live ~/.zshrc (pyenv-wired master) is not
# touched anywhere else; `exit` returns you to the normal setup. Nothing
# persists except ~/.venv-sandbox if you run `mysandbox` inside.
#
# Usage:  ./try-uv.sh [path-to-worktree]   (default: ../../dotfiles-uv-worktree
#                                           relative to this script)
###############################################################################
set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
WORKTREE="${1:-$(cd "$SCRIPT_DIR/../.." && pwd)/dotfiles-uv-worktree}"

if [ ! -f "$WORKTREE/shell/zshrc" ]; then
  echo "❌ No uv-only worktree at: $WORKTREE"
  echo "   Create it: git -C ~/Code/000-config/001-dotfiles worktree add ../dotfiles-uv-worktree uv-only"
  exit 1
fi

zsh -n "$WORKTREE/shell/zshrc" || { echo "❌ zshrc syntax error — fix before trying"; exit 1; }

TRIAL_HOME=$(mktemp -d /tmp/try-uv.XXXXXX)
cat > "$TRIAL_HOME/.zshenv" <<EOF
# trial shell — uv-only branch
source "$WORKTREE/shell/zshenv" 2>/dev/null || true
EOF
cat > "$TRIAL_HOME/.zprofile" <<EOF
source "$WORKTREE/shell/zprofile"
# On this Intel machine the pyenv uv shim may shadow brew uv — prefer brew's.
export PATH="\$(brew --prefix 2>/dev/null)/bin:\$PATH"
EOF
cat > "$TRIAL_HOME/.zshrc" <<EOF
export TRY_UV=1
source "$WORKTREE/shell/zshrc"
print -P "%F{yellow}🧪 try-uv trial shell — uv-only config from:%f $WORKTREE"
print -P "%F{yellow}   exit → back to the normal (pyenv) setup. Nothing persisted.%f"
EOF

echo "🧪 Entering uv-only trial shell (ZDOTDIR=$TRIAL_HOME)..."
ZDOTDIR="$TRIAL_HOME" zsh -i
rm -rf "$TRIAL_HOME"
echo "✅ Trial shell closed — live config untouched."
