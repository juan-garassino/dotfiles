# MIGRATE.md — move the whole dev setup + code to a new machine (Claude Code runs this)

**Claude Code: this is an executable runbook.** Run it ON THE NEW MACHINE (the target), top to
bottom; verify each step; STOP at every 🙋 (human-only: passwords, logins, clicks on the source).
The **source** machine is read-only and stays the rollback: only read from it — never modify,
delete or push from it.

**Goal: exactly the same dev setup** — shell, prompt, terminal, tools, configs, credentials,
Claude memory, and `~/Code` byte-for-byte (every repo, branch, stash, uncommitted change,
engenious, `.env`). NOT the OS itself: personal apps, documents and media are out of scope.

**How:** `install.sh` rebuilds the environment from this repo; `rsync` over ssh pulls `~/Code` +
`packages/home-carry.txt` from the source. `.venv`/`node_modules`/build caches are not copied —
they're OS/arch-specific and rebuilt (`envup`). GitHub is complete for personal repos (backup layer).

| Target (this machine) | `$OS` | Notes |
|---|---|---|
| Ubuntu desktop / laptop (incl. a 2015 MacBook running Ubuntu) | linux | path-compat symlink; 2015 MBP Wi-Fi: `sudo apt install bcmwl-kernel-source` (tether USB first) |
| WSL2 (Ubuntu inside Windows) | wsl | `~/Code` in the WSL ext4 home, **never** `/mnt/c`; font + Warp on the Windows side; systemd for Docker |
| Apple Silicon Mac (M5) | mac | Homebrew + Brewfile; same `/Users/juan-garassino` home → no path-compat needed |

| Source (old machine) | ssh on | home |
|---|---|---|
| Mac (e.g. the Intel today, later the M5) | System Settings/Preferences → Sharing → **Remote Login** | `/Users/juan-garassino` |
| Linux (e.g. this Ubuntu box, when the Intel Mac becomes Linux) | `sudo apt install -y openssh-server` | `/home/<user>` |

## 0. Bootstrap (human, one command — done if you are reading this inside Claude)

```bash
curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh | bash
```

## 1. Preflight (read-only)

- `git -C ~/Code/000-config/001-dotfiles pull --ff-only` — re-read this file if it changed.
- Detect target: `uname` (Darwin → mac), `grep -qi microsoft /proc/version` → wsl, else linux.
  `df -h ~` → need **≥ 150G free** (`~/Code` without envs is ~93G). Linux/WSL: `~/Code` on ext4 under `$HOME`.
- 🙋 Ask: which machine is the **source**, its address (`<name>.local` or IP) → `$SRC`, its user
  (`juan-garassino` on the Macs) → `$SRC_USER`. Then `S=$SRC_USER@$SRC`.

## 2. Guide the user on the source (they sit there; Claude instructs from here)

One at a time, wait for "done":
1. 🙋 **Enable ssh.** Mac: macOS 12 Monterey → Apple menu → **System Preferences → Sharing** → tick
   **Remote Login** → "Only these users" includes the user. macOS 13+ → **System Settings → General →
   Sharing → Remote Login** (ⓘ → allow the user). Linux source: `sudo apt install -y openssh-server`.
2. 🙋 **Read the address.** The Mac Sharing pane shows `ssh user@<name>` → `$SRC`. If `.local` doesn't
   resolve from here, use the IP: Mac `ipconfig getifaddr en0` (or `en1`); Linux `hostname -I`.
3. 🙋 **Keep it awake:** Mac → `caffeinate -dis` in a Terminal window left open; Linux →
   `systemd-inhibit --what=sleep:idle sleep infinity`. On power, same network (ethernet = fastest).
4. Verify from here: `ping -c 2 $SRC` and `nc -zv $SRC 22`.
Afterwards (step 10): remind the user to turn Remote Login off and stop caffeinate/inhibit.

## 3. ssh key to the source (no passwords inside Claude)

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_migrate -N "" -C "migrate-$(hostname)"
```
🙋 User runs in a normal terminal (asks the source password once):
`ssh-copy-id -i ~/.ssh/id_migrate.pub $S` (no ssh-copy-id → `cat ~/.ssh/id_migrate.pub | ssh $S 'mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys'`).
Verify `ssh -i ~/.ssh/id_migrate -o BatchMode=yes $S 'echo ok; uname; du -sh ~/Code'`. Then
`export RSYNC_RSH="ssh -i $HOME/.ssh/id_migrate"` and `SRC_HOME=$(ssh $S 'echo $HOME')`.

## 4. Temporary passwordless sudo (Linux/WSL/mac — Claude can't type passwords)

🙋 The user runs once in a normal terminal:
```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-migration && sudo chmod 440 /etc/sudoers.d/99-migration
```
Verify `sudo -n true`. **Removed in step 10.** (Declined → the user runs `./install.sh` in a second
terminal and Claude follows its output.)

## 5. Path compatibility (linux/wsl only, when `$SRC_HOME` ≠ `$HOME`)

Code, git worktrees (63 use absolute gitdirs), `~/.claude` memory and ~700 configs hard-code
`/Users/juan-garassino`. Make it resolve here:
`sudo mkdir -p /Users && sudo ln -sfn $HOME /Users/juan-garassino` (Linux source with a different
home: also `sudo ln -sfn $HOME $SRC_HOME`).

## 6. Pull the dev setup outside ~/Code

```bash
cd ~/Code/000-config/001-dotfiles
rsync -ar --info=progress2 --files-from=packages/home-carry.txt \
  --exclude .ssh/config --exclude .claude/settings.json --exclude .claude/settings.local.json \
  --exclude .claude/statusline-command.sh $S: ~/        # exit 23 = some listed path absent: fine
rsync -a $S:.claude.json ~/.claude.json.src            # MCP servers, merged below
```
- ngrok token: Mac source `rsync -a "$S:Library/Application Support/ngrok/ngrok.yml" ~/.config/ngrok/`
  (Linux source: `.config/ngrok/ngrok.yml`; mac target: `~/Library/Application Support/ngrok/`).
- Perms: `chmod 600 ~/.secrets ~/.secrets-cheatsheet.md ~/.engenious_university.env; chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_*; chmod 644 ~/.ssh/*.pub`.
- Keys: linux → `eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_work`;
  mac → `ssh-add --apple-use-keychain …`. Verify `ssh -T git@github.com` → `Hi juan-garassino`.
- **Claude memory is keyed by path:** if `$SRC_HOME` ≠ `$HOME`, for each `~/.claude/projects/<src-slug>-*`
  also `cp -a` it to the slug with `$HOME` (`/` → `-`), keeping the original.
- 🙋 Ask once whether to also bring personal data dirs (Documents, other Downloads, ML results) — default **no**.

## 7. Pull ~/Code (~93G, resumable — just re-run if interrupted)

```bash
rsync -aH --partial --info=progress2 \
  --exclude .venv --exclude venv --exclude '.venv-*' --exclude node_modules --exclude .next \
  --exclude __pycache__ --exclude .pytest_cache --exclude .mypy_cache --exclude .terraform \
  --exclude .DS_Store --exclude '._*' \
  --exclude /000-config/001-dotfiles/ --exclude /000-config/dotfiles-uv-worktree/ \
  $S:Code/ ~/Code/
```
The dotfiles checkouts are excluded (this machine has its own clone on `main`). macOS sources ship
rsync 2.6.9 — it works, just scans all ~665k files before sending; **don't `brew install rsync` on an
unsupported (old) Mac** (it compiles OpenSSL from source). **Byte-verify:** same command with
`-anc --itemize-changes` → must print nothing.

## 8. Install the toolchain (Claude runs it, narrating each phase)

```bash
cd ~/Code/000-config/001-dotfiles
git remote set-url origin git@github.com:juan-garassino/dotfiles.git && git fetch
./install.sh
```
- **linux/wsl:** apt (core, build deps, ffmpeg, tesseract, git-lfs, go, mkcert, `postgresql-client`) +
  `linux-tools.sh` (docker+compose, gcloud, terraform, kubectl, helm, aws, minikube, k3d, act, runpodctl,
  cloud-sql-proxy, ngrok, rustup, Warp, llm, ollama). wsl: skips Warp (use Warp for Windows) and enables
  systemd → 🙋 `wsl --shutdown` in PowerShell, reopen, re-run `./install.sh`.
- **mac:** Homebrew (noninteractive) + Brewfile.
- **all:** MesloLGS NF + terminal font 14, OMZ + plugins, Powerlevel10k + `~/.p10k.zsh`, Warp settings
  (`phenomenon`), uv + Python 3.11/3.12/3.13 + ruff/pre-commit, nvm + LTS + npm globals, VS Code
  settings + 48 extensions, global git ignore, Claude status line/settings/skills/agents.
- **Postgres = containers only** (host gets `psql`/`pg_dump`). See step 9 for data.
- After: `sudo chsh -s $(command -v zsh) $USER`; 🙋 **re-login** (zsh + docker group); reopen Claude
  here and continue. First zsh: **decline** the p10k wizard. Open Warp → should look like the old machine.

### Guided logins (one at a time; print the command, user runs it, verify)
1. 🙋 `gh auth login` → GitHub.com · SSH · skip key upload · browser → Authorize as `juan-garassino`.
2. 🙋 again → Authorize as `j-garassino-engenious`. Verify `gh auth status` (both) and the cd-switch:
   `~/Code` → `juan-garassino`, `~/Code/002-engenious` → `j-garassino-engenious`.
3. GCP: carried `~/.config/gcloud` usually works — `gcloud auth list`; `gcloud projects list` shows
   `garassino-ml/ai/op` + `engenious-mcp-prod`. Else 🙋 `gcloud auth login` + `gcloud auth application-default login`.
4. AWS: `aws sts get-caller-identity` (carried `~/.aws`); report failures, don't guess.
5. runpod: `runpodctl config --apiKey "$RUNPOD_API_KEY"` (key from `~/.secrets`). Codex: 🙋 `codex login`.
   ngrok: `ngrok config check`.

## 9. Settle the code and data

- **MCP servers:** merge the source's `~/.claude.json` servers (user + per-project), rewriting paths:
  ```bash
  jq -s --arg h "$HOME" --arg s "$SRC_HOME" '.[0] as $n | .[1] as $o
    | $n + {mcpServers: (($n.mcpServers // {}) + ($o.mcpServers // {})),
            projects: (($n.projects // {}) * (($o.projects // {}) | with_entries(.key |= sub("^"+$s; $h))
                       | map_values({mcpServers: (.mcpServers // {})})))}' \
    ~/.claude.json ~/.claude.json.src > /tmp/cj && mv /tmp/cj ~/.claude.json && chmod 600 ~/.claude.json
  ```
  Then restart Claude and check `claude mcp list` (discord-me + marketing_agent servers).
- **git, per repo** (Linux is case-sensitive; Mac paths moved):
  `find ~/Code -name .git -prune -exec sh -c 'git -C "$(dirname "$1")" config core.ignorecase false' _ {} \;`
  then `git worktree repair` / `git worktree prune` in repos with worktrees (ai-underwriter OCR +
  prediction, deepVogue, carreer-navigator, PromptPlot). First `git status` per repo rehashes — normal.
- **Scratch-worktree WIP** (uncommitted work from `~/.claude-tmp` worktrees): `~/env-snapshots/worktree-wip-*/INDEX.txt`
  lists branch + repo; apply `*.patch` and untar `*.untracked.tgz` in a fresh worktree of that branch when the user wants it.
- **Databases:** start each compose stack, then restore: aiuw → `gunzip -c ~/env-snapshots/aiuw-pgdumpall-*.sql.gz | docker exec -i aiuw-postgres psql -U aiuw -d postgres`;
  Le Wagon DE → untar `lewagon-de-pgdata-*.tgz` into the `lewagon-de_de-pgdata` volume before first start.
- **Envs:** `mysandbox` once; project envs on touch with `envup`. `terraform init` where `.terraform` was dropped.
- **macOS-only bits in code** (report, fix only if the user asks): `caffeinate` in boundaryBrush/dataDiffusion
  Makefiles (→ `systemd-inhibit`), `brew install` hints in marketing_agent/deepCab/deepMaze Makefiles,
  `engenious_university` launchd plist + `run_bot_cron.sh` (→ a systemd user timer on Linux).
- Loose code carried from the source's Desktop/Downloads: suggest moving into `~/Code`.

## 10. Verify + clean up (print a PASS/FAIL scorecard)

- `zsh -i -c 'source custom_scripts/preflight_gauntlet.sh'` (OS-specific checks → N/A with reason).
- Look: p10k icons + ochre `personal`; `cd ~/Code/002-engenious` → burgundy `work`; Warp `phenomenon`.
- Tools: `docker compose version`, `minikube version`, `kubectl version --client`, `psql --version`,
  `terraform -version`, `gcloud --version`, `rustc --version`, `ngrok version`, `claude mcp list`.
- Byte parity: `custom_scripts/code_fingerprint.sh` here vs on the source (`ssh $S zsh ~/Code/000-config/001-dotfiles/custom_scripts/code_fingerprint.sh`
  — or the dotfiles-uv-worktree path on the Intel Mac) → `diff` empty.
- Teaching stacks (containers only): ask first (GBs) → `custom_scripts/validate_teaching.sh` + `make build-mle`.
- 3 `envup` spot-checks; `docker run --rm hello-world`; `uv run --python 3.12 python -V`.
- **Clean up:** `sudo rm /etc/sudoers.d/99-migration` (verify `sudo -n true` now FAILS); remind: Remote
  Login off + stop caffeinate on the source; `rm ~/.claude.json.src` once MCPs work.

## Hard rules

- Source is read-only: only `rsync`/`ssh` reads. No `--delete` toward it, no installs on it.
- Never echo secret values; never commit `~/.secrets`, keys, GCP JSON, `.env` into any repo.
- Push protection / rule violations: report, never bypass. Engenious never goes to personal remotes.
- Ambiguous → one short question.

## State of GitHub (2026-10-14) — the backup layer

- All personal repos, all branches pushed; dirty trees committed (`wip/pre-migration-2026-10-14`
  where the branch was the default). Pre-rewrite backups: `~/git-bundles/pre-fix-2026-10-14/`.
- 10 formerly loose dirs are private repos (`candidate-assistant`, `graphrag-integration`,
  `custom-graphrag`, `chroma-rag`, `emoji-generation`, `adversarial-diffusion`, `orchestration-coreo`,
  `multiagent-orchestrator`, `nlsql`, `assessment`). SelfGPT → fork `juan-garassino/SelfGPT` (remote `mine`).
- rsync-only by design: `002-engenious`, `000-config` root (GCP creds), `012-temps`, loose non-repo
  files, neuefische `ds-curriculum` local commit, `.env`, `~/.claude`, keys.
- Keys to rotate (were in local-only history): SelfGPT OpenAI key, achievementsAI Azure key.
