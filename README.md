# 🛠️ Juan's Dotfiles — macOS + Linux Environment Kit

A complete, reproducible **macOS & Linux** dev environment: shell, prompt, editor, dual git identity,
Python tooling, and Claude Code config. Everything is organized into subdirs and symlinked
into `$HOME` by `install.sh`. **No secrets ever live in this repo** — API keys stay in
`~/.secrets` (chmod 600), outside any repo.

## 🚀 Fresh machine — one command

```bash
curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh | bash
```

[`bootstrap.sh`](./bootstrap.sh) does **git → clone → claude**: installs git/curl, clones this
repo to `~/Code/000-config/001-dotfiles`, installs Claude Code, and opens it with the setup
prompt already typed. Claude asks one question, then runs the matching runbook:
- **fresh setup** (empty machine): `install.sh` + the [`CLAUDE.md`](./CLAUDE.md) checklist.
- **migration from another machine** (Mac or Linux → Linux, WSL or Mac): [`MIGRATE.md`](./MIGRATE.md), which rsyncs
  `~/Code` + secrets/keys/`~/.claude`, installs everything and prints a PASS/FAIL scorecard.

<details><summary>Same thing by hand</summary>

```bash
sudo apt-get update && sudo apt-get install -y git curl openssh-server     # macOS: xcode-select --install
git clone https://github.com/juan-garassino/dotfiles ~/Code/000-config/001-dotfiles
curl -fsSL https://claude.ai/install.sh | bash
cd ~/Code/000-config/001-dotfiles && claude    # then: "set up this machine" or "execute MIGRATE.md"
```
</details>

Claude stops only for what a machine can't fabricate: passwords, `gh auth login`, secrets, SSH keys.

---

## 🎨 What you get — exactly this setup

| Layer | Setup | Where |
|---|---|---|
| **Shell** | zsh + Oh-My-Zsh · plugins `git gitfast last-working-dir common-aliases zsh-autosuggestions zsh-syntax-highlighting history-substring-search` · lazy-loaded nvm/rbenv/kubectl (fast startup) | `shell/zshrc` |
| **Prompt** | Powerlevel10k, Bauhaus palette (cobalt / ochre / burgundy + grays), custom `gh_identity` segment: ochre `personal` / burgundy `work` | `prompt/p10k.zsh` |
| **Font** | **MesloLGS NF**: Brewfile cask on macOS; on Linux `install.sh` downloads it to `~/.local/share/fonts` and sets GNOME Terminal / Ptyxis to `MesloLGS NF 12` | `install.sh` |
| **Terminal** | **Warp** on both (Brewfile cask / Warp apt repo), same settings: theme `dracula`, MesloLGS NF 14, `honor_ps1` so the p10k prompt shows. Default Ubuntu terminal also set to MesloLGS NF 14 | `terminal/warp-settings.toml` |
| **App icons** | Linux GNOME: one Bauhaus/Kandinsky icon set for every launcher — colored tiles (cobalt / ochre / burgundy), gray glyphs, optional name labels in Jost. `bauhaus_icons.py` (`--labels` / plain / `--dark` / `--undo`), applied by `install.sh`. macOS: `bauhaus_icons.py --mac [--undo]` sets each app's custom icon (re-run after app updates) and builds look-alike launchers for Apple's own apps (sealed volume) in `~/Applications/Bauhaus`; `--mac-dock [--undo]` swaps them into the Dock; `--mac-watch` installs a LaunchAgent that re-applies icons after app updates. In-bundle icons invalidate the app's signature, so signature-sensitive apps (`MAC_LAUNCH_ONLY`, currently Docker) keep their stock icon and get a Bauhaus launcher instead | `custom_scripts/bauhaus_icons.py` |
| **Python** | **uv only, no pyenv.** uv 3.11 + 3.12, `ruff` + `pre-commit` as uv tools, global `~/.venv-sandbox` (`mysandbox`), per-project `.venv` auto-activated on `cd`, `envup` rebuilds any project | `shell/zshrc`, `packages/mysandbox-requirements.txt` |
| **Node** | nvm (brew on macOS, standalone on Linux), LTS + global CLIs | `packages/npm-globals.txt` |
| **Containers** | Docker (colima on macOS, native Engine on Linux). Used only for deploy images and the 5 teaching stacks (Le Wagon ds/da/de, Spiced, MLE): `make up-spiced` etc. Daily dev is bare uv, never containers | `~/Code/004-lewagon-spiced/teaching-containers` |
| **Git identity** | `~/Code/` personal, `~/Code/002-engenious/` work (gitconfig `includeIf`, work SSH alias), gh CLI account auto-switches on `cd` | `git/`, `ssh/config` |
| **Claude Code** | Bauhaus 3-zone status line, sanitized `settings.json` (hooks, plugins, model), personal skills + agents, plugins: superpowers · context7 · code-simplifier · frontend-design · atlassian | `claude/` |
| **Editor** | VS Code / Antigravity settings + 48 extensions | `editor/settings.json`, `packages/vscode-extensions.txt` |
| **Packages** | macOS: curated `Brewfile` (leaves only). Linux: `apt.txt` + `linux-tools.sh` — docker + compose, gcloud, terraform, kubectl, helm, minikube, k3d, aws, act, runpodctl, cloud-sql-proxy, ollama, Warp | `packages/` |
| **Postgres** | client only on the host (`psql`, `pg_dump`); servers always run in Docker (`docker run postgres:16` / compose) | — |
| **Secrets** | `~/.secrets` (chmod 600, never in git), seeded empty from `.secrets.sample` | — |

**Not automated:** `chsh` asks for your password; first `p10k` launch:
**decline** the config wizard, since `~/.p10k.zsh` is already symlinked. Private skills
(`post-as-me`) and claude.ai-synced skills are not in this public repo; they come with the
`~/.claude` hand-carry.

**Check it matches:** `custom_scripts/check_setup.sh` (PASS/FAIL scorecard of the whole dev setup;
add `--code user@old-machine` to also prove `~/Code` — every repo, branch, stash and file — equals the source). Or by eye: `exec zsh` → the prompt shows clean icons (no boxes) and an ochre
`personal` badge; `cd ~/Code/002-engenious` → it turns burgundy `work`; `which uv` →
`~/.local/bin/uv`; `claude` → the status line renders.

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
├── MIGRATE.md      any machine → any machine (Linux/WSL/Mac), Claude-executed
├── bootstrap.sh    one command: git, clone, claude
├── MIGRATION.md    historical Intel→M5 SSD-vault plan (superseded)
└── CLAUDE.md         autonomous setup instructions for Claude Code
```

---

## Quick start (human)

> macOS shown below; on **Linux** the same `./install.sh` installs via **apt/dnf** (not Homebrew),
> adds the gh + VS Code repos, and installs uv. See `SETUP.md` for Linux details.
> Migrating from another machine? → `MIGRATE.md`.

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

Reports Brewfile drift (never overwrites the curated Brewfile), re-sanitizes the Claude
settings snapshot (strips secrets, personal paths and `autoMode`), re-snapshots skills/agents
(minus private and synced ones), runs a **secret-scan gate** (aborts on any leak), commits, and
pushes. Commits to whichever checkout the script lives in.

---

*Detailed runbook: [`SETUP.md`](./SETUP.md) · Claude Code automation: [`CLAUDE.md`](./CLAUDE.md)*
