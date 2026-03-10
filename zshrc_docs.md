# 🛠️ Juan's `.zshrc` — Command Reference

> A personal shell environment built for autonomy, dual-context switching (personal ↔ work), and Python project management.

---

## Table of Contents

- [Context Switchers](#-context-switchers)
- [Python / Venv](#-python--venv)
- [Git Helpers](#-git-helpers)
- [Project Scaffolding](#-project-scaffolding)
- [System Helpers](#-system-helpers)
- [Shell Config](#-shell-config)
- [Auto-behaviors](#-auto-behaviors)
- [Environment Structure](#-environment-structure)

---

## 🔀 Context Switchers

These are the most powerful commands in the setup. They switch your entire dev identity — GitHub account, GCP credentials, and working directory — in one command.

---

### `workon`

Switch to the **Engenious work context**.

```zsh
workon
```

**What it does:**
- Switches `gh` CLI to `j-garassino-engenious`
- Loads the Engenious GCP credentials from `~/Code/001-config/002-gcp-credentials/`
- `cd` into `~/Code/006-engenious`
- Calls `engopen` so you can pick a repo immediately

**When to use:** First thing when starting a work session.

---

### `personal`

Switch to the **personal context**.

```zsh
personal
```

**What it does:**
- Switches `gh` CLI to `juan-garassino`
- Loads personal GCP credentials (if present)
- `cd` into `~/Code/004-products`

**When to use:** When switching from work to personal projects.

---

### `whoami_dev`

Show a full snapshot of your **current active context**.

```zsh
whoami_dev
```

**Output:**
```
👤 Current Dev Context
─────────────────────────────────────────
  📁 Directory : ~/Code/006-engenious/ai_underwriter_chatbot
  📧 Git email : jgarassino@engenious.io
  🐙 gh account: j-garassino-engenious
  ☁️  GCP creds : /Users/.../engenious-key.json
  🐍 Python    : Python 3.10.6
  📦 Venv      : /Users/.../ai_underwriter_chatbot/.venv
```

**When to use:** Any time you're unsure which identity/context is active.

---

## 🐍 Python / Venv

---

### `usevenv`

Create or activate a **uv-based virtual environment** with a specific Python version.

```zsh
usevenv                          # Python 3.10.6, venv name .venv
usevenv 3.11.4                   # Python 3.11.4, venv name .venv
usevenv 3.10.6 .venv-alt         # custom venv name
usevenv 3.10.6 .venv reset       # destroy and recreate
```

**What it does:**
- Sets the pyenv shell to the requested version
- Creates the venv with `uv` if it doesn't exist
- Activates it
- Writes `.python-version` for `autoenv` to pick up next time

---

### `usepyenv`

Activate a **named pyenv virtualenv** (not a local `.venv`).

```zsh
usepyenv my-ml-env
```

> ⚠️ When using pyenv venvs, `uv` requires the `--active` flag.

---

### `lsenvs`

List all **pyenv versions**, virtualenvs, and local `.venv` directories.

```zsh
lsenvs
```

---

### `venvinfo`

Show detailed info about the **currently active environment**.

```zsh
venvinfo
```

Includes: venv path, Python version, site-packages location, and package count.

---

### `freezeenv`

Save the current environment's dependencies to `requirements.txt`.

```zsh
freezeenv
```

> Uses `uv pip freeze`. Requires an active venv.

---

### `syncenv`

Sync the current environment with `requirements.txt`.

```zsh
syncenv
```

> Uses `uv pip sync`. Useful after pulling a repo or switching branches.

---

### `envcheck`

Compare `.env` against `.env.example` and report **missing keys**.

```zsh
envcheck
```

**Example output:**
```
❌ Missing keys in .env:
  - OPENAI_API_KEY
  - DATABASE_URL
```

**When to use:** After cloning a repo, or when onboarding a new service.

---

## 🌿 Git Helpers

---

### `gitclean`

Interactive **merged branch cleanup**.

```zsh
gitclean
```

Lists all branches that have been merged into the current branch (excluding `main`, `master`, `develop`), asks for confirmation, then deletes them.

---

### `ghopen`

Open the **current git repo** in your browser.

```zsh
ghopen
```

Works with SSH remotes — converts `git@github.com:org/repo.git` to `https://github.com/org/repo` automatically.

---

## 🏗️ Project Scaffolding

---

### `newproject`

Scaffold a new project in the right `~/Code` folder.

```zsh
newproject <name> <folder_number>
```

**Examples:**
```zsh
newproject my-api 004           # creates ~/Code/004-products/my-api
newproject rl-experiment 003    # creates ~/Code/003-research/rl-experiment
```

**What it creates:**
```
my-api/
├── README.md           # prefilled with project name
├── requirements.txt
├── .env
├── .env.example
├── .gitignore          # includes .venv, .env, __pycache__
└── .python-version     # defaults to 3.10.6
```

Also runs `git init` so it's immediately a repo.

---

### `engopen`

Interactively **pick and cd into** an Engenious repo.

```zsh
engopen
```

**Output:**
```
📂 Engenious repos:
  1) ai_underwriter_chatbot
  2) ai_underwriter_knowledge_extraction
  3) ai_underwriter_ocr
  4) ai_underwriter_prediction
  5) phoenix_be_pro_clinical_trials

Enter number to cd into (or press Enter to stay):
```

> Also called automatically at the end of `workon`.

---

### `mkcd`

Make a directory and immediately `cd` into it.

```zsh
mkcd my-new-folder
```

---

## 🔧 System Helpers

---

### `killport`

Kill whatever process is running on a given port.

```zsh
killport 8080
```

Useful when a dev server didn't shut down cleanly.

---

### `portwatch`

Poll a port until a service is up. Default timeout: 60 seconds.

```zsh
portwatch 8080          # waits up to 60s
portwatch 8080 120      # waits up to 120s
```

**When to use:** After `docker-compose up` or starting a slow API — chain it in a script to know exactly when the service is ready.

---

## ⚡ Shell Config

---

### `editrc`

Open `~/.zshrc` in your default editor.

```zsh
editrc
```

---

### `reloadrc`

Reload `~/.zshrc` without restarting the terminal.

```zsh
reloadrc
```

---

### `mycmds`

Print a grouped reference of all custom commands.

```zsh
mycmds
```

---

## 🤖 Auto-behaviors

These run automatically — no manual invocation needed.

---

### `autoenv` (hooked to `cd`)

Every time you `cd` into a directory, the shell automatically:

1. **Activates `.venv`** if one exists in the directory
2. **Activates a pyenv virtualenv** if `.python-version` contains a named env
3. **Sets the pyenv Python version** if `.python-version` contains a version number
4. **Falls back to global pyenv** if nothing is found

This means you never need to manually `source .venv/bin/activate` again.

---

### `load-nvmrc` (hooked to `cd`)

Automatically switches Node.js version when entering a directory with an `.nvmrc` file.

---

### `direnv`

If a directory has a `.envrc` file, `direnv` automatically loads/unloads environment variables as you enter/leave the directory. This is the recommended way to manage per-project secrets and credentials.

**Example `.envrc`:**
```bash
export DATABASE_URL=postgres://localhost/mydb
export OPENAI_API_KEY=sk-...
```

---

## 🗂️ Environment Structure

```
~/Code/
├── 001-config/
│   ├── 001-dotfiles/       ← gitconfig, zshrc, ssh/config (symlinked)
│   └── 002-gcp-credentials/ ← GCP service account keys (loaded by workon/personal)
├── 002-lewagon-spiced/     ← personal (git: juan-garassino@gmail.com)
├── 003-research/           ← personal
├── 004-products/           ← personal
├── 005-knowledge/          ← personal
├── 006-engenious/          ← WORK (git: jgarassino@engenious.io)
├── 007-archives/           ← personal
└── 008-sandbox/            ← personal
```

**Git identity is automatic** based on directory:
- Any repo inside `006-engenious/` → `jgarassino@engenious.io` + `id_ed25519_work`
- Everything else → `juan.garassino@gmail.com` + `id_ed25519_personal`

**SSH:**
- `github.com` → personal account
- `github-work` → Engenious account

---

*Last updated: March 2026*
