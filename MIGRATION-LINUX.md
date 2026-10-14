# MIGRATION-LINUX.md — old Mac → Ubuntu, rsync-first (Claude Code runs this on the Linux box)

**Claude Code on Linux: this is an executable runbook.** Follow it top to bottom, verify each
step, and STOP at every 🙋 (human-only: passwords, logins, secrets). The Mac is the **read-only
source and the rollback**: only read from it, never modify, delete or push from it.

**Carrier model:** `rsync` over ssh pulls `~/Code` and the home-level config straight from the
Mac — byte-for-byte, including engenious, `.env` files, dirty trees and loose folders. GitHub is
already complete for personal repos (see the bottom section); it is the backup and the sync
layer from now on, not the transport. `.venv` / `node_modules` / caches are NOT copied —
macOS binaries are useless on Linux; they are rebuilt with `envup`.

## 0. Bootstrap (human, one command — already done if you are reading this in Claude)

```bash
curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/uv-only/bootstrap.sh | bash
```

## 1. Preflight (read-only)

- `lsb_release -d` (target Ubuntu 26.04), `uname -m`, `df -h ~` — need **≥ 150G free on ext4**
  (`~/Code` without envs is ~93G). `~/Code` MUST be on ext4 under `$HOME`, never the NTFS/Windows partition.
- `id -un` → `$LU`. Home is `/home/$LU`, not `/Users/juan-garassino`.
- 🙋 Ask for the Mac's address (`<name>.local` or IP) → `$MAC`, user `juan-garassino`.
  The Mac needs **Remote Login ON** (System Settings → General → Sharing).

## 2. ssh access to the Mac (no passwords inside Claude)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_mac_pull -N "" -C "linux-pull"
```
🙋 The user runs in a normal terminal (it asks the Mac password once):
`ssh-copy-id -i ~/.ssh/id_mac_pull.pub juan-garassino@$MAC`
Verify: `ssh -i ~/.ssh/id_mac_pull -o BatchMode=yes juan-garassino@$MAC 'echo ok; du -sh ~/Code'`.
Then `export RSYNC_RSH="ssh -i $HOME/.ssh/id_mac_pull"` for every rsync below.

## 3. Path compatibility (recommended)

🙋 (sudo) `sudo mkdir -p /Users && sudo ln -sfn /home/$LU /Users/juan-garassino`
Old absolute paths keep working: git worktree `.git` files, `~/.claude` project memory, scripts
and configs that hard-coded `/Users/juan-garassino/...`. Harmless, removable later.

## 4. Pull home-level config

```bash
S=juan-garassino@$MAC
rsync -a --info=progress2 $S:'.secrets .secrets-cheatsheet.md' ~/
rsync -a $S:.ssh/ ~/.ssh/ --exclude config            # ~/.ssh/config is symlinked by install.sh
rsync -a --info=progress2 $S:.claude/ ~/.claude/ \
  --exclude settings.json --exclude settings.local.json --exclude statusline-command.sh
rsync -a $S:.config/gcloud/ ~/.config/gcloud/
rsync -a $S:.aws/ ~/.aws/
rsync -a --info=progress2 $S:env-snapshots $S:git-bundles ~/
chmod 600 ~/.secrets ~/.secrets-cheatsheet.md; chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_*; chmod 644 ~/.ssh/*.pub
```
Excluded on purpose: `settings.json` and the statusline (install.sh restores the sanitized
Linux-safe versions), `~/.ssh/config` (symlink). Then `eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_work`;
verify `ssh -T git@github.com` → `Hi juan-garassino`.

**Claude memory is keyed by path:** for each `~/.claude/projects/-Users-juan-garassino-*` dir, also
`cp -a` it to `-home-$LU-*` (keep the original) so sessions at `/home/$LU/Code/...` find their memory.

## 5. Pull `~/Code` (the big one, ~93G — resumable, just re-run if interrupted)

```bash
rsync -aH --partial --info=progress2 \
  --exclude .venv --exclude venv --exclude node_modules --exclude __pycache__ \
  --exclude .pytest_cache --exclude .mypy_cache --exclude .DS_Store --exclude '._*' \
  --exclude /000-config/001-dotfiles/ --exclude /000-config/dotfiles-uv-worktree/ \
  $S:Code/ ~/Code/
```
The dotfiles checkouts are excluded: this machine already has its own clone on `uv-only`
(the Mac's are a `main` checkout + a worktree tied to Mac paths).
**Byte-verify:** run the same command with `-anc --itemize-changes` (checksum dry-run) → must print
nothing. Wi-Fi: 1–3 h; ethernet: minutes.

## 6. Install the toolchain

```bash
cd ~/Code/000-config/001-dotfiles
git remote set-url origin git@github.com:juan-garassino/dotfiles.git && git fetch
./install.sh      # apt + linux-tools.sh (docker, gcloud, terraform, kubectl, helm, aws), uv, nvm,
                  # MesloLGS NF + terminal font, OMZ + p10k, symlinks, Claude statusline/settings/skills
```
Don't open new terminals mid-install. 🙋 `chsh` asks the password; first zsh: **decline** the p10k
wizard. Re-login once (zsh default shell + docker group). 🙋 `gh auth login` twice (personal
`juan-garassino`, work `j-garassino-engenious`); `gcloud auth login` only if the carried
`~/.config/gcloud` tokens fail.

## 7. Settle the code

- Nothing to clone — everything came with rsync, `.env` files included.
- Git worktrees (ai-underwriter fleet, etc.) resolve through the `/Users` symlink; if any shows
  `fatal: not a git repository`, run `git worktree repair` in its main repo.
- `mysandbox` once; project envs rebuild on touch with `envup` (`uv sync` / requirements).
- Report (don't mass-fix) hard-coded `/Users/juan-garassino` paths that matter for Linux tooling.

## 8. Verify (print a PASS/FAIL scorecard)

- `zsh -i -c 'source custom_scripts/preflight_gauntlet.sh'` (macOS-only checks → N/A with reason).
- Look: prompt shows clean icons + ochre `personal`; `cd ~/Code/002-engenious` → burgundy `work`.
- Identity: `git config user.email` + `gh api user -q .login` in `~/Code` vs `~/Code/002-engenious`.
- Byte parity: `custom_scripts/code_fingerprint.sh` here vs the same script run on the Mac over ssh
  (`ssh $S zsh ~/Code/000-config/dotfiles-uv-worktree/custom_scripts/code_fingerprint.sh`) → `diff` empty.
- `docker run --rm hello-world`, `uv run --python 3.12 python -V`, `claude --version`, statusline renders,
  3 `envup` spot-checks (a pyproject repo, a requirements repo, an engenious repo).
- Final report: PASS/FAIL table, every N/A or skip with its reason.

## Hard rules

- The Mac is read-only: only `rsync`/`ssh` reads from it. No `--delete` toward the Mac, ever.
- Never echo secret values; never commit `~/.secrets`, keys, GCP JSON or `.env` into any repo.
- Push protection / rule violations: report, never bypass. Engenious never goes to personal remotes.
- Ambiguous → one short question to the user.

## State of GitHub (2026-10-14) — the backup layer

- All personal repos, all branches, pushed; dirty trees committed (`wip/pre-migration-2026-10-14`
  where the branch was the default). Pre-rewrite backups: `~/git-bundles/pre-fix-2026-10-14/`.
- 10 formerly loose dirs are now private repos (`candidate-assistant`, `graphrag-integration`,
  `custom-graphrag`, `chroma-rag`, `emoji-generation`, `adversarial-diffusion`, `orchestration-coreo`,
  `multiagent-orchestrator`, `nlsql`, `assessment`). SelfGPT → fork `juan-garassino/SelfGPT` (remote `mine`).
- Not on GitHub by design (rsync only): `002-engenious`, `000-config` root (GCP creds), `012-temps`,
  ~100 loose non-repo files/dirs, neuefische `ds-curriculum` local commit, `.env`, `~/.claude`, keys.
- Keys to rotate (were in local-only history): SelfGPT OpenAI key, achievementsAI Azure key.
