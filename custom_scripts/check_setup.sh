#!/usr/bin/env bash
###############################################################################
# ✅ check_setup.sh — is this machine the same dev setup? (Linux, WSL or Mac)
#
#   check_setup.sh                          # dev-setup scorecard for this machine
#   check_setup.sh --code "$S"              # + prove ~/Code identical to the source machine
#   check_setup.sh --code local:/mnt/buffer/Code   # … or to a local/mounted copy (no ssh)
#
# The code part delegates to verify_code.sh (same folder): every file's sha256,
# mode, symlink target and size on both sides (manifest runs on the source over
# ssh, nothing is copied there) + every repo's refs (except refs/remotes), stash,
# index and status. Honours MIGRATE_EXCL (the exclude list: declined folders are
# not FAILs) and MIGRATE_SSH (the migration key). Always byte-level, so --deep is
# accepted and ignored. Read-only everywhere (git --no-optional-locks).
# Never prints secret values. Exit code = number of FAILs (capped at 125).
# Portable: bash 3.2 (macOS) and bash 5 (Linux) — no associative arrays. LC_ALL=C.
###############################################################################
set -u
export LC_ALL=C
SRC=""
while [ $# -gt 0 ]; do
  case "$1" in
    --code) SRC="${2:?usage: --code 'user@host' | --code local:/dir}"; shift 2 ;;
    --deep) shift ;;                                   # always byte-level now
    -h|--help) sed -n 2,15p "$0"; exit 0 ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

OS=linux; [ "$(uname)" = Darwin ] && OS=mac
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && OS=wsl
CODE="$HOME/Code"; DOT="$CODE/000-config/001-dotfiles"
P=0; F=0; W=0
pass() { printf '  \033[32mPASS\033[0m %s\n' "$1"; P=$((P+1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; F=$((F+1)); }
warn() { printf '  \033[33mWARN\033[0m %s\n' "$1"; W=$((W+1)); }
na()   { printf '  \033[90mN/A \033[0m %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }
chk()  { if eval "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1"; fi; }   # chk <desc> <cmd>
perm() { if [ "$OS" = mac ]; then stat -f %Lp "$1"; else stat -c %a "$1"; fi 2>/dev/null; }
sec()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# Homebrew comes from zprofile (login shells only) — load it so a plain `bash check_setup.sh` sees the same tools
for b in /opt/homebrew/bin/brew /usr/local/bin/brew /home/linuxbrew/.linuxbrew/bin/brew; do
  [ -x "$b" ] && { eval "$("$b" shellenv)"; break; }; done
# nvm-managed node is lazy-loaded in zsh; load it here so node/npm checks are real
export NVM_DIR="$HOME/.nvm"
for n in "${HOMEBREW_PREFIX:-/opt/homebrew}/opt/nvm/nvm.sh" /usr/local/opt/nvm/nvm.sh "$NVM_DIR/nvm.sh"; do
  [ -s "$n" ] && { . "$n" >/dev/null 2>&1; break; }; done
# rustup is keg-only on macOS (zprofile adds opt/rustup/bin) — add it so a non-login run doesn't report rustc/cargo missing
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:${HOMEBREW_PREFIX:-/opt/homebrew}/opt/rustup/bin:/usr/local/go/bin:$HOME/go/bin:$PATH"

echo "✅ check_setup — $(hostname) · $OS · $(date '+%F %H:%M')"

sec "Shell & look"
chk "default shell is zsh"                  '[ "$(basename "${SHELL:-}")" = zsh ] || getent passwd "$USER" | grep -q zsh || dscl . -read "/Users/$USER" UserShell | grep -q zsh'
chk "~/.zshrc → dotfiles"                   '[ -L ~/.zshrc ] && readlink ~/.zshrc | grep -q 000-config'
chk "zshrc syntax"                          'zsh -n ~/.zshrc'
chk "Oh-My-Zsh + autosuggestions + syntax-highlighting" 'test -f ~/.oh-my-zsh/oh-my-zsh.sh && test -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions && test -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting'
chk "Powerlevel10k + ~/.p10k.zsh link"      'test -d ~/.powerlevel10k && [ -L ~/.p10k.zsh ]'
if [ "$OS" = mac ]; then chk "MesloLGS NF font" 'ls ~/Library/Fonts /Library/Fonts 2>/dev/null | grep -qi meslolgs'
elif [ "$OS" = wsl ]; then na "MesloLGS NF font (WSL: lives on the Windows side)"
else chk "MesloLGS NF font" 'fc-list | grep -qi "MesloLGS NF"'; fi
case "$OS" in
  mac) chk "Warp settings (theme dracula)" 'grep -q dracula ~/.warp/settings.toml' ;;
  wsl) na "Warp settings (WSL: Warp for Windows)" ;;
  *)   chk "Warp installed + settings (theme dracula)" 'have warp-terminal && grep -q dracula "${XDG_CONFIG_HOME:-$HOME/.config}/warp-terminal/settings.toml"' ;;
esac
chk "global git ignore (~/.config/git/ignore)" 'test -s ~/.config/git/ignore'

sec "Identity"
chk "~/.gitconfig → dotfiles"               '[ -L ~/.gitconfig ]'
# includeIf gitdir: only applies INSIDE a repo — probe one real repo in each tree
r1=$(find "$CODE/005-products" -maxdepth 2 -name .git -type d 2>/dev/null | head -1); r2=$(find "$CODE/002-engenious" -maxdepth 3 -name .git -type d 2>/dev/null | head -1)
e1=$(git -C "${r1%/.git}" config user.email 2>/dev/null); e2=$(git -C "${r2%/.git}" config user.email 2>/dev/null)
[ -n "$e1" ] && [ -n "$e2" ] && [ "$e1" != "$e2" ] && pass "commit identity: ~/Code personal ≠ 002-engenious work" || fail "commit identity switch (~/Code='$e1', engenious='$e2')"
if have gh; then
  n=$(gh auth status 2>&1 | grep -c 'Logged in to github.com')
  [ "$n" -ge 2 ] && pass "gh logged in to both accounts" || fail "gh accounts logged in: $n (need personal + work)"
else fail "gh installed"; fi
chk "ssh to GitHub as juan-garassino"       'ssh -o BatchMode=yes -o ConnectTimeout=8 -T git@github.com 2>&1 | grep -q "Hi juan-garassino"'

sec "Python (uv only)"
chk "uv is the standalone ~/.local/bin/uv"  '[ "$(command -v uv)" = "$HOME/.local/bin/uv" ] || [ "$(command -v uv)" = "$(brew --prefix 2>/dev/null)/bin/uv" ]'
chk "no pyenv anywhere"                     '! have pyenv && [ ! -d ~/.pyenv ]'
for v in 3.11 3.12 3.13; do chk "uv Python $v" "uv python find $v"; done
chk "~/.venv-sandbox exists (mysandbox)"    'test -x ~/.venv-sandbox/bin/python'
chk "ruff + pre-commit (uv tools)"          'have ruff && have pre-commit'

sec "Tools"
for t in git gh direnv jq claude docker gcloud terraform kubectl helm minikube k3d aws act runpodctl cloud-sql-proxy ngrok psql ffmpeg git-lfs tesseract rustc cargo go node npm code; do
  have "$t" && pass "$t" || fail "$t"
done
chk "docker compose plugin"                 'docker compose version'
if have docker; then
  docker info >/dev/null 2>&1 && pass "docker daemon reachable (no sudo)" || fail "docker daemon reachable — re-login for the docker group / start colima or Docker Desktop"
fi

sec "Claude Code"
chk "settings.json has the status line"     'jq -e .statusLine ~/.claude/settings.json'
chk "status line renders"                   'echo "{}" | bash ~/.claude/statusline-command.sh'
s=$(ls ~/.claude/skills 2>/dev/null | wc -l | tr -d ' '); [ "$s" -ge 20 ] && pass "personal skills present ($s)" || fail "personal skills present ($s)"
m=$(jq -r '[.mcpServers // {} | keys[]] + [.projects // {} | .[] | .mcpServers // {} | keys[]] | unique | join(",")' ~/.claude.json 2>/dev/null)
echo "$m" | grep -q discord-me && pass "MCP servers merged ($m)" || warn "MCP servers from the source not merged yet (have: ${m:-none})"
slug="-$(echo "$CODE" | tr '/' '-' | sed 's/^-//')"
[ -d "$HOME/.claude/projects/$slug" ] && pass "Claude memory for $CODE ($slug)" || warn "no Claude memory dir for $slug (copy the source slug, MIGRATE.md step 6)"

sec "Secrets & credentials (names only)"
if [ -f ~/.secrets ]; then
  [ "$(perm ~/.secrets)" = 600 ] && pass "~/.secrets mode 600" || fail "~/.secrets mode $(perm ~/.secrets) (want 600)"
  k=$(grep -E '^export [A-Z_]+=' ~/.secrets | grep -cvE '=("")?$'); [ "$k" -ge 5 ] && pass "~/.secrets has $k filled keys" || fail "~/.secrets has only $k filled keys"
else fail "~/.secrets exists"; fi
for f in ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_work; do
  [ -f "$f" ] && [ "$(perm "$f")" = 600 ] && pass "$(basename "$f") present, 600" || fail "$(basename "$f") present, 600"
done
chk "gcloud has an active account"          'gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q @'
chk "~/.aws present"                        'test -d ~/.aws'
chk "~/.engenious_university.env present"   'test -f ~/.engenious_university.env'

sec "Migration hygiene"
[ -e /etc/sudoers.d/99-migration ] && fail "temporary NOPASSWD sudo still present (sudo rm /etc/sudoers.d/99-migration)" || pass "no leftover NOPASSWD sudo"
# ~/.ssh/config is a symlink into this public repo: tools that append to it (colima's Include line) change the repo
[ -z "$(git -C "$DOT" status --porcelain -- ssh/config 2>/dev/null)" ] && pass "repo ssh/config unchanged" \
  || fail "repo ssh/config modified — a tool appended to ~/.ssh/config (colima: sshConfig: false); git -C $DOT diff ssh/config"
if [ "$OS" != mac ]; then
  [ -L /Users/juan-garassino ] && pass "/Users/juan-garassino → $HOME (path compat)" || warn "no /Users/juan-garassino compat symlink (old absolute paths won't resolve)"
fi

sec "Code (local)"
# every .git (dir or worktree file) at any depth; node_modules/.venv/venv/.venv-* pruned, not depth-limited
gits() { find "$CODE" \( -name node_modules -o -name .venv -o -name venv -o -name '.venv-*' \) -prune -o \
           -name .git \( -type d -o -type f \) -print -prune 2>/dev/null; }
REPOS=$(gits | wc -l | tr -d ' ')
[ "$REPOS" -ge 150 ] && pass "~/Code has $REPOS git repos" || warn "~/Code has $REPOS git repos (source had ~330 incl. worktrees)"
if [ "$OS" != mac ]; then
  ic=0; while IFS= read -r g; do
    [ "$(git -C "${g%/.git}" --no-optional-locks config core.ignorecase 2>/dev/null)" = true ] && ic=$((ic+1)); done < <(gits)
  [ "$ic" -eq 0 ] && pass "core.ignorecase=false everywhere (case-sensitive FS)" || fail "$ic repos still core.ignorecase=true (MIGRATE.md step 9)"
fi
bw=0; while IFS= read -r g; do
  git -C "${g%/.git}" --no-optional-locks rev-parse --git-dir >/dev/null 2>&1 || bw=$((bw+1)); done < <(gits | while IFS= read -r g; do [ -f "$g" ] && echo "$g"; done)
[ "$bw" -eq 0 ] && pass "all git worktrees resolve" || fail "$bw worktrees broken (git worktree repair)"

# ---------------------------------------------------------------- code sync vs source
if [ -n "$SRC" ]; then
  sec "Code sync vs $SRC"
  VC="$(cd "$(dirname "$0")" && pwd)/verify_code.sh"; [ -x "$VC" ] || VC="$DOT/custom_scripts/verify_code.sh"
  if [ ! -x "$VC" ]; then fail "verify_code.sh not found next to $0 (dotfiles not cloned?)"
  else
    vargs=()
    [ -n "${MIGRATE_EXCL:-}" ] && vargs=(--excl-file "$MIGRATE_EXCL")
    case "$SRC" in
      local:*|*' '*) vargs+=(--source "$SRC") ;;                 # local dir, or 'SSHCMD user@host'
      *)             vargs+=(--source "${MIGRATE_SSH:-ssh} $SRC") ;;
    esac
    [ -n "${MIGRATE_EXCL:-}" ] || warn "MIGRATE_EXCL unset — declined folders will show as differences"
    echo "  … verify_code.sh ${vargs[*]} (sha256 of every file + git state, both sides; a few minutes)"
    out=$(mktemp); "$VC" "${vargs[@]}" > "$out" 2>&1; rc=$?
    sed 's/^/       /' "$out"; rm -f "$out"
    case "$rc" in
      0) pass "$CODE identical to $SRC: every file (content, mode, symlinks) and every repo's refs/stash/index/status" ;;
      3) fail "verify_code.sh canary not detected — the comparison is blind" ;;
      2) fail "verify_code.sh usage error (rc=2) — see output above" ;;
      *) fail "$CODE differs from $SRC or a side reported errors (verify_code.sh rc=$rc) — re-run the MIGRATE.md step-7 rsync, then this check" ;;
    esac
  fi
fi

printf '\n\033[1mResult: %s PASS · %s FAIL · %s WARN\033[0m\n' "$P" "$F" "$W"
exit $(( F > 125 ? 125 : F ))
