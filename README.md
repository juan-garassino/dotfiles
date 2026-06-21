# 🛠️ Juan's Dotfiles — macOS Environment Kit

A complete, reproducible macOS dev environment: shell, prompt, editor, dual git identity,
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
├── Brewfile          full toolchain (brew bundle)
├── .secrets.sample   expected API-key names (no values)
├── install.sh        idempotent installer
├── SETUP.md          detailed how-it-works runbook
└── CLAUDE.md         autonomous setup instructions for Claude Code
```

---

## Quick start (human)

```bash
# 1. Homebrew
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

# 5. Python sandbox + reload
pyenv install 3.12 && sandbox
exec zsh
```

`install.sh` is idempotent — re-run anytime.

---

## Daily workflows

### Python — uv-first, pyenv sandbox

uv is primary (versions + venvs + packages); pyenv keeps one global **sandbox** scratch env.

| Command | Does |
|---|---|
| `usevenv [3.12] [.venv]` | create/activate a **uv** venv (uv manages the Python version) |
| `sandbox` | activate the global pyenv scratch env (created on first use) |
| `usepyenv <name>` | activate a named pyenv virtualenv (legacy) |
| `pyswitch` | interactive pyenv version selector (legacy) |
| `freezeenv` / `syncenv` | save / restore deps via requirements.txt (uv) |
| `pkgupdate <pkgs>` | upgrade packages + update requirements (uv) |
| `lsenvs` · `venvclean` · `dev-reset` · `envcheck` | inspect / clean / reset / check envs |

`cd` into a project auto-activates its `.venv`; leave it and you fall back to the sandbox.

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
