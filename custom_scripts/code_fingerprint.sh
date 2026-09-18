#!/bin/zsh
###############################################################################
# 🧬 code_fingerprint.sh — machine-independent fingerprint of every repo's state
#
#   code_fingerprint.sh > ~/env-snapshots/fingerprint-<machine>.txt
#   diff fingerprint-intel.txt fingerprint-m5.txt      # MUST be empty
#
# One line per repo:  <relpath>|<branch>|<HEAD sha>|<clean|dirty:N>
# Git's content-addressing means equal SHAs = byte-identical trees, so an
# empty diff between two machines' fingerprints IS the "byte-the-same working
# sets" proof (for everything that is a git repo; the vault covers the rest).
# Excludes upstream Le Wagon mirrors and third-party reference clones.
###############################################################################
set -u
CODE="${CODE_ROOT:-$HOME/Code}"
find "$CODE" -maxdepth 5 -name .git \( -type d -o -type f \) 2>/dev/null | sort | while read -r g; do
  r="${g%/.git}"
  case "$r" in
    */official-content/*|*/007-sandbox/CopilotKit*|*/007-sandbox/001-OmniParser*|*/node_modules/*|*/.venv/*) continue ;;
  esac
  cd "$r" 2>/dev/null || continue
  br=$(git branch --show-current 2>/dev/null); [ -n "$br" ] || br="DETACHED"
  sha=$(git rev-parse --short=12 HEAD 2>/dev/null || echo "-")
  n=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$n" -eq 0 ] && st="clean" || st="dirty:$n"
  printf '%s|%s|%s|%s\n' "${r#$CODE/}" "$br" "$sha" "$st"
done
