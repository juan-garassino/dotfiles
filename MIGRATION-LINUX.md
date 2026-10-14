# MIGRATION-LINUX.md — Intel Mac → Ubuntu (Claude Code runs this on the Linux box)

**Claude Code on Linux: this is an executable runbook.** Follow it top to bottom, verify each
step, and STOP at every 🙋 (human-only: logins, secrets a machine can't fabricate, physical
transfer). The Intel Mac is the **read-only source and the rollback** — never modify, delete, or
push from it during this run. Pairs with `MIGRATION.md` (macOS/M5 variant) and `SETUP.md`.

**Carrier model:** personal repos come from **GitHub**; engenious (work IP) + all non-git state
come from the **payload** staged on the Intel (`$SRC`). Nothing secret ever touches this public repo.

## 0. Human bootstrap (the only manual part, ~5 commands, on Ubuntu)

```bash
sudo apt-get update && sudo apt-get install -y git curl openssh-server
curl -fsSL https://claude.ai/install.sh | bash            # Claude Code; then `claude` → log in (🙋)
mkdir -p ~/Code/000-config
git clone -b uv-only https://github.com/juan-garassino/dotfiles ~/Code/000-config/001-dotfiles
cd ~/Code/000-config/001-dotfiles && claude               # say: "execute MIGRATION-LINUX.md"
```
(https clone because SSH keys aren't here yet; the remote is switched to SSH in step 4.)

## Intel-side prerequisites (done BEFORE this run; Claude: verify, don't redo)

Payload staged on the Intel at `$SRC` (e.g. `intel-mac:stage/`, or a mounted ext4 drive `/mnt/x/stage/`):
`custom_scripts/stage_handcarry.sh --to <stage>` output + `002-engenious/` rsync + `~/git-bundles/`
+ a fresh `repo-manifest-<date>.txt` + `SHA256SUMS`. Intel gate already green: `repo_sweep.sh` (personal
= 0 flagged), `verify_coverage.sh` = 0 uncovered, `~/env-snapshots/fingerprint-intel-<date>.txt` written.
If any is missing → STOP and tell the user; do not improvise on the Intel.

## 1. Preflight (read-only)

- `uname -m` (expect x86_64 or aarch64), `lsb_release -d` (Ubuntu 24.04), `df -h ~` — need **≥ 200G free on ext4**.
  `~/Code` MUST live on ext4 under `$HOME`, **never** the NTFS/Windows partition (no perms/symlinks).
- `id -un` → record as `$LU`. Home is `/home/$LU`, **not** `/Users/juan-garassino`.
- Reachability of `$SRC`: `ssh -o BatchMode=yes <intel> true` or `ls $SRC`. 🙋 if unreachable.

## 2. Pull + verify the payload

```bash
mkdir -p ~/stage && rsync -aE --partial --info=progress2 "$SRC"/ ~/stage/
cd ~/stage && sha256sum -c SHA256SUMS | grep -v ': OK$' || echo "payload verified"
```
Any mismatch → STOP. Then place (home-relative layout is preserved under `~/stage/handcarry/`):
`~/.secrets` `~/.secrets-cheatsheet.md` (chmod 600), `~/.ssh/*` (dir 700, keys 600, `.pub` 644),
`~/.aws`, `~/.config/gcloud`, `~/env-snapshots`, `~/git-bundles`, `Code/000-config/002-gcp-credentials/`.
Do **not** copy `Library/Application Support/*` (macOS-only). Then `eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_work`
and verify `ssh -T git@github.com` → `Hi juan-garassino`; `ssh -T git@github-work` → work account.

## 3. `~/.claude` (memory is keyed by the cwd path!)

Copy `handcarry/.claude/` → `~/.claude/` **except** `settings.json`/`settings.local.json`
(let `install.sh` restore the sanitized one; then re-add Linux-valid allow entries). Claude Code keys
`~/.claude/projects/<slug>/` by the working path, so macOS memory/standing/plans for
`/Users/juan-garassino/Code…` are invisible at `/home/$LU/Code…`. Fix by **copying** each
`~/.claude/projects/-Users-juan-garassino-*` dir to `-home-$LU-*` (`cp -a`, keep originals). Memory
files may cite `/Users/...` paths — treat as historical, verify before acting.

## 4. Dotfiles + toolchain

```bash
cd ~/Code/000-config/001-dotfiles
git remote set-url origin git@github.com:juan-garassino/dotfiles.git && git fetch
./install.sh        # Linux branch: apt (packages/apt.txt), gh, VS Code, uv, OMZ+p10k, symlinks, statusline, skills/agents
```
Don't open new terminals mid-install. Then: `chsh -s $(command -v zsh)` 🙋 (needs password), `exec zsh`.
Not covered by install.sh — do these explicitly:
- **Docker Engine** (official apt repo, not docker.io) + `sudo usermod -aG docker $LU`; verify `docker run --rm hello-world` (re-login for group).
- **uv**: `which uv` → `~/.local/bin/uv` (installer.sh); never pip/pipx/pyenv. `uv python install 3.11 3.12`.
- **Node 20 + gcloud SDK** only if needed by the project being touched (on demand).
- Postgres: `apt.txt` still lists host `postgresql` + pyenv build-deps — policy is **DBs in containers, no pyenv**. Skip/purge host postgres; keep the build-deps (harmless). Restore DB data from `env-snapshots/*pgdata*.tar.gz` into a container only if the user asks.
- 🙋 `gh auth login` twice (personal `juan-garassino`, work `j-garassino-engenious`); `gcloud auth login` + `application-default login` (skip if `~/.config/gcloud` carried and valid).

## 5. Code

1. **Personal fleet** — clone to the **exact old paths** (`includeIf` identity + `gh_auto_switch` key off them):
   `custom_scripts/code_manager.sh` driven by the newest `repo-manifest-*.txt` (`PATH | REMOTE`). Skip
   `002-engenious/*`, `NO-REMOTE` rows, and `lewagon/official-content/*` unless reachable. Report every clone failure; don't retry blindly.
2. **Case-sensitivity check:** macOS APFS was case-insensitive, ext4 is not. After clones, `git status` any repo with
   `D`/`??` pairs differing only by case → report, don't fix silently.
3. **Engenious** — `rsync -aE ~/stage/Code/002-engenious/ ~/Code/002-engenious/` (working trees incl. dirty + worktree fleet).
   For the 3 no-remote repos (`my-ai-underwriter`, `engenious_university`, `discord-me-mcp`) also verify against `~/git-bundles`
   (`git bundle verify`). **Never push engenious anywhere**; work remotes only via the work SSH alias.
4. **Loose non-git dirs** (`006-research-prototypes/{OTH-candidate-assistant,GRAPH-*,DIF-*,…}`, `005-products/001-assessment`,
   `ds-book-template` with its local-only commit): already inside the engenious/payload rsync? If not, copy from `~/stage/handcarry/Code/…`.
5. **`.env` files:** `custom_scripts/env_registry.sh --restore-from ~/stage/Code` (never overwrites; re-applies 600).
6. **Absolute paths:** `grep -rIl '/Users/juan-garassino' ~/Code --include='*.md' --include='*.sh' --include='*.toml' --include='*.yml' --include='.envrc' 2>/dev/null | head -50`.
   Report only; for tooling you must run (scripts, tfvars), prefer `$HOME`. Don't mass-sed repos. Optional compat: `sudo ln -s /home/$LU /Users/juan-garassino` 🙋 (ask first).
7. `mysandbox` once (global `~/.venv-sandbox`). Per-project envs on touch: `envup`.

## 6. Verify (all must pass; print a PASS/FAIL scorecard)

- `zsh -n ~/Code/000-config/001-dotfiles/shell/zshrc`; `zsh -i -c 'source custom_scripts/preflight_gauntlet.sh'` (macOS-only checks → mark N/A with reason, never silently skip).
- Identity: in `~/Code` → personal email + `gh api user -q .login`; in `~/Code/002-engenious` → work.
- `custom_scripts/code_fingerprint.sh > /tmp/fp-linux.txt`; `diff <(grep -v 002-engenious ~/env-snapshots/fingerprint-intel-*.txt) <(grep -v 002-engenious /tmp/fp-linux.txt)` → empty (expected exceptions: lewagon official-content, anything the user waived).
- 3 `envup` spot-checks (one pyproject, one requirements, one engenious), `docker run hello-world`, `claude --version`, statusline renders.
- Final report to user: PASS/FAIL table, every skipped/N-A item with reason, anything left on Intel only.

## Hard rules

- Intel is read-only; no `--force`, no deletes, no `git push` from here except the dotfiles repo if the user asks.
- Never echo secret values; never commit `~/.secrets`, keys, GCP JSON, `.env` into any repo.
- GitHub push protection / rule violations: report, never bypass.
- Ambiguous → ask the user (AskUserQuestion), one short question.

## Known open items (as of 2026-10-14)

- `001-archives/001-achievementsAI` branch `knowledge-graph`: GitHub push protection blocks it (Azure key in history, commit `a968f3e`, `achievements_ai_graphrag/logs/indexing-engine.log`) → arrives via payload/bundle, not GitHub.
- `009-mini-networks`, `003-carreer-navigator` have diverged branches vs origin (non-fast-forward) — GitHub copy is NOT equal to Intel for those; use payload/bundle copy or reconcile first.
- Third-party upstream clones (neuefische `ds-curriculum`/`mle-course-curriculum`, `SelfGPT`, `diffusion-point-cloud`) have local-only changes → payload only.
