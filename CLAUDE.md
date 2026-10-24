# CLAUDE.md — Dotfiles & Machine Setup

This repo is Juan's macOS + Linux **environment-replication kit**. Shell, prompt, editor, git
identity, and Claude Code config — organized into subdirs and symlinked into `$HOME` by
`install.sh`. **Secrets never live here:** API keys are in `~/.secrets` (chmod 600, outside
any repo); GCP keys in `~/Code/000-config/002-gcp-credentials/`.

- Canonical path: `~/Code/000-config/001-dotfiles`
- Remote: `github.com/juan-garassino/dotfiles` — **PUBLIC fork** of `lewagon/dotfiles` (can't be made private; zero secrets, ever)

> **Claude Code — read this first.** If you're working in this repo, your single most
> likely task is to **set up / replicate this environment on a machine** (usually a fresh
> one). **Migrating from another machine (Mac or Linux → Linux, WSL or Mac)? → follow
> `MIGRATE.md` end-to-end** (Claude-executed: rsync `~/Code` + `packages/home-carry.txt` from the
> source over ssh, install.sh, guided logins, verify). `bootstrap.sh` is the one-command entry.
> **Migrations are interactive and default to clean and light:** run the `MIGRATE.md` step 1b interview (rounds A–G, ≤ 4
> AskUserQuestion questions each: role, apps, toolchain, look and feel, accounts, verification, keeping the Mac clean) *before* touching the source, then
> step 5b (which big folders / how much Claude history) *before* any rsync — don't copy the full 25 GB history or training
> outputs unasked. Save the answers in `~/.migration/answers.md`, never inside `~/Code`; all migration state lives in
> `~/.migration/` (every Bash call starts with `source ~/.migration/env`). A Linux buffer that already holds an older `~/Code`
> may have its own work: reconcile it into the source first (`MIGRATE.md` section P, on the source, before the freeze), then mirror
> it with the reviewed `--delete` dry run (10b). Personal data (Documents, Pictures, …) moves only via 10d, only to a personal machine.
> Routine fresh setup → go straight to
> **[Full machine setup](#full-machine-setup--claude-code-follow-this-end-to-end)**
> and run it end-to-end, pausing only at the 🙋 (human-only) steps. The other most common
> task is editing a config + pushing via `/backup-env`. If the user clearly wants something
> else, ignore this banner and help with that.

## Repo map

| Path | What | Linked to |
|---|---|---|
| `shell/` | zshrc, zshenv, zprofile, aliases | `~/.zshrc`, … (symlink) |
| `git/` | gitconfig + personal/work identities | `~/.gitconfig`, … (symlink) |
| `ssh/config` | SSH host aliases (personal/work) | `~/.ssh/config` (symlink) |
| `prompt/p10k.zsh` | Powerlevel10k theme | `~/.p10k.zsh` (symlink) |
| `editor/settings.json` | VS Code / Cursor settings | editor User dirs (copied by install.sh) |
| `claude/` | statusline, sanitized settings, `skills/`, `agents/`, `mcp-servers.md` | `~/.claude/…` |
| `custom_scripts/` | code_manager, repo_scan, backup_env, ai_git_commit, … | run via `$CUSTOM` aliases |
| `packages/` | `Brewfile` (macOS `brew bundle`, incl. app casks) · `apt.txt`/`dnf.txt` + `linux-apps.sh` (Linux desktop apps) · `windows-apps.txt` (WSL → winget) · `mysandbox-requirements.txt` | — |
| `.secrets.sample` | expected API-key names (no values) | seeds `~/.secrets` |
| `legacy/` | retired configs kept for reference | — |

## Full machine setup — Claude Code, follow this end-to-end

Goal: take a fresh machine (macOS, Linux or WSL) to a working replica of this environment. Do the steps in
order, **verify each before moving on**, and **STOP to ask the user** at the human-only
points (marked 🙋 — secrets and keys a machine can't fabricate).

1. **Platform** — macOS: `install.sh` installs Homebrew itself (noninteractive). Linux/WSL: nothing to do
   (apt). Detect WSL with `grep -qi microsoft /proc/version`.
2. **Run the installer** — first (any OS) set up temporary passwordless sudo exactly as in
   `MIGRATE.md` step 4 (🙋 one command; Claude can't type passwords) and remove it at the
   end. Then `cd <repo> && ./install.sh` (OS-aware: **macOS** → Homebrew + Brewfile;
   **Linux** → apt/dnf from `packages/`, gh + VS Code repos, uv from the official installer; on macOS uv comes from Homebrew). It then
   symlinks all dotfiles, installs Oh-My-Zsh + Powerlevel10k, runs `uv python install 3.11 3.12 3.13`
   + `uv tool install ruff pre-commit`, wires the Claude statusline, restores
   `skills/` + `agents/`, and seeds `~/.secrets` from `.secrets.sample`. Verify: `ls -la ~/.zshrc`
   is a symlink into `shell/zshrc`; `brew bundle check --file=<repo>/Brewfile` is satisfied;
   `which uv` is a brew path on macOS (`~/.local/bin/uv` on Linux), never a `.pyenv/shims` one. **Icons are opt-in:** before running
   `install.sh`, ask the user whether to use the new Bauhaus app icons (and on a Mac, whether to also swap
   the Dock tiles and re-apply icons after app updates), then run `BAUHAUS_ICONS=yes|no BAUHAUS_MAC_EXTRAS=yes|no ./install.sh`.
   Without a terminal the installer skips them.
3. 🙋 **Secrets** — `~/.secrets` was seeded with EMPTY values. Ask the user to paste the real
   keys (password manager) into `~/.secrets`, then `chmod 600 ~/.secrets`. Expected keys: see
   `.secrets.sample`. **Never echo a key value; never commit `~/.secrets`.**
4. 🙋 **SSH keys** — ask the user to place `~/.ssh/id_ed25519_personal` and
   `~/.ssh/id_ed25519_work` (chmod 600), then `ssh-add --apple-use-keychain` each. Verify:
   `ssh -T git@github.com` → "Hi juan-garassino"; `ssh -T git@github-work` → work account.
5. 🙋 **GitHub CLI** — `gh auth login` for both accounts (personal `juan-garassino`, work
   `j-garassino-engenious`). Verify `gh auth status` shows both.
6. 🙋 **GCP creds** — ask the user to drop the service-account JSONs into
   `~/Code/000-config/002-gcp-credentials/`. `workon` / `personal` read them.
7. **Python** — uv-only (install.sh already installed 3.11/3.12/3.13). Run `mysandbox` once
   (creates + seeds the global uv venv `~/.venv-sandbox`). Projects use `usevenv <ver>`
   (uv-managed) or `uv sync`. Verify `python --version` inside the sandbox.
8. **Claude Code** — re-enable plugins: context7, superpowers, code-simplifier,
   frontend-design. MCP servers: see `claude/mcp-servers.md`. Skills/agents already restored.
9. **Final check** — `exec zsh`. Confirm the p10k prompt renders with the `gh_identity`
   segment, `whoami_dev` reports the right context, and `cd` into a project auto-activates its
   `.venv`.

## How the environment works (for debugging)

- **uv-only Python** — no pyenv anywhere. `usevenv` → `uv venv --python <ver>` (uv manages
  versions). The global playground is the uv venv `~/.venv-sandbox` (command: `mysandbox`,
  seeded from `packages/mysandbox-requirements.txt`, retry-safe `.seeded` marker).
  `autoenv_activate` (a `cd` hook) activates a project `.venv` first, else the sandbox;
  legacy `.python-version` files naming old pyenv envs are quietly ignored (once per dir
  per session — many are tracked in pull-only Le Wagon repos and must not be edited).
- **Node** — nvm is lazy-loaded (first `node`/`npm` call), but zshrc puts the newest installed
  `~/.nvm/versions/node/v*/bin` on PATH at startup so npm-global CLIs (`codex`, `gemini`, `mmdc`) work in a fresh shell.
- **Dual identity** — gitconfig `includeIf` sets commit identity by directory (`~/Code/`
  personal, `~/Code/002-engenious/` work); the `gh_auto_switch` cd-hook switches the gh CLI
  account; `workon`/`personal` switch GCP creds + `cd`. `whoami_dev` shows the active context.
- **Snapshot guard** — never give cd-hooks or their helpers `_`-prefixed names without the
  `typeset -f … || command …` fallback. Claude Code's shell snapshot drops `_`-prefixed
  functions; an unguarded wrapper then recurses infinitely and floods the temp dir.

## Guardrails (hard rules)

- **Never commit a secret.** Keys live in `~/.secrets` only. `custom_scripts/backup_env.sh`
  runs a secret-scan gate on the staged diff before every commit — never bypass it.
- **This repo is PUBLIC.** Before any push, confirm: no key values, no `~/.secrets`, no GCP JSON.
- **Don't overwrite an existing `~/.secrets`** during setup — only seed it when missing.
- **Edit in place:** edit files in their subdirs here; the `$HOME` symlinks pick up changes
  live. After editing the shell config, run `zsh -n shell/zshrc` before relying on it.

## Backup / sync

Refresh and push the whole kit with the **`/backup-env`** skill, or
`custom_scripts/backup_env.sh`. It regenerates the Brewfile, re-sanitizes
`claude/settings.json` (whitelisted keys), re-snapshots the skills listed in `claude/skills.public` +
agents, runs the secret-scan gate on the staged diff, commits, and pushes. Full how-it-works reference: `SETUP.md`.
