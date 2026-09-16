# 🛠️ Juan's Dotfiles — macOS + Linux Environment Kit

A complete, reproducible **macOS & Linux** dev environment: shell, prompt, editor, dual git identity,
Python tooling, and Claude Code config. Everything is organized into subdirs and symlinked
into `$HOME` by `install.sh`. **No secrets ever live in this repo** — API keys stay in
`~/.secrets` (chmod 600), outside any repo.

> New machine? Two ways to set up:
> - **Human:** clone → `./install.sh` → drop in your secrets/keys (below).
> - **Claude Code:** open Claude Code in this repo and say *"set up this machine"* — it
>   follows [`CLAUDE.md`](./CLAUDE.md) and stops to ask you only for secrets, SSH keys, and
>   `gh auth`.

---

## Structure

```
001-dotfiles/
├── shell/      zshrc · zshenv · zprofile · aliases     → ~/.zshrc, …
├── git/        gitconfig · -personal · -work           → ~/.gitconfig, …
├── ssh/        config (host aliases)                   → ~/.ssh/config
├── prompt/     p10k.zsh (Powerlevel10k)                → ~/.p10k.zsh
├── editor/     settings.json (VS Code / Cursor)
├── claude/     statusline · settings · skills/ · agents/ · mcp-servers.md
├── custom_scripts/  code_manager · repo_scan · backup_env · ai_git_commit · …
├── legacy/     retired configs (kept for reference)
├── packages/   Brewfile (macOS) · apt.txt / dnf.txt (Linux) · mysandbox-requirements.txt
├── .secrets.sample   expected API-key names (no values)
├── install.sh        idempotent installer
├── SETUP.md          detailed how-it-works runbook
├── MIGRATION.md      old→new machine migration runbook (clean rebuild)
└── CLAUDE.md         autonomous setup instructions for Claude Code
```

---

## Quick start (human)

> macOS shown below; on **Linux** the same `./install.sh` installs via **apt/dnf** (not Homebrew),
> adds the gh + VS Code repos, and installs uv. See `SETUP.md` for Linux details.
> Migrating from another machine? → `MIGRATION.md`.

```bash
# 1. Homebrew (macOS)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# 2. Clone to the canonical path
git clone git@github.com:juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles
cd ~/Code/000-config/001-dotfiles

# 3. Install — symlinks dotfiles, brew bundle, Oh-My-Zsh + p10k, Claude statusline,
#    restores skills/agents, seeds ~/.secrets from the sample
./install.sh

# 4. Secrets & keys (the only manual bits)
#    - fill ~/.secrets with real values, then: chmod 600 ~/.secrets
#    - place ~/.ssh/id_ed25519_personal and id_ed25519_work (chmod 600)
#    - gh auth login   (personal: juan-garassino, then work: j-garassino-engenious)
#    - drop GCP JSONs into ~/Code/000-config/002-gcp-credentials/

# 5. Python sandbox + reload  (uv-only; install.sh already installed 3.11/3.12)
mysandbox        # creates + seeds ~/.venv-sandbox from packages/mysandbox-requirements.txt
exec zsh
```

`install.sh` is idempotent — re-run anytime.

---

## Daily workflows

### Python — uv-only

uv does everything: Python versions, venvs, packages, tools. No pyenv. The global
playground is the uv venv **`~/.venv-sandbox`** (the GenAI/ML/finance scratch env),
seeded from `packages/mysandbox-requirements.txt`.

| Command | Does |
|---|---|
| `usevenv [3.12] [.venv]` | create/activate a **uv** venv (uv manages the Python version) |
| `mysandbox [reset]` | create/activate the global `~/.venv-sandbox` (seeded on first use) |
| `freezeenv` / `syncenv` | save / restore deps via requirements.txt (uv) |
| `pkgupdate <pkgs>` | upgrade packages + update requirements (uv) |
| `lsenvs` · `venvclean` · `dev-reset` · `envcheck` | inspect / clean / reset / check envs |

`cd` into a project auto-activates its `.venv`; leave it and you fall back to
`~/.venv-sandbox`. Legacy `.python-version` files naming old pyenv envs are quietly
ignored. Existing projects: `uv sync` (pyproject) or `usevenv 3.12 && uv pip install -r
requirements.txt` (legacy manifests).

### Identity — work ↔ personal

Everything under `~/Code/` is personal except `~/Code/002-engenious/` (work).

| Command | Does |
|---|---|
| `workon` | gh → work account, work GCP creds, `cd ~/Code/002-engenious` |
| `personal` | gh → personal account, personal GCP creds, `cd ~/Code/005-products` |
| `whoami_dev` | show active dir, git email, gh account, GCP creds, Python, venv |

Commit identity switches automatically by directory (gitconfig `includeIf`); the gh CLI
account switches on `cd` (`gh_auto_switch`); the active account shows in the p10k prompt
(`gh_identity` segment — ochre `personal` / burgundy `work`).

### Handy aliases & scripts

Git: `gs gaa gc gco gcb gl gp gpl gst gwip` · Docker: `dk dkc dkcu dkcd dklogs dkclean` ·
Nav: `c` (→`~/Code`), `c1`–`c8`, `..`/`...` · Scripts: `cm`/`cmr` (code_manager),
`dashboard`, `unprefix`. Run `mycmds` for the full grouped reference.

---

## Secrets

API keys live **only** in `~/.secrets` (chmod 600), sourced by zshrc at startup — never in
this public repo. [`.secrets.sample`](./.secrets.sample) lists every expected key (names,
empty values); `install.sh` seeds `~/.secrets` from it. GCP service-account JSONs live in
`~/Code/000-config/002-gcp-credentials/` (also outside this repo).

---

## Backup & sync

Refresh and push the whole kit:

```bash
custom_scripts/backup_env.sh        # or the /backup-env Claude Code skill
```

Regenerates the Brewfile, re-sanitizes the Claude settings snapshot, re-snapshots
skills/agents, runs a **secret-scan gate** (aborts on any leak), commits, and pushes.

---

*Detailed runbook: [`SETUP.md`](./SETUP.md) · Claude Code automation: [`CLAUDE.md`](./CLAUDE.md)*
