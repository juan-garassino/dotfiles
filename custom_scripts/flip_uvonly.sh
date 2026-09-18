#!/bin/zsh
###############################################################################
# 🔀 flip_uvonly.sh — reversibly flip the LIVE shell between main (pyenv) and
#                     uv-only, by re-pointing the home-dir symlinks.
#
#   flip_uvonly.sh --status      # show where every managed link points (default)
#   flip_uvonly.sh --to-uvonly   # point live config at dotfiles-uv-worktree
#   flip_uvonly.sh --rollback    # restore the exact pre-cutover targets
#
# Mechanism: the live dotfiles are symlinks into a repo checkout. The cutover is
# just re-pointing them — no repo mutation, no file copies. Rollback restores the
# targets recorded at first flip (snapshot: ~/env-snapshots/live-symlinks-pre-cutover.txt).
# ssh/config is deliberately NOT managed here (flipped separately if ever needed).
###############################################################################
set -u
UV="$HOME/Code/000-config/dotfiles-uv-worktree"
SNAP="$HOME/env-snapshots/live-symlinks-pre-cutover.txt"
MODE="${1:---status}"

# src-relative-to-repo : live link target
typeset -a PAIRS=(
  "shell/zshrc:$HOME/.zshrc"
  "shell/zshenv:$HOME/.zshenv"
  "shell/zprofile:$HOME/.zprofile"
  "shell/aliases:$HOME/.aliases"
  "prompt/p10k.zsh:$HOME/.p10k.zsh"
  "git/gitconfig:$HOME/.gitconfig"
  "git/gitconfig-personal:$HOME/.gitconfig-personal"
  "git/gitconfig-work:$HOME/.gitconfig-work"
  "direnv/direnvrc:$HOME/.config/direnv/direnvrc"
)

current_target(){ readlink "$1" 2>/dev/null || { [ -e "$1" ] && echo "REGULAR-FILE" || echo "MISSING"; } }

status(){
  print -P "%B🔀 live dotfile links%b"
  local uv=0 other=0 dst tgt
  for pair in "${PAIRS[@]}"; do
    dst="${pair#*:}"; tgt=$(current_target "$dst")
    case "$tgt" in
      "$UV"/*) print -P "  %F{green}uv-only%f  ${dst/#$HOME/~} → ${tgt/#$HOME/~}"; ((++uv)) ;;
      MISSING) print -P "  %F{244}missing%f  ${dst/#$HOME/~}"; ((++other)) ;;
      *)       print -P "  %F{yellow}other  %f  ${dst/#$HOME/~} → ${tgt/#$HOME/~}"; ((++other)) ;;
    esac
  done
  if [ $other -eq 0 ]; then print -P "%B→ LIVE = uv-only%b"
  elif [ $uv -eq 0 ]; then print -P "%B→ LIVE = main/other (not flipped)%b"
  else print -P "%B→ LIVE = MIXED (⚠ finish the flip or rollback)%b"; fi
}

flip(){
  # snapshot the ORIGINAL targets once — rollback always restores the first-ever state
  if [ ! -f "$SNAP" ]; then
    : > "$SNAP"
    for pair in "${PAIRS[@]}"; do
      echo "${pair#*:}|$(current_target "${pair#*:}")" >> "$SNAP"
    done
    echo "📸 pre-cutover targets → $SNAP"
  else
    echo "📸 snapshot already exists (kept): $SNAP"
  fi
  local src dst
  for pair in "${PAIRS[@]}"; do
    src="$UV/${pair%%:*}"; dst="${pair#*:}"
    [ -e "$src" ] || { print -P "  %F{yellow}skip%f $src missing in worktree"; continue; }
    mkdir -p "${dst:h}"
    [ -L "$dst" ] || [ ! -e "$dst" ] || { print -P "  %F{red}refuse%f ${dst/#$HOME/~} is a REGULAR file — resolve by hand"; continue; }
    rm -f "$dst"; ln -s "$src" "$dst"
    echo "  ✓ ${dst/#$HOME/~} → ${src/#$HOME/~}"
  done
  print -P "%B→ flipped. Open a new shell (or exec zsh) to load uv-only.%b"
}

rollback(){
  [ -f "$SNAP" ] || { echo "✗ no snapshot at $SNAP — nothing to roll back to"; exit 1; }
  while IFS='|' read -r dst tgt; do
    case "$tgt" in
      MISSING)      rm -f "$dst"; echo "  ✓ removed ${dst/#$HOME/~} (did not exist pre-cutover)" ;;
      REGULAR-FILE) echo "  ⚠ ${dst/#$HOME/~} was a regular file pre-cutover — left as-is" ;;
      *)            rm -f "$dst"; ln -s "$tgt" "$dst"; echo "  ✓ ${dst/#$HOME/~} → ${tgt/#$HOME/~}" ;;
    esac
  done < "$SNAP"
  print -P "%B→ rolled back. Open a new shell (or exec zsh) to load the previous config.%b"
}

case "$MODE" in
  --status)    status ;;
  --to-uvonly) flip; echo; status ;;
  --rollback)  rollback; echo; status ;;
  *) echo "usage: flip_uvonly.sh [--status|--to-uvonly|--rollback]"; exit 1 ;;
esac
