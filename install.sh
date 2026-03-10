#!/bin/zsh

###############################################################################
# 🛠️  install.sh — Dotfiles installer
# Run from inside ~/Code/001-config/001-dotfiles/
###############################################################################

set -e
DOTFILES_DIR="$(cd "$(dirname "$0")" && pwd)"

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
# 1. Symlink dotfiles
###############################################################################
echo "📂 Symlinking dotfiles..."

SKIP_FILES=("install.sh" "git_setup.sh" "README.md" "settings.json" "config" "*.log")

for name in "$DOTFILES_DIR"/*; do
  base=$(basename "$name")

  # skip directories, .git, and excluded files
  [ -d "$name" ] && continue
  [[ "$base" == .git* ]] && continue
  [[ "$base" == *.sh ]] && continue
  [[ "$base" == *.log ]] && continue
  [[ "$base" == "README.md" ]] && continue
  [[ "$base" == "settings.json" ]] && continue
  [[ "$base" == "config" ]] && continue

  target="$HOME/.$base"
  backup "$target"
  symlink "$DOTFILES_DIR/$base" "$target"
done

###############################################################################
# 2. SSH config
###############################################################################
echo ""
echo "🔐 SSH config..."
if [[ "$(uname)" == "Darwin" ]]; then
  backup ~/.ssh/config
  symlink "$DOTFILES_DIR/config" ~/.ssh/config

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
    symlink "$DOTFILES_DIR/settings.json" "$editor_path/settings.json"
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

BREW_PACKAGES=(gh direnv uv pyenv)
for pkg in "${BREW_PACKAGES[@]}"; do
  if ! command -v "$pkg" &>/dev/null; then
    echo "  📦 Installing $pkg..."
    brew install "$pkg"
  else
    echo "  ✅ $pkg already installed"
  fi
done

###############################################################################
# Done
###############################################################################
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║   ✅  Dotfiles installed successfully!           ║"
echo "║   👉  Run: source ~/.zshrc                       ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
