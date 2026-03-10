#!/bin/zsh

###############################################################################
# 🔀 git_setup.sh — per-project git identity helper
# Run inside any new repo to verify or override git identity.
# Does NOT touch global config — respects your includeIf setup.
###############################################################################

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║        🔀  Git Project Setup                     ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# Must be inside a git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Not inside a git repository. Run this from inside a repo."
  exit 1
fi

###############################################################################
# Show current resolved identity
###############################################################################
echo "📋 Current resolved identity for this repo:"
echo "  📁 Directory : $(pwd)"
echo "  👤 Name      : $(git config user.name)"
echo "  📧 Email     : $(git config user.email)"
echo "  🔑 SSH key   : $(git config core.sshCommand 2>/dev/null || echo '<default>')"
echo ""

# Show which config file is providing the email
echo "📂 Config source:"
git config --show-origin user.email
echo ""

###############################################################################
# Ask if override is needed
###############################################################################
echo -n "Override identity for this repo only? [y/N] "
read -r override

if [[ "$override" =~ ^[Yy]$ ]]; then
  echo -n "Name: "
  read -r custom_name
  echo -n "Email: "
  read -r custom_email

  git config user.name "$custom_name"
  git config user.email "$custom_email"

  echo ""
  echo "✅ Local identity set:"
  echo "  👤 $custom_name"
  echo "  📧 $custom_email"
  echo "  (stored in .git/config — does not affect global config)"
else
  echo "↩️  Keeping resolved identity."
fi

###############################################################################
# Remote info
###############################################################################
echo ""
echo "🌐 Remote:"
git remote -v 2>/dev/null || echo "  No remotes configured yet."

echo ""
echo "✅ Done."
