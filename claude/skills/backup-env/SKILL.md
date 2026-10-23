---
name: backup-env
description: Back up Juan's full dev environment to the PUBLIC dotfiles repo (a fork of lewagon/dotfiles) — refresh Brewfile, re-sanitize Claude settings, secret-scan, commit & push. Use when the user says "backup my env", "/backup-env", "save my environment", "sync my dotfiles", "update my dotfiles backup", or after changing shell / p10k / Claude Code config.
---

# backup-env

Refreshes and pushes Juan's environment-replication kit — the `001-dotfiles` repo at
`~/Code/000-config/001-dotfiles` (remote: `github.com/juan-garassino/dotfiles`, a **PUBLIC fork** of
`lewagon/dotfiles` — it cannot be made private without leaving the fork network, so treat every byte as public).

## What it captures
- **Shell** — `zshrc`, `zshenv`, `aliases`, `gitconfig*` (symlinked, always live)
- **Prompt/theme** — `p10k.zsh` (symlinked)
- **Claude Code** — `claude/statusline-command.sh` (symlinked) + a **sanitized** `claude/settings.json` snapshot
- **Toolchain** — `Brewfile` (hand-curated; the script only reports drift) · skills/agents listed in `claude/skills.public`

**Secrets are never captured.** API keys live in `~/.secrets` (chmod 600, outside any repo), sourced by zshrc. On a new machine they're copied manually.

## How to run
```
bash ~/Code/000-config/001-dotfiles/custom_scripts/backup_env.sh
```
Add `--no-push` to stage + commit locally without pushing.

The script: (1) reports Brewfile drift, (2) re-sanitizes `settings.json` (whitelisted keys only — `theme`, `statusLine`, `hooks`, `enabledPlugins`, `model`, …; `permissions` and `autoMode` are dropped, `env` keeps only known-safe names), (3) copies ONLY the skills listed in `claude/skills.public` (allow-list; a new skill is never published until you add its name there) + agents, (4) stages explicit paths — never `git add -A`, (5) runs the **secret-scan gate on the staged diff**: gitleaks via Docker (`ghcr.io/gitleaks/gitleaks`, read-only mount) when Docker is available, else a regex for modern key formats (`sk-ant-`, `sk-proj-`, `sk-or-v1-`, `github_pat_`, `ghp_`, `nvapi-`, `gsk_`, `pplx-`, AWS, Google, Slack, private keys), (6) aborts BEFORE committing on any hit (and unstages), else timestamped commit + push.

## If the secret-scan ABORTS
A real key is in the staged diff. **Do not bypass.** Move the key into `~/.secrets`, remove it from the offending file, re-run. Never `--no-verify` or hand-edit past the gate. The repo is public: a pushed key is burned — rotate it.

## New-machine restore
```
git clone git@github.com:juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles
cd ~/Code/000-config/001-dotfiles && ./install.sh
# then copy ~/.secrets over manually (scp/AirDrop) and: chmod 600 ~/.secrets
```
`install.sh` symlinks all dotfiles, runs `brew bundle`, installs Oh-My-Zsh + Powerlevel10k, and wires the Claude statusline. See the repo `README.md` for the full runbook.
