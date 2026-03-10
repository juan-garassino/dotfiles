# alias pth='/Applications/Cursor.app/Contents/MacOS/Cursor'
# #########################################
# # Powerlevel10k Instant Prompt         #
# #########################################
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

# #########################################
# # Oh-My-Zsh Configuration              #
# #########################################
# ZSH=$HOME/.oh-my-zsh
# #ZSH_THEME="agnoster"
# plugins=(git gitfast last-working-dir common-aliases zsh-syntax-highlighting history-substring-search pyenv direnv)
# eval "$(direnv hook zsh)"
# export HOMEBREW_NO_ANALYTICS=1
# ZSH_DISABLE_COMPFIX=true
# source "${ZSH}/oh-my-zsh.sh"
# unalias rm

# #########################################
# # Path and Environment Settings        #
# #########################################
# export PATH="${HOME}/.rbenv/bin:${PATH}"
# export PATH="./bin:./node_modules/.bin:${PATH}:/usr/local/sbin"
# export PATH="$PATH:/Users/juan-garassino/.local/bin"
# export LANG=en_US.UTF-8
# export LC_ALL=en_US.UTF-8
# export BUNDLER_EDITOR=code
# #export PATH="$PATH:/Applications/Cursor.app/Contents/MacOS/Cursor" 


# #########################################
# # Version Managers                     #
# #########################################
# # rbenv
# type -a rbenv > /dev/null && eval "$(rbenv init -)"

# # pyenv
# export PYENV_VIRTUALENV_DISABLE_PROMPT=1
# type -a pyenv > /dev/null && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)" && RPROMPT+='[🐍 $(pyenv_prompt_info)]'

# # nvm
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# # nvm use
# autoload -U add-zsh-hook
# load-nvmrc() {
#   if nvm -v &> /dev/null; then
#     local node_version="$(nvm version)"
#     local nvmrc_path="$(nvm_find_nvmrc)"

#     if [ -n "$nvmrc_path" ]; then
#       local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")

#       if [ "$nvmrc_node_version" = "N/A" ]; then
#         nvm install
#       elif [ "$nvmrc_node_version" != "$node_version" ]; then
#         nvm use --silent
#       fi
#     elif [ "$node_version" != "$(nvm version default)" ]; then
#       nvm use default --silent
#     fi
#   fi
# }
# type -a nvm > /dev/null && add-zsh-hook chpwd load-nvmrc
# type -a nvm > /dev/null && load-nvmrc

# #########################################
# # Custom Aliases and Configurations    #
# #########################################
# [[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# #########################################
# # Google Cloud SDK                     #
# #########################################
# if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]; then . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'; fi
# if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc' ]; then . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'; fi

# # export GOOGLE_APPLICATION_CREDENTIALS=/Users/juan-garassino/Code/001-config/002-gcp-credentials/myplayground-garassino-8a4f1f31908f.json
# export GOOGLE_APPLICATION_CREDENTIALS=/Users/juan-garassino/Code/003-personal/007-my-challenges-boilerplates/taxifare_boilerplate/project/service_account_key/taxifare-api-container-39031a95fad7.json

# #########################################
# # Spark Configuration                  #
# #########################################
# export SPARK_HOME=/Users/juan-garassino/spark/spark-3.5.1-bin-hadoop3
# export PATH=$PATH:$SPARK_HOME/bin

# #########################################
# # Powerlevel10k Theme                  #
# #########################################
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# source ~/.powerlevel10k/powerlevel10k.zsh-theme

# #########################################
# # Kubectl and Minikube Completion      #
# #########################################
# [[ $commands[kubectl] ]] && source <(kubectl completion zsh)
# [[ $commands[minikube] ]] && source <(minikube completion zsh)

# # Add other custom functions herealias pth='/Applications/Cursor.app/Contents/MacOS/Cursor'

# # Added by Windsurf
# export PATH="/Users/juan-garassino/.codeium/windsurf/bin:$PATH"

# # bun
# export BUN_INSTALL="$HOME/Library/Application Support/reflex/bun"
# export PATH="$BUN_INSTALL/bin:$PATH"

# [[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"


# # CUSTOM PYTHON VENV MANAGEMENT FUNCTIONS

# #########################################
# # Custom Functions                     #
# #########################################

# # AI-powered Git Commit Function
# # This function uses AI to generate commit messages based on staged changes

# # Check if the custom AI commit script exists at the given path
# if [ -f "$HOME/Code/001-config/001-dotfiles/custom_scripts/ai_git_commit.sh" ]; then
#     # Source the script if it exists
#     source "$HOME/Code/001-config/001-dotfiles/custom_scripts/ai_git_commit.sh"
# fi

# # ────────────────────────────────────────────────
# # 1) Use a project-local uv venv with pyenv’s Python
# # Usage:
# #   usevenv [python_version] [venv_name] [reset]
# # Examples:
# #   usevenv 3.10.6            → .venv (Python 3.10.6)
# #   usevenv 3.11.9 .venv311   → .venv311 (Python 3.11.9)
# #   usevenv 3.10.6 .venv reset → wipe & recreate .venv
# # ────────────────────────────────────────────────
# usevenv() {
#   local version=${1:-3.10.6}
#   local venv_name=${2:-.venv}
#   local reset=${3:-false}

#   deactivate 2>/dev/null || true
#   pyenv shell "$version"

#   if [ "$reset" = "reset" ]; then
#     echo "⚠ Resetting $venv_name..."
#     rm -rf "$venv_name"
#     uv venv "$venv_name" --python "$(pyenv which python)"
#   elif [ ! -d "$venv_name" ]; then
#     echo "ℹ Creating $venv_name with Python $version..."
#     uv venv "$venv_name" --python "$(pyenv which python)"
#   fi

#   source "$venv_name/bin/activate"
#   echo "$version" > .python-version

#   echo "▶ Using uv venv '$venv_name' (Python $(python --version | awk '{print $2}'))"
#   echo "VIRTUAL_ENV=$VIRTUAL_ENV"
# }

# # ────────────────────────────────────────────────
# # 2) Use a pyenv-managed virtualenv
# # Usage:
# #   usepyenv <env_name>
# # Example:
# #   usepyenv olist
# # ────────────────────────────────────────────────
# usepyenv() {
#   local envname=$1
#   if [ -z "$envname" ]; then
#     echo "⚠ Usage: usepyenv <env_name>"
#     return 1
#   fi

#   deactivate 2>/dev/null || true
#   pyenv activate "$envname"
#   echo "$envname" > .python-version

#   echo "▶ Using pyenv venv '$envname' (Python $(python --version | awk '{print $2}'))"
#   echo "VIRTUAL_ENV=$VIRTUAL_ENV"
#   echo "⚠ Remember: uv requires --active with pyenv venvs"
#   echo "   uv run --active python -m ml.demo_estimators"
# }

# # ────────────────────────────────────────────────
# # 3) List available environments
# # Shows pyenv versions/envs and local project venvs
# # Usage: lsenvs
# # ────────────────────────────────────────────────
# lsenvs() {
#   echo "📦 Pyenv versions and virtualenvs:"
#   pyenv versions --bare | sed 's/^/  - /'

#   echo ""
#   echo "📂 Project-local venvs:"
#   for v in .venv*; do
#     if [ -d "$v" ]; then
#       local pyver=$(grep -E 'version' "$v/pyvenv.cfg" 2>/dev/null | sed 's/ *version *= *//')
#       echo "  - $v ($pyver)"
#     fi
#   done

#   echo ""
#   echo "⭐ Currently active:"
#   echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
#   python --version 2>/dev/null || echo "  - Python: <none>"
# }

# HERE

# #######################################################################
# # 🖥️ Aliases
# #######################################################################
# alias pth='/Applications/Cursor.app/Contents/MacOS/Cursor'

# #######################################################################
# # ⚡ Powerlevel10k Instant Prompt
# #######################################################################
# if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
#   source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
# fi

# #######################################################################
# # ⚙️ Oh-My-Zsh Configuration
# #######################################################################
# ZSH=$HOME/.oh-my-zsh
# plugins=(git gitfast last-working-dir common-aliases zsh-syntax-highlighting history-substring-search pyenv direnv)
# eval "$(direnv hook zsh)"
# export HOMEBREW_NO_ANALYTICS=1
# ZSH_DISABLE_COMPFIX=true
# source "${ZSH}/oh-my-zsh.sh"
# unalias rm

# #######################################################################
# # 📂 Path and Environment Settings
# #######################################################################
# export PATH="${HOME}/.rbenv/bin:${PATH}"
# export PATH="./bin:./node_modules/.bin:${PATH}:/usr/local/sbin"
# export PATH="$PATH:/Users/juan-garassino/.local/bin"
# export LANG=en_US.UTF-8
# export LC_ALL=en_US.UTF-8
# export BUNDLER_EDITOR=code

# #######################################################################
# # 🐍 / 💎 / 🟢 Version Managers
# #######################################################################

# # rbenv (Ruby)
# type -a rbenv > /dev/null && eval "$(rbenv init -)"

# # pyenv (Python)
# export PYENV_VIRTUALENV_DISABLE_PROMPT=1
# type -a pyenv > /dev/null && \
#   eval "$(pyenv init -)" && \
#   eval "$(pyenv virtualenv-init -)" && \
#   RPROMPT+='[🐍 $(pyenv_prompt_info)]'

# # nvm (Node.js)
# export NVM_DIR="$HOME/.nvm"
# [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
# [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# # auto-load .nvmrc on cd
# autoload -U add-zsh-hook
# load-nvmrc() {
#   if nvm -v &> /dev/null; then
#     local node_version="$(nvm version)"
#     local nvmrc_path="$(nvm_find_nvmrc)"
#     if [ -n "$nvmrc_path" ]; then
#       local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")
#       if [ "$nvmrc_node_version" = "N/A" ]; then
#         nvm install
#       elif [ "$nvmrc_node_version" != "$node_version" ]; then
#         nvm use --silent
#       fi
#     elif [ "$node_version" != "$(nvm version default)" ]; then
#       nvm use default --silent
#     fi
#   fi
# }
# type -a nvm > /dev/null && add-zsh-hook chpwd load-nvmrc
# type -a nvm > /dev/null && load-nvmrc

# #######################################################################
# # 📝 Custom Aliases
# #######################################################################
# [[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# #######################################################################
# # ☁️ Google Cloud SDK
# #######################################################################
# if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]; then 
#   . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
# fi
# if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc' ]; then 
#   . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
# fi
# export GOOGLE_APPLICATION_CREDENTIALS=/Users/juan-garassino/Code/003-personal/007-my-challenges-boilerplates/taxifare_boilerplate/project/service_account_key/taxifare-api-container-39031a95fad7.json

# #######################################################################
# # 🔥 Spark Configuration
# #######################################################################
# export SPARK_HOME=/Users/juan-garassino/spark/spark-3.5.1-bin-hadoop3
# export PATH=$PATH:$SPARK_HOME/bin

# #######################################################################
# # 🎨 Powerlevel10k Theme
# #######################################################################
# [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# source ~/.powerlevel10k/powerlevel10k.zsh-theme

# #######################################################################
# # ☸️ Kubectl & Minikube Completion
# #######################################################################
# [[ $commands[kubectl] ]] && source <(kubectl completion zsh)
# [[ $commands[minikube] ]] && source <(minikube completion zsh)

# #######################################################################
# # 🌀 Windsurf & Bun
# #######################################################################
# export PATH="/Users/juan-garassino/.codeium/windsurf/bin:$PATH"
# export BUN_INSTALL="$HOME/Library/Application Support/reflex/bun"
# export PATH="$BUN_INSTALL/bin:$PATH"

# #######################################################################
# # 🎛️ Kiro Integration
# #######################################################################
# [[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

# #######################################################################
# # 🛠️ Custom Functions
# #######################################################################

# # editrc → open ~/.zshrc in editor
# editrc() {
#   ${EDITOR:-nano} ~/.zshrc
# }

# # reloadrc → reload ~/.zshrc
# reloadrc() {
#   source ~/.zshrc
#   echo "🔄 Reloaded ~/.zshrc"
# }

# #######################################################################
# # usevenv → manage uv venvs with pyenv Python
# #######################################################################
# usevenv() {
#   local version=${1:-3.10.6}
#   local venv_name=${2:-.venv}
#   local reset=${3:-false}

#   deactivate 2>/dev/null || true
#   pyenv shell "$version"

#   if [ "$reset" = "reset" ]; then
#     echo "⚠️ Resetting $venv_name..."
#     rm -rf "$venv_name"
#     uv venv "$venv_name" --python "$(pyenv which python)"
#   elif [ ! -d "$venv_name" ]; then
#     echo "ℹ️ Creating $venv_name with Python $version..."
#     uv venv "$venv_name" --python "$(pyenv which python)"
#   fi

#   source "$venv_name/bin/activate"
#   echo "$version" > .python-version

#   echo "▶ Using uv venv '$venv_name' (🐍 $(python --version | awk '{print $2}'))"
#   echo "VIRTUAL_ENV=$VIRTUAL_ENV"
# }

# #######################################################################
# # usepyenv → activate a pyenv virtualenv
# #######################################################################
# usepyenv() {
#   local envname=$1
#   if [ -z "$envname" ]; then
#     echo "⚠️ Usage: usepyenv <env_name>"
#     return 1
#   fi

#   deactivate 2>/dev/null || true
#   pyenv activate "$envname"
#   echo "$envname" > .python-version

#   echo "▶ Using pyenv venv '$envname' (🐍 $(python --version | awk '{print $2}'))"
#   echo "VIRTUAL_ENV=$VIRTUAL_ENV"
#   echo "⚠️ uv requires --active with pyenv venvs"
# }

# #######################################################################
# # lsenvs → list pyenv versions + local venvs
# #######################################################################
# lsenvs() {
#   echo "📦 Pyenv versions and virtualenvs:"
#   pyenv versions --bare | sed 's/^/  - /'

#   echo ""
#   echo "📂 Project-local venvs:"
#   for v in .venv*; do
#     if [ -d "$v" ]; then
#       local pyver=$(grep -E 'version' "$v/pyvenv.cfg" 2>/dev/null | sed 's/ *version *= *//')
#       echo "  - $v ($pyver)"
#     fi
#   done

#   echo ""
#   echo "⭐ Currently active:"
#   echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
#   python --version 2>/dev/null || echo "  - Python: <none>"
# }

# #######################################################################
# # autoenv → activate .venv OR pyenv venv (mutually exclusive)
# #######################################################################
# autoenv_activate() {
#   # Case 1: Local project .venv takes priority
#   if [ -f ".venv/bin/activate" ]; then
#     # If we're not already inside this .venv, switch to it
#     if [ "$VIRTUAL_ENV" != "$(pwd)/.venv" ]; then
#       deactivate 2>/dev/null || true
#       pyenv deactivate 2>/dev/null || true
#       source .venv/bin/activate
#       echo "▶ Activated local .venv (🐍 $(python --version 2>/dev/null))"
#     fi
#     return
#   fi

#   # Case 2: Use .python-version with pyenv
#   if [ -f ".python-version" ]; then
#     local ver
#     ver=$(cat .python-version)

#     # If it's a pyenv virtualenv (e.g. "olistV2")
#     if pyenv versions --bare | grep -qx "$ver"; then
#       if [ "$VIRTUAL_ENV" != "$(pyenv prefix "$ver")" ]; then
#         deactivate 2>/dev/null || true
#         source deactivate 2>/dev/null || true  # catch if .venv was active
#         pyenv activate "$ver"
#         echo "▶ Activated pyenv env: $ver (🐍 $(python --version 2>/dev/null))"
#       fi
#       return
#     fi

#     # If it's a plain version (e.g. "3.10.6"), just set pyenv shell
#     if [[ "$ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
#       deactivate 2>/dev/null || true
#       source deactivate 2>/dev/null || true
#       pyenv shell "$ver"
#       echo "▶ Using pyenv Python $ver (🐍 $(python --version 2>/dev/null))"
#       return
#     fi
#   fi

#   # Case 3: Fallback → global pyenv (nothing special)
#   deactivate 2>/dev/null || true
#   source deactivate 2>/dev/null || true
#   pyenv deactivate 2>/dev/null || true
#   echo "▶ No .venv or .python-version, using global pyenv ($(python --version 2>/dev/null))"
# }

# # Hook into cd
# cd() {
#   builtin cd "$@" || return
#   autoenv_activate
# }

# #######################################################################
# # Extra Dev & QoL Functions
# #######################################################################

# # 1) venvinfo → show details about active environment
# venvinfo() {
#   echo "⭐ Environment Info:"
#   echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
#   python --version 2>/dev/null || echo "  - Python: <none>"
#   if [ -n "$VIRTUAL_ENV" ]; then
#     echo "  - Site-packages: $(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)"
#     echo "  - Packages: $(pip list --disable-pip-version-check 2>/dev/null | wc -l | xargs)"
#   fi
# }

# # 2) freezeenv → save current deps to requirements.txt
# freezeenv() {
#   if [ -z "$VIRTUAL_ENV" ]; then
#     echo "⚠️ No active venv to freeze."
#     return 1
#   fi
#   uv pip freeze > requirements.txt
#   echo "📄 Saved requirements.txt from current environment."
# }

# # 3) syncenv → sync deps with requirements.txt
# syncenv() {
#   if [ ! -f requirements.txt ]; then
#     echo "⚠️ No requirements.txt found."
#     return 1
#   fi
#   uv pip sync requirements.txt
#   echo "🔄 Synced environment with requirements.txt."
# }

# # 4) killport <port> → kill process using a given port
# killport() {
#   if [ -z "$1" ]; then
#     echo "⚠️ Usage: killport <port>"
#     return 1
#   fi
#   local pid
#   pid=$(lsof -ti tcp:$1)
#   if [ -n "$pid" ]; then
#     kill -9 $pid && echo "💀 Killed process $pid on port $1"
#   else
#     echo "ℹ️ No process found on port $1"
#   fi
# }

# # 5) mkcd <dir> → make and cd into a directory
# mkcd() {
#   if [ -z "$1" ]; then
#     echo "⚠️ Usage: mkcd <directory>"
#     return 1
#   fi
#   mkdir -p "$1" && cd "$1" || return
# }

# #######################################################################
# # 📖 mycmds → list all custom commands
# #######################################################################

# mycmds() {
#   cat <<'EOF'
# 🛠️  Custom Dev / Python Helpers
# --------------------------------
#   usevenv [ver] [name] [reset]   → Create/use uv venv with pyenv Python
#   usepyenv <env>                 → Activate a pyenv-managed venv
#   lsenvs                         → List pyenv versions + local .venv dirs
#   autoenv (hooked to cd)         → Auto-activate .venv or pyenv env
#   venvinfo                       → Show details about active environment
#   freezeenv                      → Save current deps → requirements.txt
#   syncenv                        → Sync deps with requirements.txt
#   killport <port>                 → Kill process using a given port
#   mkcd <dir>                     → Make and cd into directory

# ⚡ Shell Config Shortcuts
# --------------------------------
#   editrc                         → Open ~/.zshrc in editor
#   reloadrc                       → Reload ~/.zshrc
#   mycmds                         → List these custom commands

# EOF
# }

#######################################################################
# 🖥️ Aliases
#######################################################################
alias pth='/Applications/Cursor.app/Contents/MacOS/Cursor'

#######################################################################
# ⚡ Powerlevel10k Instant Prompt
#######################################################################
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#######################################################################
# ⚙️ Oh-My-Zsh Configuration
#######################################################################
ZSH=$HOME/.oh-my-zsh
plugins=(git gitfast last-working-dir common-aliases zsh-syntax-highlighting history-substring-search pyenv direnv)
eval "$(direnv hook zsh)"
export HOMEBREW_NO_ANALYTICS=1
ZSH_DISABLE_COMPFIX=true
source "${ZSH}/oh-my-zsh.sh"
unalias rm

#######################################################################
# 📂 Path and Environment Settings
#######################################################################
export PATH="${HOME}/.rbenv/bin:${PATH}"
export PATH="./bin:./node_modules/.bin:${PATH}:/usr/local/sbin"
export PATH="$PATH:/Users/juan-garassino/.local/bin"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export BUNDLER_EDITOR=code

#######################################################################
# 🐍 / 💎 / 🟢 Version Managers
#######################################################################

# rbenv (Ruby)
type -a rbenv > /dev/null && eval "$(rbenv init -)"

# pyenv (Python)
export PYENV_VIRTUALENV_DISABLE_PROMPT=1
type -a pyenv > /dev/null && eval "$(pyenv init -)" && eval "$(pyenv virtualenv-init -)"

# nvm (Node.js)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# auto-load .nvmrc on cd
autoload -U add-zsh-hook
load-nvmrc() {
  if nvm -v &> /dev/null; then
    local node_version="$(nvm version)"
    local nvmrc_path="$(nvm_find_nvmrc)"
    if [ -n "$nvmrc_path" ]; then
      local nvmrc_node_version=$(nvm version "$(cat "${nvmrc_path}")")
      if [ "$nvmrc_node_version" = "N/A" ]; then
        nvm install
      elif [ "$nvmrc_node_version" != "$node_version" ]; then
        nvm use --silent
      fi
    elif [ "$node_version" != "$(nvm version default)" ]; then
      nvm use default --silent
    fi
  fi
}
type -a nvm > /dev/null && add-zsh-hook chpwd load-nvmrc
type -a nvm > /dev/null && load-nvmrc

#######################################################################
# 🎨 Powerlevel10k Theme (toggle with USE_P10K)
#######################################################################
USE_P10K=true  # 👉 set to false to disable P10K & pyenv prompt integration

if [ "$USE_P10K" = true ]; then
  # Add pyenv info to right prompt
  RPROMPT+='[🐍 $(pyenv_prompt_info)]'

  # Load Powerlevel10k theme
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
  source ~/.powerlevel10k/powerlevel10k.zsh-theme
else
  # Disable Powerlevel10k and pyenv prompt integration
  powerlevel10k_plugin_unload 2>/dev/null || true
  unset RPROMPT
  echo "⚠️ Powerlevel10k disabled (USE_P10K=false)"
fi

#######################################################################
# 📝 Custom Aliases
#######################################################################
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

#######################################################################
# ☁️ Google Cloud SDK
#######################################################################
if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]; then 
  . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
fi
if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc' ]; then 
  . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
fi
#export GOOGLE_APPLICATION_CREDENTIALS=/Users/juan-garassino/Code/003-personal/007-my-challenges-boilerplates/taxifare_boilerplate/project/service_account_key/taxifare-api-container-39031a95fad7.json
export GOOGLE_APPLICATION_CREDENTIALS=/Users/juan-garassino/Code/002-lewagon/003-my-boilerplates-as-teacher/taxifare_boilerplate/project/service_account_key/taxifare-api-container-39031a95fad7.json
#######################################################################
# 🔥 Spark Configuration
#######################################################################
export SPARK_HOME=/Users/juan-garassino/spark/spark-3.5.1-bin-hadoop3
export PATH=$PATH:$SPARK_HOME/bin

#######################################################################
# ☸️ Kubectl & Minikube Completion
#######################################################################
[[ $commands[kubectl] ]] && source <(kubectl completion zsh)
[[ $commands[minikube] ]] && source <(minikube completion zsh)

#######################################################################
# 🌀 Windsurf & Bun
#######################################################################
export PATH="/Users/juan-garassino/.codeium/windsurf/bin:$PATH"
export BUN_INSTALL="$HOME/Library/Application Support/reflex/bun"
export PATH="$BUN_INSTALL/bin:$PATH"

#######################################################################
# 🎛️ Kiro Integration
#######################################################################
[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

#######################################################################
# 🛠️ Custom Functions
#######################################################################

# editrc → open ~/.zshrc in editor
editrc() {
  ${EDITOR:-nano} ~/.zshrc
}

# reloadrc → reload ~/.zshrc
reloadrc() {
  source ~/.zshrc
  echo "🔄 Reloaded ~/.zshrc"
}

#######################################################################
# usevenv → manage uv venvs with pyenv Python
#######################################################################
usevenv() {
  local version=${1:-3.10.6}
  local venv_name=${2:-.venv}
  local reset=${3:-false}

  deactivate 2>/dev/null || true
  pyenv shell "$version"

  if [ "$reset" = "reset" ]; then
    echo "⚠️ Resetting $venv_name..."
    rm -rf "$venv_name"
    uv venv "$venv_name" --python "$(pyenv which python)"
  elif [ ! -d "$venv_name" ]; then
    echo "ℹ️ Creating $venv_name with Python $version..."
    uv venv "$venv_name" --python "$(pyenv which python)"
  fi

  source "$venv_name/bin/activate"
  echo "$version" > .python-version

  echo "▶ Using uv venv '$venv_name' (🐍 $(python --version | awk '{print $2}'))"
  echo "VIRTUAL_ENV=$VIRTUAL_ENV"
}

#######################################################################
# usepyenv → activate a pyenv virtualenv
#######################################################################
usepyenv() {
  local envname=$1
  if [ -z "$envname" ]; then
    echo "⚠️ Usage: usepyenv <env_name>"
    return 1
  fi

  deactivate 2>/dev/null || true
  pyenv activate "$envname"
  echo "$envname" > .python-version

  echo "▶ Using pyenv venv '$envname' (🐍 $(python --version | awk '{print $2}'))"
  echo "VIRTUAL_ENV=$VIRTUAL_ENV"
  echo "⚠️ uv requires --active with pyenv venvs"
}

#######################################################################
# lsenvs → list pyenv versions + local venvs
#######################################################################
lsenvs() {
  echo "📦 Pyenv versions and virtualenvs:"
  pyenv versions --bare | sed 's/^/  - /'

  echo ""
  echo "📂 Project-local venvs:"
  for v in .venv*; do
    if [ -d "$v" ]; then
      local pyver=$(grep -E 'version' "$v/pyvenv.cfg" 2>/dev/null | sed 's/ *version *= *//')
      echo "  - $v ($pyver)"
    fi
  done

  echo ""
  echo "⭐ Currently active:"
  echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
  python --version 2>/dev/null || echo "  - Python: <none>"
}

#######################################################################
# autoenv → activate .venv OR pyenv venv (mutually exclusive)
#######################################################################
autoenv_activate() {
  # Case 1: Local project .venv takes priority
  if [ -f ".venv/bin/activate" ]; then
    if [ "$VIRTUAL_ENV" != "$(pwd)/.venv" ]; then
      deactivate 2>/dev/null || true
      pyenv deactivate 2>/dev/null || true
      source .venv/bin/activate
      echo "▶ Activated local .venv (🐍 $(python --version 2>/dev/null))"
    fi
    return
  fi

  # Case 2: Use .python-version with pyenv
  if [ -f ".python-version" ]; then
    local ver
    ver=$(cat .python-version)

    if pyenv versions --bare | grep -qx "$ver"; then
      if [ "$VIRTUAL_ENV" != "$(pyenv prefix "$ver")" ]; then
        deactivate 2>/dev/null || true
        source deactivate 2>/dev/null || true
        pyenv activate "$ver"
        echo "▶ Activated pyenv env: $ver (🐍 $(python --version 2>/dev/null))"
      fi
      return
    fi

    if [[ "$ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      deactivate 2>/dev/null || true
      source deactivate 2>/dev/null || true
      pyenv shell "$ver"
      echo "▶ Using pyenv Python $ver (🐍 $(python --version 2>/dev/null))"
      return
    fi
  fi

  # Case 3: Fallback → global pyenv
  deactivate 2>/dev/null || true
  source deactivate 2>/dev/null || true
  pyenv deactivate 2>/dev/null || true
  echo "▶ No .venv or .python-version, using global pyenv ($(python --version 2>/dev/null))"
}

cd() {
  builtin cd "$@" || return
  autoenv_activate
}

#######################################################################
# Extra Dev & QoL Functions
#######################################################################

venvinfo() {
  echo "⭐ Environment Info:"
  echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
  python --version 2>/dev/null || echo "  - Python: <none>"
  if [ -n "$VIRTUAL_ENV" ]; then
    echo "  - Site-packages: $(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)"
    echo "  - Packages: $(pip list --disable-pip-version-check 2>/dev/null | wc -l | xargs)"
  fi
}

freezeenv() {
  if [ -z "$VIRTUAL_ENV" ]; then
    echo "⚠️ No active venv to freeze."
    return 1
  fi
  uv pip freeze > requirements.txt
  echo "📄 Saved requirements.txt from current environment."
}

syncenv() {
  if [ ! -f requirements.txt ]; then
    echo "⚠️ No requirements.txt found."
    return 1
  fi
  uv pip sync requirements.txt
  echo "🔄 Synced environment with requirements.txt."
}

killport() {
  if [ -z "$1" ]; then
    echo "⚠️ Usage: killport <port>"
    return 1
  fi
  local pid
  pid=$(lsof -ti tcp:$1)
  if [ -n "$pid" ]; then
    kill -9 $pid && echo "💀 Killed process $pid on port $1"
  else
    echo "ℹ️ No process found on port $1"
  fi
}

mkcd() {
  if [ -z "$1" ]; then
    echo "⚠️ Usage: mkcd <directory>"
    return 1
  fi
  mkdir -p "$1" && cd "$1" || return
}

#######################################################################
# 📖 mycmds → list all custom commands
#######################################################################
mycmds() {
  cat <<'EOF'
🛠️  Custom Dev / Python Helpers
--------------------------------
  usevenv [ver] [name] [reset]   → Create/use uv venv with pyenv Python
  usepyenv <env>                 → Activate a pyenv-managed venv
  lsenvs                         → List pyenv versions + local .venv dirs
  autoenv (hooked to cd)         → Auto-activate .venv or pyenv env
  venvinfo                       → Show details about active environment
  freezeenv                      → Save current deps → requirements.txt
  syncenv                        → Sync deps with requirements.txt
  killport <port>                → Kill process using a given port
  mkcd <dir>                     → Make and cd into directory

⚡ Shell Config Shortcuts
--------------------------------
  editrc                         → Open ~/.zshrc in editor
  reloadrc                       → Reload ~/.zshrc
  mycmds                         → List these custom commands
EOF
}

# Added by Antigravity
export PATH="/Users/juan-garassino/.antigravity/antigravity/bin:$PATH"
