#!/bin/zsh
###############################################################################
# 🖥️ macos_defaults.sh — the system tweaks your muscle memory depends on.
#
# NOT run by install.sh (it changes system behaviour + some settings prompt) —
# run deliberately once on the new Mac, MIGRATION.md Phase 4:  zsh macos_defaults.sh
# Every write documents its stock default; nothing here is irreversible.
# (Le Wagon lists these as optional cherry-picks; this is the curated set.)
###############################################################################
[ "$(uname)" = Darwin ] || { echo "macOS only"; exit 0; }
echo "🖥️  Applying macOS defaults..."

# Keyboard — fast key repeat + short delay (the dev muscle-memory ones; stock 6/25)
defaults write NSGlobalDomain KeyRepeat -int 2
defaults write NSGlobalDomain InitialKeyRepeat -int 15
defaults write NSGlobalDomain ApplePressAndHoldEnabled -bool false  # repeat, not accent popup

# Screenshots → Desktop, PNG (stock: Desktop/PNG already, but pin it)
defaults write com.apple.screencapture location "${HOME}/Desktop"
defaults write com.apple.screencapture type png

# Finder — show all extensions / path bar / hidden files / POSIX path in title
defaults write NSGlobalDomain AppleShowAllExtensions -bool true
defaults write com.apple.finder ShowPathbar -bool true
defaults write com.apple.finder AppleShowAllFiles -bool true
defaults write com.apple.finder _FXShowPosixPathInTitle -bool true
defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"   # search current folder

# Save/print panels expanded by default
defaults write NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults write NSGlobalDomain PMPrintingExpandedStateForPrint -bool true

# Dock — snappier autohide, no recent-apps section
defaults write com.apple.dock autohide-time-modifier -float 0.15
defaults write com.apple.dock show-recents -bool false

killall Finder Dock SystemUIServer 2>/dev/null
echo "✅ Applied. A few (key-repeat) need a logout/restart to fully take."
