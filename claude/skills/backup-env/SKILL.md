---
name: backup-env
description: Back up Juan's full dev environment to the private dotfiles repo — refresh Brewfile, re-sanitize Claude settings, secret-scan, commit & push. Use when the user says "backup my env", "/backup-env", "save my environment", "sync my dotfiles", "update my dotfiles backup", or after changing shell / p10k / Claude Code config.
---

# backup-env

Refreshes and pushes Juan's environment-replication kit — the `001-dotfiles` repo at
`~/Code/000-config/001-dotfiles` (remote: `github.com/juan-garassino/dotfiles`, private).

## What it captures
- **Shell** — `zshrc`, `zshenv`, `aliases`, `gitconfig*` (symlinked, always live)
- **Prompt/theme** — `p10k.zsh` (symlinked)
- **Claude Code** — `claude/statusline-command.sh` (symlinked) + a **sanitized** `claude/settings.json` snapshot
- **Toolchain** — `Brewfile` (regenerated each run: formulae, casks, fonts incl. the Nerd Font, taps)

**Secrets are never captured.** API keys live in `~/.secrets` (chmod 600, outside any repo), sourced by zshrc. On a new machine they're copied manually.

## How to run
```
bash ~/Code/000-config/001-dotfiles/custom_scripts/backup_env.sh
```
Add `--no-push` to stage + commit locally without pushing.

The script: (1) regenerates `Brewfile`, (2) re-sanitizes `settings.json` (strips API keys + personal-path allow entries), (3) runs a high-signal **secret-scan gate** over all tracked/untracked files, (4) `git add -A`, timestamped commit, push.

## If the secret-scan ABORTS
A real key leaked into a tracked file. **Do not bypass.** Move the key into `~/.secrets`, remove it from the offending file, re-run. Never `--no-verify` or hand-edit past the gate.

## New-machine restore
```
git clone git@github.com:juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles
cd ~/Code/000-config/001-dotfiles && ./install.sh
# then copy ~/.secrets over manually (scp/AirDrop) and: chmod 600 ~/.secrets
```
`install.sh` symlinks all dotfiles, runs `brew bundle`, installs Oh-My-Zsh + Powerlevel10k, and wires the Claude statusline. See the repo `README.md` for the full runbook.
