#!/bin/zsh
###############################################################################
# 🎭 rehearse_install.sh — virgin-home installer rehearsal in a container
#
# Spins up a fresh ubuntu:24.04 container, creates a normal user, clones the
# PUBLIC dotfiles repo's uv-only branch FROM GITHUB (proves clonability), runs
# install.sh (the Linux branch: apt + uv, no brew), and asserts the bootstrap
# actually produced a working shell. This is the closest thing to a dry run of
# the new-Mac Phase 2 that exists without the hardware: it exercises install
# ordering, the OMZ presence-check fix, plugin clones, symlinks, and uv.
#
# Usage: rehearse_install.sh [branch=uv-only]   (docker daemon must be up)
# Exit 0 = all assertions PASS.
###############################################################################
set -eu
BRANCH="${1:-uv-only}"
NAME="dotfiles-rehearsal"
IMG="ubuntu:24.04"

docker info >/dev/null 2>&1 || { echo "❌ docker daemon not running"; exit 2; }
docker rm -f "$NAME" >/dev/null 2>&1 || true

echo "🎭 Starting fresh $IMG container..."
docker run -d --name "$NAME" "$IMG" sleep infinity >/dev/null

X() { docker exec "$NAME" bash -lc "$1"; }
XT() { docker exec -u tester "$NAME" bash -lc "$1"; }

echo "── provisioning bare-minimum (git/zsh/sudo/curl — the machine-vendor layer)"
X "export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y -qq git zsh curl sudo ca-certificates locales >/dev/null"
X "useradd -m -s /bin/bash tester && echo 'tester ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/tester"

echo "── cloning dotfiles@$BRANCH from GitHub (clonability proof)"
XT "mkdir -p ~/Code/000-config && git clone -q --branch $BRANCH https://github.com/juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles"

echo "── RUN 1: install.sh (unattended)"
set +e
XT "cd ~/Code/000-config/001-dotfiles && DEBIAN_FRONTEND=noninteractive zsh ./install.sh" > /tmp/rehearse-run1.log 2>&1
RUN1=$?
set -e
tail -5 /tmp/rehearse-run1.log | sed 's/^/    /'
echo "    (full log: /tmp/rehearse-run1.log, exit=$RUN1)"

echo "── assertions"
typeset -i pass=0 fail=0
A() { # A <desc> <container-cmd-as-tester>
  if XT "$2" >/dev/null 2>&1; then echo "  PASS $1"; ((pass++)); else echo "  FAIL $1"; ((fail++)); fi
}
A "oh-my-zsh actually installed (the fixed check)" "test -f ~/.oh-my-zsh/oh-my-zsh.sh"
A "zsh-autosuggestions cloned"                     "test -d ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
A "zsh-syntax-highlighting cloned"                 "test -d ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
A "powerlevel10k cloned"                           "test -d ~/.powerlevel10k"
A "~/.zshrc symlink lands"                         "test -L ~/.zshrc && test -f ~/.zshrc"
A "~/.gitconfig symlink lands"                     "test -L ~/.gitconfig"
A "~/.ssh/config symlink lands"                    "test -L ~/.ssh/config"
A "uv installed"                                   "test -x ~/.local/bin/uv || command -v uv"
A "zsh -n on the linked zshrc"                     "zsh -n ~/.zshrc"
A "interactive shell exits clean"                  "zsh -i -c exit"
A "no pyenv anywhere"                              "! command -v pyenv && ! test -d ~/.pyenv"

echo "── RUN 2: idempotency (re-run must not fail or duplicate)"
set +e
XT "cd ~/Code/000-config/001-dotfiles && DEBIAN_FRONTEND=noninteractive zsh ./install.sh" > /tmp/rehearse-run2.log 2>&1
RUN2=$?
set -e
if [ "$RUN2" -eq 0 ]; then echo "  PASS re-run exits 0"; ((pass++)); else echo "  FAIL re-run exit=$RUN2 (log: /tmp/rehearse-run2.log)"; ((fail++)); fi

docker rm -f "$NAME" >/dev/null
echo ""
echo "🎭 Rehearsal result: $pass PASS / $fail FAIL (run1 exit=$RUN1)"
[ "$fail" -eq 0 ]
