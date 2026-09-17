#!/bin/zsh
###############################################################################
# 🏁 preflight_gauntlet.sh — MIGRATION.md Phase 3 as an executable scorecard
#
# Runs the verification gauntlet and prints PASS/FAIL per check. Used:
#   - on the OLD Intel machine inside the try-uv trial shell (the dry run):
#       ZDOTDIR=<trial> zsh -i -c '<worktree>/custom_scripts/preflight_gauntlet.sh'
#   - on the NEW machine after install.sh (the real Phase 3 gate).
#
# Exit 0 = all PASS. Any FAIL → exit 1.
###############################################################################
set -u
W="${DOTFILES_WORKTREE:-$HOME/Code/000-config/dotfiles-uv-worktree}"
[ -d "$W/shell" ] || W="$HOME/Code/000-config/001-dotfiles"   # new machine: canonical clone

typeset -i pass=0 fail=0
ok()  { print -P "  %F{green}PASS%f $1"; ((++pass)); }   # ++pre: ((pass++)) returns 1 when 0 → && || double-fire
bad() { print -P "  %F{red}FAIL%f $1"; ((++fail)); }
wrn() { print -P "  %F{yellow}WARN%f $1 (expected on the Intel rehearsal)"; ((++pass)); }

echo "🏁 Preflight gauntlet (config root: $W)"

# 1. syntax on every shell file
for f in "$W"/shell/zshrc "$W"/shell/zshenv "$W"/shell/zprofile "$W"/shell/aliases; do
  [ -f "$f" ] || { bad "missing $f"; continue; }
  zsh -n "$f" 2>/dev/null && ok "zsh -n ${f:t}" || bad "zsh -n ${f:t}"
done

# 2. no pyenv anywhere in the active environment
# (INTEL_REHEARSAL=1: the trial shell inherits the live parent's PATH — pyenv
#  presence is inherited, not configured; a real M5 shell must be strict.)
if command -v pyenv >/dev/null 2>&1; then
  [ "${INTEL_REHEARSAL:-0}" = 1 ] && wrn "pyenv on PATH (inherited from live parent shell)" || bad "pyenv on PATH (must be retired)"
else ok "no pyenv on PATH"; fi
case ":$PATH:" in
  *".pyenv"*) [ "${INTEL_REHEARSAL:-0}" = 1 ] && wrn "PATH contains .pyenv (inherited)" || bad "PATH contains .pyenv";;
  *) ok "PATH clean of .pyenv";;
esac

# 3. toolchain
command -v uv >/dev/null 2>&1 && ok "uv present ($(uv --version 2>/dev/null | head -1))" || bad "uv missing"
if uv run --python 3.12 python -c 'import sys; assert sys.version_info[:2]==(3,12)' >/dev/null 2>&1; then
  ok "uv run --python 3.12"
else bad "uv run --python 3.12"; fi

# 4. autoenv 4 cases (needs the zshrc's autoenv_activate loaded — run via zsh -i)
if typeset -f autoenv_activate >/dev/null 2>&1; then
  T=$(mktemp -d)
  # (a) plain dir → sandbox fallback or clean no-op (must not error)
  ( cd "$T" && autoenv_activate >/dev/null 2>&1 ) && ok "autoenv: plain dir no-error" || bad "autoenv: plain dir errored"
  # (b) project .venv → activates it
  mkdir -p "$T/proj/.venv/bin"; printf '#!/bin/sh\n' > "$T/proj/.venv/bin/activate"
  ( cd "$T/proj" && autoenv_activate >/dev/null 2>&1 ) && ok "autoenv: project .venv no-error" || bad "autoenv: project .venv errored"
  # (c) plain-version .python-version → prints the envup hint (assert the BEHAVIOR,
  # not the exit code — the hint path legitimately returns non-zero)
  mkdir -p "$T/ver"; echo "3.12" > "$T/ver/.python-version"
  out=$( cd "$T/ver" && autoenv_activate 2>&1 )
  [[ "$out" == *envup* || "$out" == *python-version* ]] && ok "autoenv: version-hint printed" || bad "autoenv: version-hint missing ($out)"
  # (d) legacy pyenv env-name .python-version → ignored with the documented notice
  mkdir -p "$T/legacy"; echo "deepTechno" > "$T/legacy/.python-version"
  out=$( cd "$T/legacy" && autoenv_activate 2>&1 )
  [[ "$out" == *Ignoring*legacy* || "$out" == *legacy* ]] && ok "autoenv: legacy env-name ignored" || bad "autoenv: legacy env-name not ignored ($out)"
  rm -rf "$T"
else
  bad "autoenv_activate not loaded (run inside zsh -i with the uv-only zshrc)"
fi

# 5. identity matrix
# identity must be probed from INSIDE real repos (includeIf matches by gitdir)
prepo=$(find "$HOME/Code/005-products" -maxdepth 2 -name .git \( -type d -o -type f \) 2>/dev/null | head -1)
wrepo=$(find "$HOME/Code/002-engenious" -maxdepth 3 -name .git \( -type d -o -type f \) 2>/dev/null | head -1)
pe=$([ -n "$prepo" ] && git -C "${prepo%/.git}" config user.email 2>/dev/null || git config --global user.email 2>/dev/null)
we=$([ -n "$wrepo" ] && git -C "${wrepo%/.git}" config user.email 2>/dev/null || echo "")
if [ -n "$pe" ] && [[ "$pe" == *gmail* ]]; then ok "personal identity ($pe)"; else bad "personal identity ($pe)"; fi
if [ -d "$HOME/Code/002-engenious" ]; then
  if [ -n "$we" ] && [[ "$we" == *engenious* ]]; then ok "work identity ($we)"; else bad "work identity ($we)"; fi
else ok "work dir absent — identity check skipped"; fi
command -v gh >/dev/null 2>&1 && ok "gh present ($(gh auth status 2>&1 | grep -c 'Logged in') account(s))" || bad "gh missing"

# 6. git-lfs filter functional (the audit found required=true with no commands)
if git config --get filter.lfs.clean >/dev/null 2>&1 && command -v git-lfs >/dev/null 2>&1; then
  ok "git-lfs filter wired"
elif git config --get filter.lfs.required >/dev/null 2>&1; then
  [ "${INTEL_REHEARSAL:-0}" = 1 ] && wrn "lfs filter broken in LIVE gitconfig (fixed on uv-only; M5 gets the fix)" \
    || bad "filter.lfs.required set but clean/smudge or git-lfs binary missing"
else ok "no lfs config (fine)"; fi

# 7. containers (optional — only if docker present)
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  docker run --rm hello-world >/dev/null 2>&1 && ok "docker hello-world" || bad "docker hello-world"
else ok "docker not running — container check skipped (optional)"; fi

echo ""
print -P "Result: %F{green}$pass PASS%f / %F{red}$fail FAIL%f"
[ "$fail" -eq 0 ]
