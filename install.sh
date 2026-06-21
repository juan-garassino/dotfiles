#!/bin/zsh

###############################################################################
# 🛠️  install.sh — Dotfiles installer (macOS + Linux)
# Run from inside ~/Code/000-config/001-dotfiles/
###############################################################################

set -e
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

OS="$(uname)"   # Darwin | Linux
PM=""           # Linux package manager
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

backup() {
  local target=$1
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    mv "$target" "$target.backup"
    echo "  📦 Backed up $target → $target.backup"
  fi
}

symlink() {
  local file=$1
  local link=$2
  if [ ! -e "$link" ]; then
    ln -s "$file" "$link"
    echo "  🔗 Linked $link"
  else
    echo "  ✅ Already linked: $link"
  fi
}

###############################################################################
# 0. Platform packages — macOS: Homebrew · Linux: apt/dnf (adapted from Le Wagon)
###############################################################################
echo "🧰 Platform packages ($OS${PM:+/$PM})..."

if [ "$OS" = "Darwin" ]; then
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "  📦 Installing Command Line Tools (accept the GUI prompt)..."
    xcode-select --install || true
  fi
  if ! command -v brew >/dev/null 2>&1; then
    echo "  🍺 Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    [ -f /opt/homebrew/bin/brew ] && eval "$(/opt/homebrew/bin/brew shellenv)"
    [ -f /usr/local/bin/brew ]    && eval "$(/usr/local/bin/brew shellenv)"
  fi

elif [ "$OS" = "Linux" ]; then
  pkglist() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$1" 2>/dev/null; }
  if [ "$PM" = "apt" ]; then
    echo "  📦 apt: core tools + pyenv build deps..."
    sudo apt-get update -y
    pkglist "$DOTFILES_DIR/packages/apt.txt" | xargs -r sudo apt-get install -y || echo "  ⚠️  some apt packages failed"
    if ! command -v gh >/dev/null 2>&1; then
      echo "  📦 GitHub CLI (apt repo)..."
      curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
      echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
      sudo apt-get update -y && sudo apt-get install -y gh
    fi
    if ! command -v code >/dev/null 2>&1; then
      echo "  📦 VS Code (Microsoft apt repo)..."
      wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/ms.gpg
      sudo install -D -o root -g root -m 644 /tmp/ms.gpg /etc/apt/keyrings/packages.microsoft.gpg && rm -f /tmp/ms.gpg
      echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list >/dev/null
      sudo apt-get update -y && sudo apt-get install -y code
    fi
  elif [ "$PM" = "dnf" ] || [ "$PM" = "yum" ]; then
    echo "  📦 $PM: core tools + pyenv build deps..."
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
  # pyenv (git clone — no brew on Linux)
  if [ ! -d "$HOME/.pyenv" ]; then
    echo "  📦 pyenv + pyenv-virtualenv (git)..."
    git clone --quiet https://github.com/pyenv/pyenv.git "$HOME/.pyenv"
    git clone --quiet https://github.com/pyenv/pyenv-virtualenv.git "$HOME/.pyenv/plugins/pyenv-virtualenv"
  fi
  # uv (official installer)
  command -v uv >/dev/null 2>&1 || { echo "  📦 uv..."; curl -LsSf https://astral.sh/uv/install.sh | sh; }
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
link_map=(
  "shell/zshrc:$HOME/.zshrc"
  "shell/zshenv:$HOME/.zshenv"
  "shell/zprofile:$HOME/.zprofile"
  "shell/aliases:$HOME/.aliases"
  "git/gitconfig:$HOME/.gitconfig"
  "git/gitconfig-personal:$HOME/.gitconfig-personal"
  "git/gitconfig-work:$HOME/.gitconfig-work"
  "prompt/p10k.zsh:$HOME/.p10k.zsh"
)
for pair in "${link_map[@]}"; do
  src="${pair%%:*}"; dst="${pair#*:}"
  backup "$dst"
  symlink "$DOTFILES_DIR/$src" "$dst"
done

###############################################################################
# 2. SSH config
###############################################################################
echo ""
echo "🔐 SSH config..."
if [[ "$(uname)" == "Darwin" ]]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  backup ~/.ssh/config
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
  backup ~/.ssh/config
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

if [[ "$(uname)" == "Darwin" ]]; then
  CODE_PATH=~/Library/Application\ Support/Code/User
  CURSOR_PATH=~/Library/Application\ Support/Cursor/User
else
  CODE_PATH=~/.config/Code/User
  CURSOR_PATH=~/.config/Cursor/User
  [ ! -e "$CODE_PATH" ] && CODE_PATH=~/.vscode-server/data/Machine
fi

for editor_path in "$CODE_PATH" "$CURSOR_PATH"; do
  if [ -d "$editor_path" ]; then
    backup "$editor_path/settings.json"
    symlink "$DOTFILES_DIR/editor/settings.json" "$editor_path/settings.json"
  fi
done

###############################################################################
# 4. zsh plugins
###############################################################################
echo ""
echo "🔌 zsh plugins..."

ZSH_PLUGINS_DIR="$HOME/.oh-my-zsh/custom/plugins"
mkdir -p "$ZSH_PLUGINS_DIR"

if [ ! -d "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting" ]; then
  echo "  📦 Installing zsh-syntax-highlighting..."
  git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_PLUGINS_DIR/zsh-syntax-highlighting"
else
  echo "  ✅ zsh-syntax-highlighting already installed"
fi

if [ ! -d "$ZSH_PLUGINS_DIR/zsh-autosuggestions" ]; then
  echo "  📦 Installing zsh-autosuggestions..."
  git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "$ZSH_PLUGINS_DIR/zsh-autosuggestions"
else
  echo "  ✅ zsh-autosuggestions already installed"
fi

###############################################################################
# 5. Homebrew essentials
###############################################################################
echo ""
echo "🍺 Checking Homebrew essentials..."

if [ "$OS" = "Darwin" ]; then
  BREW_PACKAGES=(gh direnv uv pyenv)
  for pkg in "${BREW_PACKAGES[@]}"; do
    if ! command -v "$pkg" &>/dev/null; then
      echo "  📦 Installing $pkg..."
      brew install "$pkg"
    else
      echo "  ✅ $pkg already installed"
    fi
  done
else
  echo "  ⏭️  Linux — gh/direnv/uv/pyenv handled in step 0 (apt/dnf + git + curl)"
fi

###############################################################################
# 6. Homebrew bundle — full toolchain (pyenv, uv, docker, minikube, postgres, fonts…)
###############################################################################
echo ""
echo "🍺 Restoring full Homebrew bundle..."
if [ "$OS" = "Darwin" ] && command -v brew &>/dev/null && [ -f "$DOTFILES_DIR/packages/Brewfile" ]; then
  brew bundle --file="$DOTFILES_DIR/packages/Brewfile" || echo "  ⚠️  Some bundle entries failed — review output above"
else
  echo "  ⏭️  Not macOS / no brew — skipping Brewfile (Linux uses packages/apt.txt|dnf.txt)"
fi

###############################################################################
# 7. Oh-My-Zsh + Powerlevel10k
###############################################################################
echo ""
echo "🎨 Oh-My-Zsh + Powerlevel10k..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  echo "  📦 Installing Oh-My-Zsh..."
  RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
  echo "  ✅ Oh-My-Zsh present"
fi
if [ ! -d "$HOME/.powerlevel10k" ]; then
  echo "  📦 Installing Powerlevel10k..."
  git clone --quiet --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.powerlevel10k"
else
  echo "  ✅ Powerlevel10k present"
fi

###############################################################################
# 8. Claude Code config (statusline symlink + settings template)
###############################################################################
echo ""
echo "🤖 Claude Code config..."
mkdir -p "$HOME/.claude"
backup ~/.claude/statusline-command.sh
symlink "$DOTFILES_DIR/claude/statusline-command.sh" ~/.claude/statusline-command.sh
if [ -f "$DOTFILES_DIR/claude/settings.json" ]; then
  if [ ! -f "$HOME/.claude/settings.json" ]; then
    cp "$DOTFILES_DIR/claude/settings.json" "$HOME/.claude/settings.json"
    echo "  🔗 Installed Claude settings.json template (machine secrets go in env via ~/.secrets, never here)"
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
