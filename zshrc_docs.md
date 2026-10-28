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
- [Improvements](#-improvements)
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
- Loads the Engenious GCP credentials from `~/Code/000-config/002-gcp-credentials/`
- `cd` into `~/Code/002-engenious`
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
- `cd` into `~/Code/005-products`

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
  📁 Directory : ~/Code/002-engenious/<repo>
  📧 Git email : jgarassino@engenious.io
  🐙 gh account: j-garassino-engenious
  ☁️  GCP creds : ~/Code/000-config/002-gcp-credentials/<work>.json
  🐍 Python    : Python 3.12.9
  📦 Venv      : ~/Code/002-engenious/<repo>/.venv
```

**When to use:** Any time you're unsure which identity/context is active.

---

## 🐍 Python / Venv

---

> Python is **uv-only** (no pyenv since 2026-09-18). uv downloads and manages every Python version.

### `envup`

Build + activate **this project's env from whatever manifest exists**.

```zsh
envup            # pyproject.toml / uv.lock → uv sync
envup 3.11       # requirements.txt → uv venv (3.11) + uv pip install -r
```

**What it does:**
- `pyproject.toml` / `uv.lock` → `uv sync`, activates `.venv`
- `requirements.txt` → creates `.venv` (version: arg, else `.python-version`, else 3.12) and installs into it
- Nothing → bare `.venv`
- Never writes `.python-version` (safe inside pull-only upstream repos)

---

### `usevenv`

Create or activate a **uv virtual environment** at a specific Python version.

```zsh
usevenv                          # Python 3.12, venv name .venv
usevenv 3.11                     # Python 3.11, venv name .venv
usevenv 3.12 .venv-alt           # custom venv name
usevenv 3.12 .venv reset         # destroy and recreate
```

**What it does:**
- Creates the venv with `uv venv --python <ver>` if it doesn't exist (uv downloads the Python if missing)
- Activates it
- Writes `.python-version` only if the dir has none (never overwrites)

---

### `mysandbox`

Create/activate the **global uv playground** `~/.venv-sandbox` (Python 3.12), seeded once from `packages/mysandbox-requirements.txt`.

```zsh
mysandbox        # create + seed on first use, then activate
mysandbox reset  # destroy and rebuild
```

> A `.seeded` marker makes the big install retry-safe — re-run if seeding was interrupted.

---

### `u`, `pip`, `python`

uv conveniences that never intercept `uv` itself:
- `u pytest -q` == `uv run pytest -q` (project-aware)
- `pip` / `pip3` → `uv pip` (uv venvs ship without pip). Real binary: `command pip`
- `python` → the active venv's python if any; else `uv run python` in a project, else an ephemeral uv 3.12

---

### `lsenvs`

List **uv-managed Pythons**, the global sandbox, and local `.venv` directories.

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

### `pkgupdate`

Upgrade specific packages **and automatically update** `requirements.txt`.

```zsh
pkgupdate numpy pandas          # Upgrade multiple packages
pkgupdate requests              # Upgrade single package
```

**What it does:**
- Upgrades the specified packages with `uv pip install --upgrade`
- Automatically runs `uv pip freeze > requirements.txt`
- Keeps your requirements.txt in sync

**When to use:** When iterating on dependencies or testing new versions.

---

### `venvclean`

Interactively **remove unused `.venv` folders**.

```zsh
venvclean
```

**Output:**
```
🧹 Local venvs found:
  1) .venv (245M)
  2) .venv-old (512M)
  3) .venv-test (123M)
Enter numbers to delete (space-separated, or Enter to skip): 2 3
🗑️  Removing .venv-old...
🗑️  Removing .venv-test...
✅ Cleanup done.
```

**When to use:** Periodically clean up old venv folders that are no longer needed.

---

### `dev-reset`

**Completely reset your environment** — useful for debugging environment issues.

```zsh
dev-reset
```

**What it does:**
- Deactivates the active venv
- Removes `.python-version` file
- Removes `.venv` folder
- Next `cd` re-runs autoenv detection

**When to use:** When your environment gets into a weird state and you need to start fresh.

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
newproject my-api 005           # creates ~/Code/005-products/my-api
newproject rl-experiment 006    # creates ~/Code/006-research-prototypes/rl-experiment
```

**What it creates:**
```
my-api/
├── README.md           # prefilled with project name
├── .env
├── .env.example
├── .gitignore          # includes .venv, .env, __pycache__
└── .python-version     # 3.12.9
```

No `requirements.txt` — add deps with `uv init` / `uv add` (pyproject).

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

1. **Activates `.venv`** if one exists in the directory (+ a once-per-session `uv sync` hint if `uv.lock` is newer)
2. **Hints `envup`** (once per dir, never mutates) if there's a manifest or a version in `.python-version` but no `.venv`; a legacy pyenv env name is quietly ignored
3. **Falls back to `~/.venv-sandbox`** if built, else deactivates to plain `python3`

The same `cd` hook also runs `gh_auto_switch` (work gh account inside `002-engenious/`, personal elsewhere).

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

## ✨ Improvements

### Autoenv Smart Logging

`autoenv_activate` says what it did (interactive shells only — scripts and Claude Code stay quiet):

```zsh
▶ Activated .venv (🐍 3.12.9)                          # project .venv
🔄 uv.lock is newer than .venv — run: uv sync          # stale env
📦 Project detected, no .venv — run: envup             # manifest, no env
📦 .python-version=3.11, no .venv — run: envup         # version file, no env
ℹ️  Ignoring legacy pyenv env 'my-env' (uv-only setup) # old pyenv name
▶ No project env — using ~/.venv-sandbox               # fallback
```

---

## 🗂️ Environment Structure

```
~/Code/
├── 000-config/
│   ├── 001-dotfiles/       ← gitconfig, zshrc, ssh/config (symlinked)
│   └── 002-gcp-credentials/ ← GCP service account keys (loaded by workon/personal; never in git)
├── 001-archives/           ← personal (git: juan.garassino@gmail.com)
├── 002-engenious/          ← WORK (git: jgarassino@engenious.io)
├── 003-knowledge-playgrounds/ ← personal
├── 004-lewagon-spiced/     ← personal
├── 005-products/           ← personal
├── 006-research-prototypes/ ← personal
└── 007-sandbox/            ← personal
```

**Git identity is automatic** based on directory:
- Any repo inside `002-engenious/` → `jgarassino@engenious.io` + `id_ed25519_work`
- Everything else → `juan.garassino@gmail.com` + `id_ed25519_personal`

**SSH:**
- `github.com` → personal account
- `github-work` → Engenious account

---

*Last updated: October 2026*
