#######################################################################
# 🖥️  Aliases
#######################################################################
alias pth='/Applications/Cursor.app/Contents/MacOS/Cursor'

#######################################################################
# ⚡ Powerlevel10k Instant Prompt
#######################################################################
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

#######################################################################
# ⚙️  Oh-My-Zsh Configuration
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
# 🎨 Powerlevel10k Theme
#######################################################################
USE_P10K=true  # 👉 set to false to disable P10K

if [ "$USE_P10K" = true ]; then
  RPROMPT+='[🐍 $(pyenv_prompt_info)]'
  [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
  source ~/.powerlevel10k/powerlevel10k.zsh-theme
else
  powerlevel10k_plugin_unload 2>/dev/null || true
  unset RPROMPT
  echo "⚠️  Powerlevel10k disabled (USE_P10K=false)"
fi

#######################################################################
# 📝 Custom Aliases
#######################################################################
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

#######################################################################
# ☁️  Google Cloud SDK
#######################################################################
if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc' ]; then
  . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/path.zsh.inc'
fi
if [ -f '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc' ]; then
  . '/usr/local/Caskroom/google-cloud-sdk/latest/google-cloud-sdk/completion.zsh.inc'
fi

# 🔑 GCP credentials — loaded per context (personal/work), not hardcoded
# Use `workon` or `personal` to activate the right credentials
# export GOOGLE_APPLICATION_CREDENTIALS=...  ← moved to context switchers below

#######################################################################
# 🔥 Spark Configuration
#######################################################################
export SPARK_HOME=/Users/juan-garassino/spark/spark-3.5.1-bin-hadoop3
export PATH=$PATH:$SPARK_HOME/bin

#######################################################################
# ☸️  Kubectl & Minikube Completion
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
# 🎛️  Kiro Integration
#######################################################################
[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

#######################################################################
# 🛠️  Shell Config Helpers
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
# 🐍 Python / venv Helpers
#######################################################################

# usevenv → create or activate a uv venv with a specific pyenv Python
# Usage: usevenv [python_version] [venv_name] [reset]
# Examples:
#   usevenv              → uses 3.10.6, creates .venv
#   usevenv 3.11.4       → uses 3.11.4, creates .venv
#   usevenv 3.10.6 .venv reset  → destroys and recreates .venv
usevenv() {
  local version=${1:-3.10.6}
  local venv_name=${2:-.venv}
  local reset=${3:-false}

  deactivate 2>/dev/null || true
  pyenv shell "$version"

  if [ "$reset" = "reset" ]; then
    echo "⚠️  Resetting $venv_name..."
    rm -rf "$venv_name"
    uv venv "$venv_name" --python "$(pyenv which python)"
  elif [ ! -d "$venv_name" ]; then
    echo "ℹ️  Creating $venv_name with Python $version..."
    uv venv "$venv_name" --python "$(pyenv which python)"
  fi

  source "$venv_name/bin/activate"
  echo "$version" > .python-version

  echo "▶ Using uv venv '$venv_name' (🐍 $(python --version | awk '{print $2}'))"
  echo "VIRTUAL_ENV=$VIRTUAL_ENV"
}

# usepyenv → activate a named pyenv virtualenv
# Usage: usepyenv <env_name>
usepyenv() {
  local envname=$1
  if [ -z "$envname" ]; then
    echo "⚠️  Usage: usepyenv <env_name>"
    return 1
  fi

  deactivate 2>/dev/null || true
  pyenv activate "$envname"
  echo "$envname" > .python-version

  echo "▶ Using pyenv venv '$envname' (🐍 $(python --version | awk '{print $2}'))"
  echo "VIRTUAL_ENV=$VIRTUAL_ENV"
  echo "⚠️  uv requires --active with pyenv venvs"
}

# lsenvs → list all pyenv versions and local .venv dirs
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

# venvinfo → show details about the active environment
venvinfo() {
  echo "⭐ Environment Info:"
  echo "  - VIRTUAL_ENV=${VIRTUAL_ENV:-<none>}"
  python --version 2>/dev/null || echo "  - Python: <none>"
  if [ -n "$VIRTUAL_ENV" ]; then
    echo "  - Site-packages: $(python -c 'import site; print(site.getsitepackages()[0])' 2>/dev/null)"
    echo "  - Packages: $(pip list --disable-pip-version-check 2>/dev/null | wc -l | xargs)"
  fi
}

# freezeenv → save current deps to requirements.txt
freezeenv() {
  if [ -z "$VIRTUAL_ENV" ]; then
    echo "⚠️  No active venv to freeze."
    return 1
  fi
  uv pip freeze > requirements.txt
  echo "📄 Saved requirements.txt from current environment."
}

# syncenv → sync environment with requirements.txt
syncenv() {
  if [ ! -f requirements.txt ]; then
    echo "⚠️  No requirements.txt found."
    return 1
  fi
  uv pip sync requirements.txt
  echo "🔄 Synced environment with requirements.txt."
}

# envcheck → compare .env vs .env.example and show missing vars
# Usage: envcheck
envcheck() {
  if [ ! -f ".env.example" ]; then
    echo "⚠️  No .env.example found in current directory."
    return 1
  fi
  if [ ! -f ".env" ]; then
    echo "⚠️  No .env found — you may need to create one from .env.example"
    return 1
  fi

  local missing=()
  while IFS= read -r line; do
    # skip comments and empty lines
    [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
    local key="${line%%=*}"
    if ! grep -q "^${key}=" .env 2>/dev/null; then
      missing+=("$key")
    fi
  done < .env.example

  if [ ${#missing[@]} -eq 0 ]; then
    echo "✅ .env is complete — all keys from .env.example are present."
  else
    echo "❌ Missing keys in .env:"
    for k in "${missing[@]}"; do
      echo "  - $k"
    done
  fi
}

#######################################################################
# 🤖 autoenv → auto-activate .venv or pyenv on cd
#######################################################################
autoenv_activate() {
  if [ -f ".venv/bin/activate" ]; then
    if [ "$VIRTUAL_ENV" != "$(pwd)/.venv" ]; then
      deactivate 2>/dev/null || true
      pyenv deactivate 2>/dev/null || true
      source .venv/bin/activate
      echo "▶ Activated local .venv (🐍 $(python --version 2>/dev/null))"
    fi
    return
  fi

  if [ -f ".python-version" ]; then
    local ver
    ver=$(cat .python-version)

    if pyenv versions --bare | grep -qx "$ver"; then
      if [ "$VIRTUAL_ENV" != "$(pyenv prefix "$ver")" ]; then
        deactivate 2>/dev/null || true
        pyenv activate "$ver"
        echo "▶ Activated pyenv env: $ver (🐍 $(python --version 2>/dev/null))"
      fi
      return
    fi

    if [[ "$ver" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
      deactivate 2>/dev/null || true
      pyenv shell "$ver"
      echo "▶ Using pyenv Python $ver (🐍 $(python --version 2>/dev/null))"
      return
    fi
  fi

  deactivate 2>/dev/null || true
  pyenv deactivate 2>/dev/null || true
  echo "▶ No .venv or .python-version, using global pyenv ($(python --version 2>/dev/null))"
}

cd() {
  builtin cd "$@" || return
  autoenv_activate
}

#######################################################################
# 🔧 General Dev Helpers
#######################################################################

# killport → kill whatever is running on a port
# Usage: killport 8080
killport() {
  if [ -z "$1" ]; then
    echo "⚠️  Usage: killport <port>"
    return 1
  fi
  local pid
  pid=$(lsof -ti tcp:$1)
  if [ -n "$pid" ]; then
    kill -9 $pid && echo "💀 Killed process $pid on port $1"
  else
    echo "ℹ️  No process found on port $1"
  fi
}

# portwatch → poll a port until a service responds (useful for docker/APIs)
# Usage: portwatch 8080
# Usage: portwatch 8080 30   (timeout after 30s)
portwatch() {
  local port=$1
  local timeout=${2:-60}
  local elapsed=0

  if [ -z "$port" ]; then
    echo "⚠️  Usage: portwatch <port> [timeout_seconds]"
    return 1
  fi

  echo "👀 Watching port $port (timeout: ${timeout}s)..."
  while ! nc -z localhost "$port" 2>/dev/null; do
    sleep 1
    elapsed=$((elapsed + 1))
    if [ "$elapsed" -ge "$timeout" ]; then
      echo "⏱️  Timeout after ${timeout}s — nothing on port $port"
      return 1
    fi
  done
  echo "✅ Port $port is up! (${elapsed}s)"
}

# mkcd → make a directory and cd into it
# Usage: mkcd my-new-project
mkcd() {
  if [ -z "$1" ]; then
    echo "⚠️  Usage: mkcd <directory>"
    return 1
  fi
  mkdir -p "$1" && cd "$1" || return
}

# ghopen → open current git repo in the browser
ghopen() {
  local url
  url=$(git remote get-url origin 2>/dev/null)
  if [ -z "$url" ]; then
    echo "⚠️  No git remote found."
    return 1
  fi
  # convert SSH to HTTPS
  url=$(echo "$url" | sed 's|git@github.com:|https://github.com/|' | sed 's|\.git$||')
  open "$url"
  echo "🌐 Opening $url"
}

# newproject → scaffold a new project in the right Code folder
# Usage: newproject <name> <folder_number>
# Example: newproject my-tool 004
newproject() {
  local name=$1
  local folder=$2

  if [ -z "$name" ] || [ -z "$folder" ]; then
    echo "⚠️  Usage: newproject <name> <folder_number>"
    echo "  Folders:"
    ls ~/Code | sed 's/^/    /'
    return 1
  fi

  local base=$(ls ~/Code | grep "^${folder}")
  if [ -z "$base" ]; then
    echo "❌ No folder matching '${folder}' in ~/Code"
    return 1
  fi

  local target="$HOME/Code/$base/$name"
  mkdir -p "$target"
  cd "$target" || return

  # scaffold
  touch README.md requirements.txt .env .env.example .gitignore
  echo "# $name" > README.md
  echo ".venv/" >> .gitignore
  echo ".env" >> .gitignore
  echo "__pycache__/" >> .gitignore

  echo "3.10.6" > .python-version

  git init -q
  echo "✅ Project '$name' created in ~/Code/$base/"
  echo "📂 $(pwd)"
}

#######################################################################
# 🔀 Git Helpers
#######################################################################

# gitclean → interactive merged branch cleanup
gitclean() {
  local branches
  branches=$(git branch --merged | grep -v '^\*' | grep -v 'main\|master\|develop')

  if [ -z "$branches" ]; then
    echo "✅ No merged branches to clean."
    return 0
  fi

  echo "🧹 Merged branches that can be deleted:"
  echo "$branches" | sed 's/^/  /'
  echo ""
  echo -n "Delete all of the above? [y/N] "
  read -r confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    echo "$branches" | xargs git branch -d
    echo "✅ Done."
  else
    echo "↩️  Aborted."
  fi
}

#######################################################################
# 🔄 Context Switchers (personal ↔ work)
#######################################################################

# workon → switch to Engenious work context
# Sets gh CLI, GCP credentials, and cds to 006-engenious
workon() {
  echo "🏢 Switching to Engenious work context..."

  # Switch gh CLI account
  gh auth switch --user j-garassino-engenious 2>/dev/null && \
    echo "  ✅ gh → j-garassino-engenious" || \
    echo "  ⚠️  gh switch failed — run: gh auth login"

  # Load work GCP credentials if available
  local work_creds=$(ls ~/Code/001-config/002-gcp-credentials/*engenious*.json 2>/dev/null | head -1)
  if [ -n "$work_creds" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$work_creds"
    echo "  ✅ GCP → $(basename $work_creds)"
  else
    unset GOOGLE_APPLICATION_CREDENTIALS
    echo "  ℹ️  No Engenious GCP credentials found in ~/Code/001-config/002-gcp-credentials/"
  fi

  cd ~/Code/006-engenious || return
  echo "  ✅ cd → ~/Code/006-engenious"
  echo ""
  echo "🏢 Work context active."
  engopen
}

# personal → switch back to personal context
# Sets gh CLI, GCP credentials, and cds to 004-products
personal() {
  echo "🏠 Switching to personal context..."

  # Switch gh CLI account
  gh auth switch --user juan-garassino 2>/dev/null && \
    echo "  ✅ gh → juan-garassino" || \
    echo "  ⚠️  gh switch failed"

  # Load personal GCP credentials if available
  local personal_creds=$(ls ~/Code/001-config/002-gcp-credentials/*personal*.json 2>/dev/null | head -1)
  if [ -n "$personal_creds" ]; then
    export GOOGLE_APPLICATION_CREDENTIALS="$personal_creds"
    echo "  ✅ GCP → $(basename $personal_creds)"
  else
    unset GOOGLE_APPLICATION_CREDENTIALS
    echo "  ℹ️  No personal GCP credentials found."
  fi

  cd ~/Code/004-products || return
  echo "  ✅ cd → ~/Code/004-products"
  echo ""
  echo "🏠 Personal context active."
}

# whoami_dev → show current active context (git, gh, GCP)
whoami_dev() {
  echo "👤 Current Dev Context"
  echo "─────────────────────────────────────────"
  echo "  📁 Directory : $(pwd)"
  echo "  📧 Git email : $(git config user.email 2>/dev/null || echo '<not in a repo>')"
  echo "  🐙 gh account: $(gh api user --jq .login 2>/dev/null || echo '<not authenticated>')"
  echo "  ☁️  GCP creds : ${GOOGLE_APPLICATION_CREDENTIALS:-<not set>}"
  echo "  🐍 Python    : $(python --version 2>/dev/null || echo '<none>')"
  echo "  📦 Venv      : ${VIRTUAL_ENV:-<none>}"
}

# engopen → list Engenious repos and cd into selected one
engopen() {
  local repos=(~/Code/006-engenious/*/)
  if [ ${#repos[@]} -eq 0 ]; then
    echo "⚠️  No repos found in ~/Code/006-engenious/"
    return 1
  fi

  echo "📂 Engenious repos:"
  local i=1
  for repo in "${repos[@]}"; do
    echo "  $i) $(basename $repo)"
    i=$((i + 1))
  done

  echo -n "Enter number to cd into (or press Enter to stay): "
  read -r choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#repos[@]} ]; then
    cd "${repos[$choice]}" || return
    echo "✅ cd → $(pwd)"
  fi
}

#######################################################################
# 📖 mycmds → grouped help for all custom commands
#######################################################################
mycmds() {
  cat <<'EOF'

╔══════════════════════════════════════════════════════════════╗
║                  🛠️   Custom Dev Commands                    ║
╚══════════════════════════════════════════════════════════════╝

🐍  Python / Venv
─────────────────────────────────────────────────────────────
  usevenv [ver] [name] [reset]   Create/activate uv venv
  usepyenv <env>                 Activate a pyenv-managed venv
  lsenvs                         List pyenv versions + .venv dirs
  venvinfo                       Show active environment details
  freezeenv                      Save deps → requirements.txt
  syncenv                        Sync deps from requirements.txt
  envcheck                       Compare .env vs .env.example

🔀  Context Switchers
─────────────────────────────────────────────────────────────
  workon                         → Engenious (gh, GCP, cd)
  personal                       → Personal (gh, GCP, cd)
  whoami_dev                     Show current active context

🌿  Git Helpers
─────────────────────────────────────────────────────────────
  gitclean                       Interactive merged branch cleanup
  ghopen                         Open current repo in browser

🏗️   Project Scaffolding
─────────────────────────────────────────────────────────────
  newproject <name> <folder>     Scaffold project in ~/Code/00X
  engopen                        Pick and cd into Engenious repo
  mkcd <dir>                     Make dir and cd into it

🔧  System Helpers
─────────────────────────────────────────────────────────────
  killport <port>                Kill process on a port
  portwatch <port> [timeout]     Wait until a port is up

⚡  Shell Config
─────────────────────────────────────────────────────────────
  editrc                         Open ~/.zshrc in editor
  reloadrc                       Reload ~/.zshrc
  mycmds                         Show this help

EOF
}

#######################################################################
# 🚀 Antigravity
#######################################################################
export PATH="/Users/juan-garassino/.antigravity/antigravity/bin:$PATH"
