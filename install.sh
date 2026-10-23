#!/bin/zsh

###############################################################################
# 🛠️  install.sh — Dotfiles installer (macOS + Linux)
# Run from inside ~/Code/000-config/001-dotfiles/
###############################################################################

set -e
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

OS="$(uname)"   # Darwin | Linux
PM=""           # Linux package manager
IS_WSL=0        # Ubuntu inside Windows (WSL2): no desktop; fonts + terminal live on the Windows side
grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null && IS_WSL=1
export IS_WSL
if [ "$OS" = "Linux" ]; then
  if command -v apt-get >/dev/null 2>&1; then PM="apt"
  elif command -v dnf >/dev/null 2>&1; then PM="dnf"
  elif command -v yum >/dev/null 2>&1; then PM="yum"; fi
fi

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║        🛠️  Dotfiles Installer                    ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

###############################################################################
# Helpers
###############################################################################

# backup FILE — move a REAL file/dir aside as FILE.<YYYYmmdd-HHMMSS>.backup (the migration
# hygiene gate finds leftovers with `-name '*.backup'`, so the suffix must stay `.backup`).
# Symlinks are never backed up: symlink() replaces them in place.
backup() {
  local target=$1 dest
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    dest="$target.$(date +%Y%m%d-%H%M%S).backup"
    [ -e "$dest" ] && dest="$target.$(date +%Y%m%d-%H%M%S).$$.backup"
    mv "$target" "$dest"
    echo "  📦 Backed up $target → $dest"
  fi
}

# symlink TARGET LINK — idempotent:
#   LINK is a symlink → TARGET        : untouched ("Already linked")
#   LINK is a symlink → anything else : replaced (covers DANGLING links, e.g. a copied ~/.ssh/config
#                                       pointing at /Users/<old-user>/… — `[ -e ]` is false for those,
#                                       so the old code ran `ln -s`, hit "File exists" and set -e aborted)
#   LINK is a real file/dir           : backed up (timestamped), then linked
#   LINK absent                       : linked
symlink() {
  local file=$1 link=$2 current
  if [ -L "$link" ]; then
    current="$(readlink "$link")"
    if [ "$current" = "$file" ]; then
      echo "  ✅ Already linked: $link"
    else
      ln -sfn "$file" "$link"
      echo "  🔁 Relinked $link (was → $current)"
    fi
  elif [ -e "$link" ]; then
    backup "$link"
    ln -s "$file" "$link"
    echo "  🔗 Linked $link"
  else
    ln -s "$file" "$link"
    echo "  🔗 Linked $link"
  fi
}

# install_meslo_fonts DIR — the 4 "MesloLGS NF" ttf files p10k + Warp expect (Warp settings say
# font_name = "MesloLGS NF"; the Brewfile's font-meslo-lg-nerd-font cask installs a DIFFERENT
# family name, "MesloLGS Nerd Font", so the cask alone leaves Warp on a fallback font). Idempotent.
install_meslo_fonts() {
  local dir=$1 v f
  mkdir -p "$dir"
  for v in "Regular" "Bold" "Italic" "Bold Italic"; do
    f="$dir/MesloLGS NF $v.ttf"
    [ -s "$f" ] && continue
    curl -fsSL -o "$f" "https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20${v// /%20}.ttf" \
      || { rm -f "$f"; echo "  ⚠️  font download failed: MesloLGS NF $v"; }
  done
  echo "  🔤 MesloLGS NF present in $dir"
}

# link_editor_settings — VS Code / Cursor settings.json → repo copy. Called in step 3 AND again
# after the Brewfile step: on a first run the apps don't exist yet at step 3 (they install in
# step 6), so the User dir is missing and the link used to be skipped silently.
link_editor_settings() {
  local editor_path
  if [[ "$OS" == "Darwin" ]]; then
    CODE_PATH="$HOME/Library/Application Support/Code/User"
    CURSOR_PATH="$HOME/Library/Application Support/Cursor/User"
    [ -d "/Applications/Visual Studio Code.app" ] && mkdir -p "$CODE_PATH"
    [ -d "/Applications/Cursor.app" ]             && mkdir -p "$CURSOR_PATH"
  else
    CODE_PATH="$HOME/.config/Code/User"
    CURSOR_PATH="$HOME/.config/Cursor/User"
    if [ ! -e "$CODE_PATH" ]; then
      if command -v code >/dev/null 2>&1; then mkdir -p "$CODE_PATH"
      else CODE_PATH="$HOME/.vscode-server/data/Machine"; fi
    fi
  fi
  for editor_path in "$CODE_PATH" "$CURSOR_PATH"; do
    if [ -d "$editor_path" ]; then
      symlink "$DOTFILES_DIR/editor/settings.json" "$editor_path/settings.json"
    else
      echo "  ⏭️  $editor_path not present yet — editor settings linked after the app installs"
    fi
  done
}

# merge_docker_plugins_dir DIR — Homebrew's docker-compose is a CLI plugin; `docker compose` only
# works once ~/.docker/config.json lists $HOMEBREW_PREFIX/lib/docker/cli-plugins in
# cliPluginsExtraDirs (the formula's caveat). jq merge via temp file + mv; an invalid file is
# never clobbered.
merge_docker_plugins_dir() {
  local dir=$1 cfg="$HOME/.docker/config.json" tmp
  command -v jq >/dev/null 2>&1 || { echo "  ⚠️  jq missing — add \"cliPluginsExtraDirs\": [\"$dir\"] to $cfg by hand"; return 0; }
  mkdir -p "$HOME/.docker"
  if [ ! -s "$cfg" ]; then
    printf '{\n  "cliPluginsExtraDirs": ["%s"]\n}\n' "$dir" > "$cfg"
    echo "  🐳 $cfg created (docker compose plugin dir)"
    return 0
  fi
  if ! jq -e . "$cfg" >/dev/null 2>&1; then
    echo "  ⚠️  $cfg is not valid JSON — left untouched; add \"cliPluginsExtraDirs\": [\"$dir\"] by hand"
    return 0
  fi
  if jq -e --arg d "$dir" '(.cliPluginsExtraDirs // []) | index($d) != null' "$cfg" >/dev/null 2>&1; then
    echo "  ✅ docker compose plugin dir already in $cfg"
    return 0
  fi
  tmp="$(mktemp "$HOME/.docker/config.json.XXXXXX")" || return 0
  if jq --arg d "$dir" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$d] | unique)' "$cfg" > "$tmp"; then
    mv "$tmp" "$cfg" && echo "  🐳 docker compose plugin dir added to $cfg"
  else
    rm -f "$tmp"; echo "  ⚠️  jq merge failed — $cfg left untouched"
  fi
}

###############################################################################
# 0. Platform packages — macOS: Homebrew · Linux: apt/dnf (adapted from Le Wagon)
###############################################################################
echo "🧰 Platform packages ($OS${PM:+/$PM}$( [ "$IS_WSL" = 1 ] && echo ' · WSL'))..."

if [ "$OS" = "Darwin" ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "  📦 Installing Command Line Tools (accept the GUI prompt)..."
    xcode-select --install || true
  fi
  # brew may be installed but not on PATH yet (fresh login shell, Claude's `zsh -c`) — put it on
  # PATH BEFORE deciding to run the installer, or an installed Homebrew gets re-installed.
  if ! command -v brew >/dev/null 2>&1; then
    for _b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$_b" ] && { eval "$("$_b" shellenv)"; break; }
    done
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "  🍺 Installing Homebrew..."
    # The Homebrew installer needs sudo. NONINTERACTIVE=1 skips its "Press RETURN" prompt but
    # then it can only work with passwordless sudo; without a TTY it would die with a cryptic
    # "sudo: a terminal is required" inside `set -e`. Say so up front instead.
    if sudo -n true 2>/dev/null; then
      NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { echo "  ❌ Homebrew installer failed — fix the error above and re-run ./install.sh"; exit 1; }
    elif [ -t 0 ]; then
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
        || { echo "  ❌ Homebrew installer failed — fix the error above and re-run ./install.sh"; exit 1; }
    else
      echo "  ❌ Homebrew is not installed and this run has no terminal and no passwordless sudo."
      echo "     Either run in a terminal:  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      echo "     or grant passwordless sudo for the install (e.g. a temporary /etc/sudoers.d entry), then re-run ./install.sh"
      exit 1
    fi
    for _b in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [ -x "$_b" ] && { eval "$("$_b" shellenv)"; break; }
    done
  fi
  # MesloLGS NF into ~/Library/Fonts (the font Warp/p10k are configured for; see install_meslo_fonts)
  install_meslo_fonts "$HOME/Library/Fonts"

elif [ "$OS" = "Linux" ]; then
  pkglist() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$1" 2>/dev/null; }
  if [ "$PM" = "apt" ]; then
    echo "  📦 apt: core tools..."
    sudo apt-get update -y
    # One missing name makes apt-get abort the WHOLE transaction (list was rehearsed on 24.04;
    # newer releases drop/rename packages) — install only what this release actually has.
    avail=(); missing=()
    for p in $(pkglist "$DOTFILES_DIR/packages/apt.txt"); do
      # `apt-cache show` passes for referenced-but-uninstallable names (e.g. tldr on 26.04);
      # only a real install candidate counts
      apt-cache policy "$p" 2>/dev/null | grep -q 'Candidate: [^(]' && avail+=("$p") || missing+=("$p")
    done
    [ ${#missing[@]} -gt 0 ] && echo "  ⚠️  not in this release, skipped: ${missing[*]}"
    [ ${#avail[@]} -gt 0 ] && { sudo apt-get install -y "${avail[@]}" || echo "  ⚠️  some apt packages failed"; }
    if ! command -v gh >/dev/null 2>&1; then
      echo "  📦 GitHub CLI (apt repo)..."
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update -y && sudo apt-get install -y gh
    fi
    if ! command -v code >/dev/null 2>&1; then
      echo "  📦 VS Code (Microsoft apt repo)..."
      curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/ms.gpg
      sudo install -D -o root -g root -m 644 /tmp/ms.gpg /etc/apt/keyrings/packages.microsoft.gpg && rm -f /tmp/ms.gpg
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
      sudo apt-get update -y && sudo apt-get install -y code
    fi
    # Brewfile-equivalent CLI toolchain: docker, gcloud, terraform, kubectl, helm, aws, llm, ollama
    bash "$DOTFILES_DIR/packages/linux-tools.sh" || echo "  ⚠️  linux-tools.sh had failures (see above)"
  elif [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
    echo "  📦 $PM: core tools..."
    pkglist "$DOTFILES_DIR/packages/dnf.txt" | xargs -r sudo "$PM" install -y || echo "  ⚠️  some packages failed"
    command -v gh >/dev/null 2>&1 || sudo "$PM" install -y gh || true
    if ! command -v code >/dev/null 2>&1; then
      echo "  📦 VS Code (Microsoft rpm repo)..."
      sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc || true
      printf '[code]\nname=Visual Studio Code\nbaseurl=https://packages.microsoft.com/yumrepos/vscode\nenabled=1\ngpgcheck=1\ngpgkey=https://packages.microsoft.com/keys/microsoft.asc\n' | sudo tee /etc/yum.repos.d/vscode.repo >/dev/null
      sudo "$PM" install -y code || true
    fi
  else
    echo "  ⚠️  No supported package manager (apt/dnf/yum) — install tools manually."
  fi
  # uv (official installer) — the ONLY Python manager; no pyenv
  command -v uv >/dev/null 2>&1 || { echo "  📦 uv..."; curl -LsSf https://astral.sh/uv/install.sh | sh; }
  # MesloLGS NF — the p10k font (macOS gets it from the Brewfile cask). Without it the prompt
  # renders tofu boxes. Then point the desktop terminal at it (GNOME Terminal / Ptyxis).
  FONT_DIR="$HOME/.local/share/fonts"
  install_meslo_fonts "$FONT_DIR"
  command -v fc-cache >/dev/null 2>&1 && fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
  if [ "$IS_WSL" = 1 ]; then
    echo "  🪟 WSL: the terminal is a Windows app — install MesloLGS NF on WINDOWS (double-click the 4"
    echo "     .ttf files in $FONT_DIR via "'\\\\wsl$'" → Install for all users) and set Windows Terminal /"
    echo "     Warp for Windows → font 'MesloLGS NF', size 14. Warp settings: terminal/warp-settings.toml."
  fi
  if command -v gsettings >/dev/null 2>&1; then
    prof="$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")"
    if [ -n "$prof" ]; then
      p="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$prof/"
      gsettings set "$p" use-system-font false 2>/dev/null && gsettings set "$p" font 'MesloLGS NF 14' 2>/dev/null \
        && echo "  🖥️  GNOME Terminal font → MesloLGS NF 14"
    fi
    gsettings set org.gnome.Ptyxis use-system-font false 2>/dev/null && gsettings set org.gnome.Ptyxis font-name 'MesloLGS NF 14' 2>/dev/null \
      && echo "  🖥️  Ptyxis font → MesloLGS NF 14"
  fi
  # nvm (standalone; zshrc lazy-loads $NVM_DIR/nvm.sh). PROFILE=/dev/null: never let it edit
  # the symlinked zshrc.
  [ -s "$HOME/.nvm/nvm.sh" ] || { echo "  📦 nvm..."; curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | PROFILE=/dev/null bash >/dev/null 2>&1 || echo "  ⚠️  nvm install failed"; }
  # default shell → zsh
  if command -v zsh >/dev/null 2>&1 && [ "$SHELL" != "$(command -v zsh)" ]; then
    chsh -s "$(command -v zsh)" 2>/dev/null && echo "  🐚 default shell → zsh (re-login to apply)" || true
  fi
fi

###############################################################################
# 1. Symlink dotfiles
###############################################################################
echo "📂 Symlinking dotfiles..."

# Explicit map (repo is organized into subdirs): "<repo path>:<home target>"
mkdir -p "$HOME/.config/direnv" "$HOME/.config/git"
link_map=(
  "shell/zshrc:$HOME/.zshrc"
  "shell/zshenv:$HOME/.zshenv"
  "shell/zprofile:$HOME/.zprofile"
  "shell/aliases:$HOME/.aliases"
  "git/gitconfig:$HOME/.gitconfig"
  "git/gitconfig-personal:$HOME/.gitconfig-personal"
  "git/gitconfig-work:$HOME/.gitconfig-work"
  "git/ignore:$HOME/.config/git/ignore"
  "prompt/p10k.zsh:$HOME/.p10k.zsh"
  "direnv/direnvrc:$HOME/.config/direnv/direnvrc"
)
for pair in "${link_map[@]}"; do
  src="${pair%%:*}"; dst="${pair#*:}"
  symlink "$DOTFILES_DIR/$src" "$dst"
done

###############################################################################
# 2. SSH config
###############################################################################
echo ""
echo "🔐 SSH config..."
if [[ "$(uname)" == "Darwin" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  symlink "$DOTFILES_DIR/ssh/config" ~/.ssh/config

  # Modern macOS keychain flag (Ventura+)
  if [ -f ~/.ssh/id_ed25519_personal ]; then
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal 2>/dev/null && \
      echo "  ✅ Personal SSH key added to keychain" || \
      echo "  ℹ️  Personal key already in keychain or not found"
  fi
  if [ -f ~/.ssh/id_ed25519_work ]; then
    ssh-add --apple-use-keychain ~/.ssh/id_ed25519_work 2>/dev/null && \
      echo "  ✅ Work SSH key added to keychain" || \
      echo "  ℹ️  Work key already in keychain or not found"
  fi
else
  # Linux — symlink config + add keys to the ssh-agent (no macOS keychain)
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  symlink "$DOTFILES_DIR/ssh/config" ~/.ssh/config
  eval "$(ssh-agent -s)" >/dev/null 2>&1 || true
  [ -f ~/.ssh/id_ed25519_personal ] && ssh-add ~/.ssh/id_ed25519_personal 2>/dev/null || true
  [ -f ~/.ssh/id_ed25519_work ]     && ssh-add ~/.ssh/id_ed25519_work 2>/dev/null || true
fi

###############################################################################
# 3. VS Code / Cursor settings
###############################################################################
echo ""
echo "⚙️  VS Code / Cursor settings..."

link_editor_settings   # repeated after step 6 once the apps exist

###############################################################################
# 4. Oh-My-Zsh + zsh plugins
# ORDER MATTERS: the OMZ installer refuses to run if ~/.oh-my-zsh already exists
# (even empty), so OMZ must install BEFORE anything mkdirs into it — the old
# layout (plugins first) pre-created the dir and the fresh-machine install died
# with "The $ZSH folder already exists". Caught by rehearse_install.sh.
###############################################################################
echo ""
echo "🎨 Oh-My-Zsh..."
if [ ! -f "$HOME/.oh-my-zsh/oh-my-zsh.sh" ]; then
  if [ -d "$HOME/.oh-my-zsh" ]; then
    echo "  🧹 Removing empty/broken ~/.oh-my-zsh (no oh-my-zsh.sh inside)"
    rm -rf "$HOME/.oh-my-zsh"
  fi
  echo "  📦 Installing Oh-My-Zsh..."
  # CHSH=no: never call chsh (prompts for a password → hangs without a TTY; step 0 handles the
  # default shell on Linux, macOS already uses zsh). RUNZSH=no: don't exec a zsh at the end.
  # KEEP_ZSHRC=yes: don't move our symlinked ~/.zshrc aside. All three are read by tools/install.sh.
  CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    || echo "  ⚠️  Oh-My-Zsh install failed (network?) — re-run ./install.sh later; the shell still works without it"
else
  echo "  ✅ Oh-My-Zsh present"
fi

echo ""
echo "🔌 zsh plugins..."

ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"
mkdir -p "$HOME/.nvm"   # brew nvm needs the working dir to exist

if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  echo "  📦 Installing zsh-syntax-highlighting..."
  git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" \
    || echo "  ⚠️  zsh-syntax-highlighting clone failed (network?) — re-run ./install.sh later"
else
  echo "  ✅ zsh-syntax-highlighting already installed"
fi

if [ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ]; then
  echo "  📦 Installing zsh-autosuggestions..."
  git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions" \
    || echo "  ⚠️  zsh-autosuggestions clone failed (network?) — re-run ./install.sh later"
else
  echo "  ✅ zsh-autosuggestions already installed"
fi

###############################################################################
# 5. Homebrew essentials
###############################################################################
echo ""
echo "🍺 Checking Homebrew essentials..."

if [ "$OS" = "Darwin" ]; then
  BREW_PACKAGES=(gh direnv uv)
  for pkg in "${BREW_PACKAGES[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      echo "  📦 Installing $pkg..."
      brew install "$pkg" || echo "  ⚠️  brew install $pkg failed — the Brewfile step retries it"
    else
      echo "  ✅ $pkg already installed"
    fi
  done
else
  echo "  ⏭️  Linux — gh/direnv/uv handled in step 0 (apt/dnf + curl)"
fi

# uv-managed Pythons + the two project-agnostic global CLIs (→ ~/.local/bin)
if command -v uv &>/dev/null; then
  echo "  🐍 uv python install 3.11 3.12 3.13..."
  uv python install 3.11 3.12 3.13 || echo "  ⚠️  uv python install failed — retry manually"
  uv tool install ruff >/dev/null 2>&1 || true
  uv tool install pre-commit >/dev/null 2>&1 || true
  echo "  ✅ uv tools: ruff, pre-commit"
fi

###############################################################################
# 6. Homebrew bundle — full toolchain (uv, docker, minikube, postgres, fonts… — NO pyenv)
###############################################################################
echo ""
echo "🍺 Restoring full Homebrew bundle..."
if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null && [ -f "$DOTFILES_DIR/packages/Brewfile" ]; then
  brew bundle --file="$DOTFILES_DIR/packages/Brewfile" || echo "  ⚠️  Some bundle entries failed — review output above"
  _prefix="$(brew --prefix)"
  # docker compose (CLI plugin, see merge_docker_plugins_dir) — only once the formula is there
  [ -d "$_prefix/lib/docker/cli-plugins" ] && merge_docker_plugins_dir "$_prefix/lib/docker/cli-plugins"
  # rustup (keg-only: its bin dir is NOT on PATH — zprofile adds $HOMEBREW_PREFIX/opt/rustup/bin)
  # installs no toolchain by itself; without one `cargo`/`rustc` are proxies that error out.
  # `rustup default` prints the active toolchain, so a non-zero exit = none configured yet.
  _rustup="$_prefix/opt/rustup/bin/rustup"
  [ -x "$_rustup" ] || _rustup="$(command -v rustup 2>/dev/null || true)"   # e.g. a carried-over ~/.cargo/bin/rustup
  if [ -n "$_rustup" ] && [ -x "$_rustup" ]; then
    if "$_rustup" default >/dev/null 2>&1; then
      echo "  ✅ rust toolchain: $("$_rustup" default 2>/dev/null)"
    else
      echo "  🦀 rustup default stable..."
      "$_rustup" default stable >/dev/null 2>&1 && echo "  ✅ rust stable installed (cargo via \$HOMEBREW_PREFIX/opt/rustup/bin in zprofile)" \
        || echo "  ⚠️  rustup default stable failed — run it manually later"
    fi
  fi
  # editor settings again — VS Code / Cursor exist now (first run skipped them in step 3)
  echo ""
  echo "⚙️  VS Code / Cursor settings (post-install)..."
  link_editor_settings
else
  echo "  ⏭️  Not macOS / no brew — skipping Brewfile (Linux uses packages/apt.txt|dnf.txt)"
fi

###############################################################################
# 6b. VS Code extensions — restore the snapshot (Le Wagon installs a subset;
#     this ships your full real set so a fresh machine matches the old one).
###############################################################################
echo ""
echo "🧩 VS Code extensions..."
if [ "${DOTFILES_MINIMAL:-0}" = 1 ]; then
  echo "  ⏭️  MINIMAL rehearsal — skipping downloads ($(grep -vcE '^#|^$' "$DOTFILES_DIR/packages/vscode-extensions.txt" 2>/dev/null) in list)"
elif command -v code >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/packages/vscode-extensions.txt" ]; then
  installed="$(code --list-extensions 2>/dev/null)"
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    case "$ext" in \#*) continue ;; esac
    if printf '%s\n' "$installed" | grep -qix "$ext"; then continue; fi
    code --install-extension "$ext" >/dev/null 2>&1 && echo "  + $ext" || echo "  ⚠️  failed: $ext"
  done < "$DOTFILES_DIR/packages/vscode-extensions.txt"
  echo "  ✅ extensions synced"
else
  echo "  ⏭️  code CLI not found / no list — install VS Code first, then re-run"
fi

###############################################################################
# 6c. Global npm CLIs + go tools (brew bundle can't do `npm`/`go` stanzas).
#     Needs node — provided by brew nvm; load it non-interactively here.
###############################################################################
echo ""
echo "🌐 Global npm CLIs + go tools..."
if [ "${DOTFILES_MINIMAL:-0}" = 1 ]; then
  echo "  ⏭️  MINIMAL rehearsal — skipping npm/go installs ($(grep -vcE '^#|^$' "$DOTFILES_DIR/packages/npm-globals.txt" 2>/dev/null) npm globals in list)"
else
_brew_nvm="$(brew --prefix 2>/dev/null || true)/opt/nvm/nvm.sh"
[ -s "$_brew_nvm" ] || _brew_nvm="$HOME/.nvm/nvm.sh"   # Linux: standalone nvm from step 0
if [ -s "$_brew_nvm" ]; then
  mkdir -p "$HOME/.nvm"; export NVM_DIR="$HOME/.nvm"
  . "$_brew_nvm" 2>/dev/null
  nvm install --lts >/dev/null 2>&1 && nvm use --lts >/dev/null 2>&1
fi
if command -v npm >/dev/null 2>&1 && [ -f "$DOTFILES_DIR/packages/npm-globals.txt" ]; then
  while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue; case "$pkg" in \#*) continue ;; esac
    npm ls -g "$pkg" >/dev/null 2>&1 || { npm install -g "$pkg" >/dev/null 2>&1 && echo "  + $pkg" || echo "  ⚠️  npm failed: $pkg"; }
  done < "$DOTFILES_DIR/packages/npm-globals.txt"
else
  echo "  ⏭️  npm not on PATH — run 'nvm install --lts' then re-run install.sh"
fi
if command -v go >/dev/null 2>&1; then
  go install golang.org/x/tools/gopls@latest >/dev/null 2>&1 && echo "  + gopls" || echo "  ⚠️  gopls install failed"
fi
fi   # end DOTFILES_MINIMAL guard

###############################################################################
# 7. Powerlevel10k (OMZ itself installs in step 4, BEFORE the plugins mkdir)
###############################################################################
echo ""
echo "🎨 Powerlevel10k..."
if [ ! -d "$HOME/.powerlevel10k" ]; then
  echo "  📦 Installing Powerlevel10k..."
  git clone --quiet --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.powerlevel10k" \
    || echo "  ⚠️  powerlevel10k clone failed (network?) — re-run ./install.sh later"
else
  echo "  ✅ Powerlevel10k present"
fi

###############################################################################
# 8. Claude Code config (statusline symlink + settings template)
###############################################################################
echo ""
echo "🤖 Claude Code config..."
mkdir -p "$HOME/.claude" "$HOME/.claude-tmp"   # CLAUDE_CODE_TMPDIR (settings env) must exist
symlink "$DOTFILES_DIR/claude/statusline-command.sh" ~/.claude/statusline-command.sh
if [ -f "$DOTFILES_DIR/claude/settings.json" ]; then
  if [ ! -f "$HOME/.claude/settings.json" ]; then
    sed "s#/Users/juan-garassino#$HOME#g" "$DOTFILES_DIR/claude/settings.json" > "$HOME/.claude/settings.json"
    echo "  🔗 Installed Claude settings.json template (machine secrets go in env via ~/.secrets, never here)"
  elif command -v jq >/dev/null 2>&1 && ! jq -e '.statusLine' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    # A fresh login (bootstrap.sh) can create a near-empty settings.json first — merge the
    # template in (template wins) so statusline, hooks and plugins still land.
    cp "$HOME/.claude/settings.json" "$HOME/.claude/settings.json.pre-dotfiles"
    # temp file + mv: `jq … > settings.json` truncates the target BEFORE jq reads, so a jq error
    # (or a Ctrl-C) used to leave an empty settings.json
    _tmp="$(mktemp "$HOME/.claude/settings.json.XXXXXX")"
    if jq -s '.[0] * .[1]' "$HOME/.claude/settings.json.pre-dotfiles" <(sed "s#/Users/juan-garassino#$HOME#g" "$DOTFILES_DIR/claude/settings.json") > "$_tmp"; then
      mv "$_tmp" "$HOME/.claude/settings.json"
      echo "  🔗 Merged Claude settings template into the fresh settings.json (backup: settings.json.pre-dotfiles)"
    else
      rm -f "$_tmp"
      echo "  ⚠️  jq merge failed — settings.json left as it was (template: claude/settings.json)"
    fi
  else
    echo "  ✅ Claude settings.json exists — left as-is (diff against claude/settings.json template if needed)"
  fi
fi
# Personal skills & agents (copied, not symlinked — Claude Code writes into these dirs)
if [ -d "$DOTFILES_DIR/claude/skills" ]; then
  mkdir -p ~/.claude/skills ~/.claude/agents
  rsync -a "$DOTFILES_DIR/claude/skills/" ~/.claude/skills/ 2>/dev/null && echo "  📦 Restored personal Claude skills"
  rsync -a "$DOTFILES_DIR/claude/agents/" ~/.claude/agents/ 2>/dev/null && echo "  📦 Restored Claude agents"
fi

###############################################################################
# 8b. Warp terminal settings (theme "dracula", MesloLGS NF 14, honor_ps1 → p10k prompt)
#     Copied, not symlinked: Warp rewrites the file. __HOME__ = this machine's $HOME.
###############################################################################
if [ -f "$DOTFILES_DIR/terminal/warp-settings.toml" ]; then
  if [[ "$(uname)" == "Darwin" ]]; then WARP_CFG="$HOME/.warp/settings.toml"
  else WARP_CFG="${XDG_CONFIG_HOME:-$HOME/.config}/warp-terminal/settings.toml"; fi
  if [ ! -f "$WARP_CFG" ]; then
    mkdir -p "$(dirname "$WARP_CFG")"
    sed "s#__HOME__#$HOME#g" "$DOTFILES_DIR/terminal/warp-settings.toml" > "$WARP_CFG"
    echo "  🖥️  Warp settings installed → $WARP_CFG"
  else
    echo "  ✅ Warp settings exist — left as-is ($WARP_CFG)"
  fi
fi

###############################################################################
# 8c. Bauhaus app icons: one design language for every launcher — colored tiles, gray
#     glyphs. Jost (open Futura revival) is for the --labels variant. Opt-in: icons change
#     how the whole desktop looks, so ask. BAUHAUS_ICONS=yes|no|ask (default ask; with no
#     terminal to ask on, "ask" means no). macOS extras (Dock tiles + re-apply after app
#     updates) are a second question: BAUHAUS_MAC_EXTRAS=yes|no|ask.
###############################################################################
ask_yes_no() {   # $1 = env value (yes|no|ask), $2 = prompt; returns 0 for yes
  case "$1" in
    yes) return 0 ;;
    no)  return 1 ;;
  esac
  if [ -t 0 ]; then
    local ans; read -r "ans?  🎨 $2 [y/N] "
    [[ "$ans" == [yY]* ]]
  else
    return 1
  fi
}

BAUHAUS_ICONS="${BAUHAUS_ICONS:-ask}"
BAUHAUS_MAC_EXTRAS="${BAUHAUS_MAC_EXTRAS:-ask}"
if [[ "$OS" == "Darwin" ]]; then
  # macOS 13+ "App Management" (Privacy & Security) can block writes into other vendors' .app
  # bundles for the terminal/agent doing it — the icon swap is untested there. Still opt-in.
  _macver="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1)"
  if [ "${_macver:-0}" -ge 13 ] 2>/dev/null; then
    echo "  ⚠️  macOS $_macver: writing icons into other apps' bundles may be blocked by Privacy & Security →"
    echo "     App Management (grant it to your terminal first). Untested on macOS ≥ 13 — default is NO."
  fi
  if ask_yes_no "$BAUHAUS_ICONS" "Use the new Bauhaus app icons on this Mac?"; then
    python3 "$DOTFILES_DIR/custom_scripts/bauhaus_icons.py" --mac \
      && echo "  🎨 Bauhaus app icons applied (one sudo prompt for root-owned apps)" \
      || echo "  ⚠️  Bauhaus icons failed — undo any partial change with: bauhaus_icons.py --mac --undo"
    if ask_yes_no "$BAUHAUS_MAC_EXTRAS" "Also swap the Dock tiles and re-apply icons after app updates?"; then
      python3 "$DOTFILES_DIR/custom_scripts/bauhaus_icons.py" --mac-dock >/dev/null \
        && python3 "$DOTFILES_DIR/custom_scripts/bauhaus_icons.py" --mac-watch >/dev/null \
        && echo "  🎨 Dock tiles swapped; icons re-apply after app updates (undo: --mac-dock --undo / --mac-watch --undo)"
    fi
  else
    echo "  ⏭️  Bauhaus icons skipped (BAUHAUS_ICONS=yes ./install.sh, or custom_scripts/bauhaus_icons.py --mac)"
  fi
elif [ "$IS_WSL" = 0 ] && command -v gsettings >/dev/null 2>&1; then
  if ask_yes_no "$BAUHAUS_ICONS" "Use the new Bauhaus app icons on this desktop?"; then
    JOST="$HOME/.local/share/fonts/jost/Jost.ttf"
    if [ ! -f "$JOST" ]; then
      mkdir -p "$(dirname "$JOST")"
      curl -fsSL -o "$JOST" 'https://github.com/google/fonts/raw/main/ofl/jost/Jost%5Bwght%5D.ttf' \
        && fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || echo "  ⚠️  Jost font download failed"
    fi
    python3 "$DOTFILES_DIR/custom_scripts/bauhaus_icons.py" >/dev/null \
      && echo "  🎨 Bauhaus app icons applied (custom_scripts/bauhaus_icons.py)"
  else
    echo "  ⏭️  Bauhaus icons skipped (BAUHAUS_ICONS=yes ./install.sh, or custom_scripts/bauhaus_icons.py)"
  fi
fi

###############################################################################
# 9. Secrets check (keys live in ~/.secrets, outside any repo)
###############################################################################
echo ""
echo "🔑 Secrets..."
if [ -f "$HOME/.secrets" ]; then
  echo "  ✅ ~/.secrets present (sourced by zshrc)"
else
  if [ -f "$DOTFILES_DIR/.secrets.sample" ]; then
    cp "$DOTFILES_DIR/.secrets.sample" "$HOME/.secrets"
    chmod 600 "$HOME/.secrets"
    echo "  📝 Seeded ~/.secrets from .secrets.sample — now FILL IN the real values (keys are empty)."
  else
    echo "  ⚠️  ~/.secrets MISSING — copy it from your password manager / old machine, then: chmod 600 ~/.secrets"
  fi
  echo "      API keys live there only; they are deliberately NOT in this repo."
fi

###############################################################################
# Done
###############################################################################
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅  Dotfiles installed successfully!           ║"
echo "║   👉  Run: source ~/.zshrc                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
