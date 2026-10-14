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
curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh | bash
```

## 1. Preflight (read-only)

- **First:** `git -C ~/Code/000-config/001-dotfiles pull --ff-only` — this runbook may have been
  improved since bootstrap cloned it. If the file changed, re-read it before continuing.
- `lsb_release -d` (target Ubuntu 26.04), `uname -m`, `df -h ~` — need **≥ 150G free on ext4**
  (`~/Code` without envs is ~93G). `~/Code` MUST be on ext4 under `$HOME`, never the NTFS/Windows partition.
- `id -un` → `$LU`. Home is `/home/$LU`, not `/Users/juan-garassino`.
## 2. Guide the user on the Mac (they sit at the Mac; Claude instructs from here)

Give these one at a time, wait for "done" after each:

1. 🙋 **Turn on Remote Login.** The old Mac is macOS 12 Monterey:
    Apple menu → **System Preferences → Sharing** → tick **Remote Login** →
   "Allow access for: **Only these users**" → make sure **juan-garassino** is listed (add with **+**).
   (macOS 13+ would be System Settings → General → Sharing → Remote Login.)
2. 🙋 **Read the address.** The Sharing pane now says *"To log in to this computer remotely, type
   `ssh juan-garassino@<something>`"* — ask the user to read out `<something>` → `$MAC`.
   If it is a `.local` name that doesn't resolve from Linux, ask for the IP instead: in a Mac
   Terminal `ipconfig getifaddr en0` (Wi-Fi) or `en1` → `$MAC`.
3. 🙋 **Keep the Mac awake** for the copy: in a Mac Terminal run `caffeinate -dis` and leave that
   window open (Ctrl+C when the migration is done). Mac on power; same network as this machine
   (ethernet cable to the router on both = fastest).
4. Verify from here: `ping -c 2 $MAC` and `nc -zv $MAC 22` → port 22 open.

After the whole migration passes: remind the user to untick **Remote Login** again and stop
`caffeinate`.

## 3. ssh access to the Mac (no passwords inside Claude)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_mac_pull -N "" -C "linux-pull"
```
🙋 The user runs in a normal terminal (it asks the Mac password once):
`ssh-copy-id -i ~/.ssh/id_mac_pull.pub juan-garassino@$MAC`
Verify: `ssh -i ~/.ssh/id_mac_pull -o BatchMode=yes juan-garassino@$MAC 'echo ok; du -sh ~/Code'`.
Then `export RSYNC_RSH="ssh -i $HOME/.ssh/id_mac_pull"` for every rsync below.

## 4. Path compatibility (recommended)

🙋 (sudo) `sudo mkdir -p /Users && sudo ln -sfn /home/$LU /Users/juan-garassino`
Old absolute paths keep working: git worktree `.git` files, `~/.claude` project memory, scripts
and configs that hard-coded `/Users/juan-garassino/...`. Harmless, removable later.

## 5. Pull home-level config

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

## 6. Pull `~/Code` (the big one, ~93G — resumable, just re-run if interrupted)

```bash
rsync -aH --partial --info=progress2 \
  --exclude .venv --exclude venv --exclude node_modules --exclude __pycache__ \
  --exclude .pytest_cache --exclude .mypy_cache --exclude .DS_Store --exclude '._*' \
  --exclude /000-config/001-dotfiles/ --exclude /000-config/dotfiles-uv-worktree/ \
  $S:Code/ ~/Code/
```
The dotfiles checkouts are excluded: this machine already has its own clone on `main`
(the Mac's are a `main` checkout + a worktree tied to Mac paths).
**Byte-verify:** run the same command with `-anc --itemize-changes` (checksum dry-run) → must print
nothing. Wi-Fi: 1–3 h; ethernet: minutes.

## 7. Install the toolchain (Claude runs it and narrates)

**sudo without a password, temporarily.** `install.sh` calls `sudo` many times and Claude cannot
type a password. 🙋 Ask the user to run, once, in a normal terminal:
```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-migration && sudo chmod 440 /etc/sudoers.d/99-migration
```
Verify with `sudo -n true`. It is **removed in step 9** (`sudo rm /etc/sudoers.d/99-migration`) —
never leave it behind. (If the user declines: they run `./install.sh` themselves in a second
terminal and Claude follows the output and fixes failures.)

```bash
cd ~/Code/000-config/001-dotfiles
git remote set-url origin git@github.com:juan-garassino/dotfiles.git && git fetch
./install.sh
```
What it installs — tell the user each phase as it runs:
- **apt:** core CLI, build deps, ffmpeg, tesseract, git-lfs, go, mkcert, `postgresql-client` (psql/pg_dump).
- **linux-tools.sh:** docker + compose (+ docker group), gcloud, terraform, kubectl, helm, aws v2,
  **minikube**, k3d, act, runpodctl, cloud-sql-proxy, **Warp**, llm, ollama.
- **look:** MesloLGS NF + terminal font 14 pt, Oh-My-Zsh + plugins, Powerlevel10k + `~/.p10k.zsh`,
  Warp settings (theme `phenomenon`, MesloLGS NF 14, honors the p10k prompt).
- **Python/Node:** uv + Pythons 3.11/3.12 + ruff/pre-commit, nvm + LTS + npm globals.
- **Claude:** status line, settings (merged into a fresh one), skills, agents. **VS Code** + 48 extensions.

**Postgres is never a host server** (policy: databases run in containers). For a DB:
`docker run -d --name pg -e POSTGRES_PASSWORD=dev -p 5432:5432 -v pgdata:/var/lib/postgresql/data postgres:16`
or the project's own `docker compose`. Restore old data from `~/env-snapshots/*pgdata*` only if asked.

After install: `chsh` may need the password 🙋 (`sudo chsh -s $(command -v zsh) $USER` works under
NOPASSWD). **Re-login once** (zsh + docker group), reopen Claude in this repo and continue. First zsh:
**decline** the p10k wizard. Open **Warp** from the app menu → it should look like the Mac
(dark `phenomenon` theme, p10k prompt with icons).

### Guided logins (Claude walks the user through each, one at a time)

Claude cannot type passwords or click Authorize. For each login: print the exact command, say
which answers to pick, let the user run it (`! <command>` in Claude, or a second terminal),
wait for "done", then **verify** before moving on.

1. 🙋 **GitHub personal** — `gh auth login` → GitHub.com · SSH · skip key upload (keys came with
   rsync) · *Login with a web browser* → copy the one-time code, Authorize as `juan-garassino`.
2. 🙋 **GitHub work** — same command again, Authorize as `j-garassino-engenious`.
   Verify: `gh auth status` lists both; `cd ~/Code && gh api user -q .login` → `juan-garassino`,
   `cd ~/Code/002-engenious && gh api user -q .login` → `j-garassino-engenious` (the cd-hook switches).
3. **GCP** — the carried `~/.config/gcloud` usually just works. Check first:
   `gcloud auth list` and `gcloud projects list --format='value(projectId)'` (expect `garassino-ml`,
   `garassino-ai`, `garassino-op`, `engenious-mcp-prod`). Only if that fails or tokens expired:
   🙋 `gcloud auth login` then 🙋 `gcloud auth application-default login` (browser, Authorize as
   `juan.garassino@hotmail.com`), then `gcloud config set project garassino-ml`. Re-run the check.
4. **AWS (work)** — carried `~/.aws`; verify `aws sts get-caller-identity`. If it fails, report it —
   don't guess credentials.

## 8. Settle the code

- Nothing to clone — everything came with rsync, `.env` files included.
- Git worktrees (ai-underwriter fleet, etc.) resolve through the `/Users` symlink; if any shows
  `fatal: not a git repository`, run `git worktree repair` in its main repo.
- `mysandbox` once; project envs rebuild on touch with `envup` (`uv sync` / requirements).
- Report (don't mass-fix) hard-coded `/Users/juan-garassino` paths that matter for Linux tooling.

## 9. Verify (print a PASS/FAIL scorecard)

- `zsh -i -c 'source custom_scripts/preflight_gauntlet.sh'` (macOS-only checks → N/A with reason).
- Look: prompt shows clean icons + ochre `personal`; `cd ~/Code/002-engenious` → burgundy `work`.
- Identity: `git config user.email` + `gh api user -q .login` in `~/Code` vs `~/Code/002-engenious`.
- Byte parity: `custom_scripts/code_fingerprint.sh` here vs the same script run on the Mac over ssh
  (`ssh $S zsh ~/Code/000-config/dotfiles-uv-worktree/custom_scripts/code_fingerprint.sh`) → `diff` empty.
- **Teaching stacks** (Le Wagon / Spiced run ONLY in containers; native Docker here, no colima):
  `custom_scripts/validate_teaching.sh spiced lewagon-ds lewagon-da lewagon-de` (build → up → smoke →
  down, one at a time; long first build), then `cd ~/Code/004-lewagon-spiced/teaching-containers &&
  make build-mle` for the 5th stack. Ask the user before starting — it downloads several GB.
- `docker run --rm hello-world`, `uv run --python 3.12 python -V`, `claude --version`, statusline renders,
  3 `envup` spot-checks (a pyproject repo, a requirements repo, an engenious repo).
- Tools: `docker compose version`, `minikube version`, `kubectl version --client`, `psql --version`,
  `terraform -version`, `gcloud --version`, `warp-terminal` present.
- **Clean up:** `sudo rm /etc/sudoers.d/99-migration` and confirm `sudo -n true` now FAILS; remind the
  user to untick Remote Login on the Mac and stop `caffeinate`.
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
