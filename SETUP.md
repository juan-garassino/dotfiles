# SETUP.md — Environment Replication Runbook

How to reproduce Juan's full macOS dev environment on a new machine, and how it works.
This repo is **public-safe by design**: every config is clean, and all secrets live in
`~/.secrets` (chmod 600, outside any repo) — copied manually, never committed.

---

## 0. Quick start (new machine)

```bash
# 1. Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Clone this repo to the canonical path
git clone git@github.com:juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles
cd ~/Code/000-config/001-dotfiles

# 3. Run the installer — symlinks dotfiles, brew bundle, Oh-My-Zsh + p10k, Claude statusline
./install.sh

# 4. Restore secrets (NOT in any repo)
#    Copy ~/.secrets from your password manager / old machine (scp / AirDrop), then:
chmod 600 ~/.secrets

# 5. Restore credentials & auth
#    - Place GCP service-account JSONs in ~/Code/000-config/002-gcp-credentials/
#    - gh auth login   (personal: juan-garassino, then work: j-garassino-engenious)
#    - Place SSH keys ~/.ssh/id_ed25519_personal and ~/.ssh/id_ed25519_work (chmod 600)

# 6. Python versions
pyenv install 3.10.6 3.11.4 3.12.9 && pyenv global 3.10.6

# 7. Reload
exec zsh
```

`install.sh` is idempotent — re-run anytime.

---

## 1. Shell & Python environments (pyenv + uv + venv + direnv)

**Auto-activation on `cd`** — `autoenv_activate()` (hooked into `cd()`), priority order:
1. local `.venv/bin/activate` (uv venv)
2. `.python-version` matching a pyenv virtualenv name → `pyenv activate <name>`
3. `.python-version` as a version string (e.g. `3.10.6`) → `pyenv shell <version>`
4. fallback to global pyenv. Messages print only in interactive shells.

**Commands:**

| Command | Does | Args |
|---|---|---|
| `usevenv` | create/activate a uv venv at a Python version | `[version] [name=.venv] [reset]` |
| `usepyenv` | activate a named pyenv virtualenv | `<env_name>` |
| `pyswitch` | interactive Python version selector | — |
| `pkgupdate` | upgrade packages + update requirements.txt | `<pkgs…>` |
| `freezeenv` / `syncenv` | save / restore deps via requirements.txt | — |
| `venvclean` | remove unused `.venv` dirs (interactive) | — |
| `dev-reset` | deactivate + remove `.python-version` & `.venv` | — |
| `envcheck` | compare `.env` vs `.env.example`, report missing | — |
| `lsenvs` | list pyenv versions + project `.venv` dirs | — |

**Reproduce:** `brew install pyenv pyenv-virtualenv uv direnv`; direnv hook is in zshrc; per-project `.envrc` needs `direnv allow .`.

---

## 2. Identity & context switching (work vs personal)

Directory-aware across three layers — everything under `~/Code/` is personal **except** `002-engenious/` (work):

1. **Git identity** — `gitconfig` `includeIf`: `~/Code/` → `gitconfig-personal` (juan.garassino@gmail.com, personal SSH key); `~/Code/002-engenious/` → `gitconfig-work` (jgarassino@engenious.io, work SSH key). `gitconfig-work` also rewrites `git@github.com:` → `git@github-work:` so work repos use the work key.
2. **gh CLI account** — `gh_auto_switch` cd-hook reads `~/.config/gh/hosts.yml`, switches only when crossing the `002-engenious/` boundary (work: `j-garassino-engenious`, else `juan-garassino`).
3. **GCP creds** — `workon` / `personal` set `GOOGLE_APPLICATION_CREDENTIALS` to the matching JSON in `002-gcp-credentials/` and `cd` to the context root. `whoami_dev` prints the active context (dir, git email, gh account, GCP creds, python, venv).

**SSH** (`ssh/config` → `~/.ssh/config`): `github.com` → `id_ed25519_personal`; `github-work` alias → `id_ed25519_work`.

**Reproduce:** `gh auth login` for both accounts; drop both SSH keys (chmod 600) + `ssh-add --apple-use-keychain`; place GCP JSONs.

> **Gotcha:** `gh_auto_switch` has **no** `_` prefix on purpose — Claude Code's shell snapshot drops `_`-prefixed functions, which would break the cd-hook. The lazy-load helpers that *are* `_`-prefixed (`_pyenv_lazy_load` etc.) guard with `typeset -f <helper> >/dev/null || command <cmd>` to avoid infinite recursion.

---

## 3. Containers & local services

- **Docker** (via `colima`): aliases `dk`, `dkc`, `dkcu`, `dkcd`, `dkcb`, `dkps`, `dklogs`, `dkclean`. `brew install docker docker-compose colima`.
- **Kubernetes / minikube**: completions load lazily on first TAB (`compdef <lazy> kubectl/minikube`) to save startup time. `brew install kubernetes-cli minikube helm`.
- **Postgres**: `brew install postgresql@14 && brew services start postgresql@14`. No custom psql helpers.
- **custom_scripts/**: `code_manager.sh` (`cm`/`cmr`/`cmn` — manage/rename/scan `~/Code`), `repo_scan.sh` (emit repo-tree JSON), `build_dashboard.sh` (`dashboard` — repo dashboard), `unprefix.sh` (strip `NNN-` prefixes), `ai_git_commit.sh` (AI commit messages via `llm`), `backup_env.sh` (this kit's backup, see §6).

---

## 4. Prompt, theme & status lines

**Powerlevel10k** (`source ~/.powerlevel10k/powerlevel10k.zsh-theme`, instant-prompt cached): left = `os_icon` + `dir` + `vcs`; right = status/time/RAM + env tools (pyenv/virtualenv/direnv) + a **custom `gh_identity` segment** (ochre `personal` / burgundy `work`, read from `~/.config/gh/hosts.yml`, no CLI exec). Font: **MesloLGS Nerd Font** — `brew install --cask font-meslo-lg-nerd-font`.

**Claude Code status line** (`claude/statusline-command.sh`, wired via `settings.json` → `statusLine.command`): Bauhaus 3-zone palette — **place**=cobalt blue (path/branch), **session**=gray (model/perm/context), **env/accounts**=ochre (python/gcloud/k8s/gh), **system**=burgundy (clock/RAM). State markers `● ▲ ■` (calm/caution/alarm) for context% and free RAM; permission modes `rw/auto/plan/yolo`. Reads JSON from stdin (`cwd`, `model.display_name`, `context_window.used_percentage`, `permission_mode`, `model.thinking_budget`). **Emoji only — no Nerd Font glyphs** (Claude Code strips them).

---

## 5. Editor & Claude Code config

**VS Code / Cursor** (`editor/settings.json`, symlinked into both User dirs by `install.sh`): 14pt ligature font, 2-space indent, rulers 88/120, Black-on-save + Ruff (fixAll/organizeImports), Pylance basic, telemetry off, git autofetch/smart-commit, excludes `__pycache__/.venv/.pytest_cache`.

**Claude Code** (`~/.claude/settings.json`; sanitized snapshot in `claude/settings.json`): effort `xhigh`, theme `dark-ansi`, auto-memory on, `MCP_TIMEOUT=60s`, `CLAUDE_CODE_TMPDIR=~/.claude-tmp`. SessionStart hook cats `brevity-protocol` + `docs-current-protocol`. Plugins: context7, superpowers, code-simplifier, frontend-design. Personal skills/agents live under `~/.claude/{skills,agents}/` (hello-claude, morning-coffee, where-were-we, the ds-*/eh-*/pp-*/ag-* families).

> The repo `claude/settings.json` is a **sanitized snapshot** (API keys + personal `/Users/...` allow entries stripped) — it's a template, not a live symlink. The live file is mutated by Claude Code at runtime.

---

## 6. Secrets

- API keys live **only** in `~/.secrets` (chmod 600), `source`d by zshrc at startup. Never in this repo.
- **`.secrets.sample`** (committed) lists every key this environment expects — names only, empty values. `install.sh` seeds `~/.secrets` from it on a fresh machine; then fill in the real values.
- New machine: copy `~/.secrets` manually (scp / AirDrop / password manager) — or start from the sample — then `chmod 600`.
- GCP service-account JSONs live in `~/Code/000-config/002-gcp-credentials/` (also private, outside this repo).

---

## 7. Backup & maintenance

Refresh this kit and push it with the **`/backup-env`** Claude Code skill, or directly:

```bash
custom_scripts/backup_env.sh            # refresh + secret-scan + commit + push
custom_scripts/backup_env.sh --no-push  # stage & commit locally only
```

It regenerates the `Brewfile`, re-sanitizes `claude/settings.json`, runs a high-signal **secret-scan gate** (aborts on any hit), then commits and pushes. If it aborts: move the key into `~/.secrets`, remove it from the offending file, re-run — never bypass the gate.

---

## 8. Gotchas (don't regress these)

- **`_`-prefixed functions vanish** from Claude Code's shell snapshot → top-level cd-hooks (`gh_auto_switch`) must not use `_`; lazy-load helpers must keep their `typeset -f … || command …` guard or they recurse infinitely and flood the temp dir.
- **`includeIf` order matters**: personal (`~/Code/`) first, work (`~/Code/002-engenious/`) override second.
- **gh account ≠ git identity** — the cd-hook sets the CLI account; commit email comes from `includeIf`. Both must be right.
- **p10k instant-prompt cache** is per-machine — regenerate after migrating.
- **Statusline = emoji only**, never Nerd Font glyphs.
