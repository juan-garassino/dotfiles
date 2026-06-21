# CLAUDE.md — Dotfiles & Machine Setup

This repo is Juan's macOS **environment-replication kit**. Shell, prompt, editor, git
identity, and Claude Code config — organized into subdirs and symlinked into `$HOME` by
`install.sh`. **Secrets never live here:** API keys are in `~/.secrets` (chmod 600, outside
any repo); GCP keys in `~/Code/000-config/002-gcp-credentials/`.

- Canonical path: `~/Code/000-config/001-dotfiles`
- Remote: `github.com/juan-garassino/dotfiles` — **PUBLIC** (zero secrets, ever)

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
| `Brewfile` | full toolchain (`brew bundle`) | — |
| `.secrets.sample` | expected API-key names (no values) | seeds `~/.secrets` |
| `legacy/` | retired configs kept for reference | — |

## Full machine setup — Claude Code, follow this end-to-end

Goal: take a fresh macOS machine to a working replica of this environment. Do the steps in
order, **verify each before moving on**, and **STOP to ask the user** at the human-only
points (marked 🙋 — secrets and keys a machine can't fabricate).

1. **Homebrew** — `command -v brew` or install from https://brew.sh. Verify `brew --version`.
2. **Run the installer** — `cd <repo> && ./install.sh`. It symlinks all dotfiles, runs
   `brew bundle`, installs Oh-My-Zsh + Powerlevel10k, wires the Claude statusline, restores
   `skills/` + `agents/`, and seeds `~/.secrets` from `.secrets.sample`. Verify: `ls -la ~/.zshrc`
   is a symlink into `shell/zshrc`; `brew bundle check --file=<repo>/Brewfile` is satisfied.
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
7. **Python** — `pyenv install 3.12`, then run `sandbox` once (creates the global pyenv
   scratch env). Projects use `usevenv <ver>` (uv-managed). Verify `python --version`.
8. **Claude Code** — re-enable plugins: context7, superpowers, code-simplifier,
   frontend-design. MCP servers: see `claude/mcp-servers.md`. Skills/agents already restored.
9. **Final check** — `exec zsh`. Confirm the p10k prompt renders with the `gh_identity`
   segment, `whoami_dev` reports the right context, and `cd` into a project auto-activates its
   `.venv`.

## How the environment works (for debugging)

- **uv-first Python** — `usevenv` → `uv venv --python <ver>` (uv manages the version). pyenv's
  only day-to-day role is the global `sandbox` scratch env. `autoenv_activate` (a `cd` hook)
  activates a project `.venv` first, else the global sandbox. `usepyenv`/`pyswitch` remain as
  legacy pyenv helpers.
- **Dual identity** — gitconfig `includeIf` sets commit identity by directory (`~/Code/`
  personal, `~/Code/002-engenious/` work); the `gh_auto_switch` cd-hook switches the gh CLI
  account; `workon`/`personal` switch GCP creds + `cd`. `whoami_dev` shows the active context.
- **Snapshot guard** — never give cd-hooks or their helpers `_`-prefixed names without the
  `typeset -f … || command …` fallback. Claude Code's shell snapshot drops `_`-prefixed
  functions; an unguarded wrapper then recurses infinitely and floods the temp dir.

## Guardrails (hard rules)

- **Never commit a secret.** Keys live in `~/.secrets` only. `custom_scripts/backup_env.sh`
  runs a secret-scan gate before every push — never bypass it.
- **This repo is PUBLIC.** Before any push, confirm: no key values, no `~/.secrets`, no GCP JSON.
- **Don't overwrite an existing `~/.secrets`** during setup — only seed it when missing.
- **Edit in place:** edit files in their subdirs here; the `$HOME` symlinks pick up changes
  live. After editing the shell config, run `zsh -n shell/zshrc` before relying on it.

## Backup / sync

Refresh and push the whole kit with the **`/backup-env`** skill, or
`custom_scripts/backup_env.sh`. It regenerates the Brewfile, re-sanitizes
`claude/settings.json`, re-snapshots skills/agents, runs the secret-scan gate, commits, and
pushes. Full how-it-works reference: `SETUP.md`.
