# MIGRATION.md — Old Intel Mac → New Apple Silicon Mac (clean rebuild)

**Claude Code: this is an executable runbook.** Follow it end-to-end, verify each step,
and STOP at every 🙋 (human-only: secrets, keys, physical file transfer). The strategy is
a **clean rebuild** — fresh macOS, this repo's installer, repos re-cloned, a short list of
private files hand-carried. No Migration Assistant. The old machine is never modified, so
it remains the rollback at every step.

This runbook pairs with the `uv-only` branch: **no pyenv anywhere**. Python is managed by
uv (`uv python install`, per-project `.venv`, global `~/.venv-sandbox`). See SETUP.md for
how the environment works day-to-day.

---

## ⚠️ Audit 2026-09-17 — gap closures (READ FIRST)

A 4-agent migration audit found the git layer solid (192 repos, 7 no-remote all bundled) but
real holes in the **non-git / gitignored / machine-state** layer that a reclone doesn't touch.
Fixes already applied to this branch: arm64 path bugs (`/usr/local/sbin`→`${HOMEBREW_PREFIX}/sbin`,
hardcoded `$HOME`, gitconfig `!gh` PATH-resolved). The rest are **pre-wipe actions** — do them
on the OLD machine before wiping, they are NOT auto-handled:

1. 🔴 **`.env` secrets reclone EMPTY.** ~50 populated `.env`/`.env.local` files are gitignored or
   in non-git dirs (worst: `002-engenious/.../marketing_agent/.env.local` — live prod tokens).
   The `rsync ~/Code → SSD` (Phase 0.3) captures them, but you MUST **restore them from the SSD
   snapshot after cloning** (see Phase 2.8), OR consolidate real keys into `~/.secrets` (carried).
2. 🔴 **Carry the reclone manifest:** `~/env-snapshots/repo-manifest-2026-09-17.txt` (PATH|REMOTE
   for all 192 repos) — `code_manager.sh` can't discover repos on a wiped Mac. Hand-carry it.
3. 🔴 **Genuinely-loose non-git dirs** (untracked, no remote → hand-carry; git-status-verified 2026-09-17):
   `006-rp/{OTH-candidate-assistant (306M), GRAPH-graphrag-integration (82M), GRAPH-custom-graphrag (33M),
   GRAPH-chroma-rag, DIF-emoji-generation (116M), DIF-adversarial-diffusion (64M), OTH-orchestration-coreo (58M),
   AGT-multiagent-orchestrator, SQL-nlsql}` + `005-products/001-assessment (9M)`. The rsync (0.3) also covers these.
   **NOT hand-carry (all reclone-safe git repos/tracked — an earlier draft wrongly listed them):** 026-Noema,
   028-nano-universe, AGT-rlm-graph-unix (own repos w/ remotes), and ALL of 003-kp incl. miniprojects/* +
   llm-engineering-lab (tracked in the 003 repo).
4. 🔴 **Databases:** `pg_dump` PostgreSQL@14 (`/usr/local/var/postgresql@14`, ~360M) if it holds
   anything you want; carry `027-ml-workspace/mlops/.prefect/prefect.db`; verify the docker
   `teaching_postgres` volume (start docker first). Runbook otherwise says nothing about DBs.
5. 🟠 **Extra SSH keys** (add to Phase-1): `~/.ssh/google_compute_engine`, `~/.ssh/dc_trader`,
   `~/.ssh/known_hosts` (only `id_ed25519_personal/_work` were listed).
6. 🟡 **Teaching:** re-run the spiced RISE nbconfig `echo` one-liners (see `004-lewagon-spiced/CLAUDE.md`)
   for BARE `ds-book-template` use (the container bakes it, bare dev doesn't). Snapshot VS Code
   extensions (`code --list-extensions > ~/env-snapshots/vscode-ext.txt`) — Dev Containers ext is
   needed for the spiced container. Carry `~/Library/Application Support/Claude/` if you use custom MCPs.

Hand-carry payload is **~8.5G** (Noema 2.6G + nano-universe 949M + ds-book-template 3.0G + the
non-git source dirs) — size the SSD/AirDrop accordingly, not the old "~4.2G" line below.

---

## Phase 0 — OLD machine pre-flight (run days before, re-run as final gate)

1. **Repo hygiene sweep** — `custom_scripts/repo_sweep.sh` must print **RECLONE-READY**
   (checks every repo for dirty trees, unpushed commits, missing remotes; exit 1
   otherwise). Run it days before AND on migration morning — do not proceed on ❌.
   A `.sweepignore` (at `$ROOT/.sweepignore`) allowlists confirmed false positives
   (vestigial `git init` shells, by-design no-remote scratch) so ❌ means real work.
   State 2026-09-17 post-audit: 114 flagged (allowlist off) → **7 NO-REMOTE** (4 are
   the allowlisted vestigial/scratch shells; 3 are engenious work repos — my-ai-underwriter,
   engenious_university, discord-me-mcp — all bundled to `~/git-bundles/`), ~50 dirty +
   ~61 unpushed dominated by the `ai-underwriter-references/000-ai-underwriter-local`
   worktree fleet (engenious work) + pre-existing personal WIP. talentsphere,
   teaching-containers, 021-bootcamp, 020-autoresearch, 024-dino, 025-ltm now all remoted.
   Fix recipes:
   - no remote → `gh repo create <name> --private --source . --push`
   - unpushed  → `git push --all` (engenious work branches: owner's call)
   - dirty scratch → `git add -A && git commit -m "chore: wip snapshot" && git push`
2. **Branch deep-clean (layer 2)** — `custom_scripts/repo_sweep.sh --branches` lists
   every repo's branch sprawl with `[unmerged]` / `[local-only]` flags. `[local-only]`
   branches VANISH on reclone. Per branch: merge → main + push + delete, or
   `git push -u origin <b>` to keep, or `git branch -D` to drop. The gate (layer 1)
   only requires pushed-somewhere; this layer is the proper cleaning — do it repo-by-repo
   in the weeks before migration (engenious feature branches = work decision).
3. **Belt-and-braces (mandatory):** `rsync -a ~/Code /Volumes/<SSD>/Code-final-snapshot/`
   before the Intel is ever wiped — caps reclone risk at zero even if the sweep missed
   something. The Intel also stays shelved (powered off, unwiped) for ≥ a few weeks.
4. **pyenv snapshots** — `custom_scripts/depyenv.sh` (dry-run default; Phase A freezes all
   envs to `~/env-snapshots/`). Only during migration week: `depyenv.sh --apply` to fix
   Juan-owned `.python-version` files (upstream-tracked ones are always left alone).
5. 🙋 **Review loose data**: `~/Downloads`, `~/Desktop`, `~/Documents` (teaching zips live
   there), `~/Library/LaunchAgents`.
6. **Coverage proof** — `custom_scripts/verify_coverage.sh` must report zero UNCOVERED
   branch tips (every local branch in every repo, engenious + worktree fleets included,
   contained in a remote or a `~/git-bundles` bundle). **Re-bundle engenious on wipe-day**
   (`git bundle create <name> --all` per repo) so bundles are never stale at the moment of truth.

## Phase 1 — 🙋 Hand-carry (external SSD / AirDrop; NEVER through this public repo)

| Item | Target on new Mac | Note |
|---|---|---|
| `~/.secrets` | `~/.secrets` | `chmod 600` |
| `~/.ssh/id_ed25519_personal`, `~/.ssh/id_ed25519_work` | `~/.ssh/` | `chmod 600` each |
| `~/Code/000-config/002-gcp-credentials/` | same path | GCP SA JSONs |
| **entire `~/.claude/`** (~1.3G) | `~/.claude/` | projects memory/standing, plans, history — irreplaceable |
| `~/.config/gcloud/` | same path | auth tokens; else re-auth every project |
| `~/.aws/` + `~/.azure/` | same paths | WORK credentials/tokens (aws-cli, azure-cli) — else re-auth both |
| `~/env-snapshots/` | anywhere | pyenv freeze insurance |
| Loose non-git dirs (~0.7G personal) | same paths under `~/Code` | See the corrected list in the "Audit 2026-09-17" section above — `006-rp/{OTH-candidate-assistant, GRAPH-*, DIF-*, OTH-orchestration-coreo, AGT-multiagent-orchestrator, SQL-nlsql}` + `005-products/001-assessment`. (026-Noema, 028-nano-universe, AGT-rlm-graph-unix, all 003-kp = git repos → reclone, do NOT carry.) |
| `004-lewagon-spiced/spiced/ds-book-template/` | same path | has LOCAL-ONLY commit (origin = neuefische, no push rights) — re-cloning loses it; bundled at `~/git-bundles/spiced_ds-book-template.bundle`, or carry the folder / add a personal fork remote first |
| `~/.secrets-cheatsheet.md` | `~/` | repo→keys→source map (chmod 600) |
| `~/env-snapshots/pgdump-2026-09-17.sql.gz` | anywhere | postgres@14 dump (360M data dir) |
| `~/env-snapshots/vscode-extensions-2026-09-17.txt` | anywhere | `code --install-extension` loop on new Mac |
| `~/env-snapshots/claude_desktop_config-*.json` | `~/Library/Application Support/Claude/` | Claude Desktop MCP config |
| `~/.ssh/{google_compute_engine,dc_trader,known_hosts}` | `~/.ssh/` | extra keys + host trust |
| Reviewed Downloads/Desktop/Documents picks | wherever | from Phase 0.5 |

**Authoritative executable list + copier:** `custom_scripts/stage_handcarry.sh` — `--check`
verifies everything above exists; `--to /Volumes/<SSD>` stages it. The table is the narrative;
the script is the truth.

Do **not** carry: `~/.pyenv` (the point), any `.venv`, `~/.nvm`, `~/.jupyter`,
`~/.zsh_history`, `~/.colima`, `~/.ollama/models` (re-pull).

## Phase 2 — NEW machine bring-up (ordered; don't reorder)

1. First boot → `xcode-select --install` (GUI prompt).
2. Copy the Phase 1 hand-carry items into place FIRST (enables SSH clones; kills the
   installer's missing-secrets warning).
3. ```bash
   mkdir -p ~/Code/000-config
   git clone git@github.com:juan-garassino/dotfiles.git ~/Code/000-config/001-dotfiles
   cd ~/Code/000-config/001-dotfiles
   git checkout uv-only        # until this branch is merged to master
   ./install.sh                # installs brew, symlinks, bundle, omz+p10k, uv pythons
   ```
   ⚠️ Do not open new terminal tabs mid-install (zshrc is symlinked before oh-my-zsh
   exists — a shell opened in between errors once, harmlessly, but confusingly).
4. 🙋 **Auth gates**:
   - Fill real values in `~/.secrets` if it was seeded empty; `chmod 600`.
   - `ssh-add --apple-use-keychain ~/.ssh/id_ed25519_personal` (and `_work`).
   - `gh auth login` twice: personal `juan-garassino`, then work `j-garassino-engenious`.
   - `gcloud init` + `gcloud auth application-default login` (skip if `~/.config/gcloud` carried).
   - p10k config wizard: **decline** — `~/.p10k.zsh` is already symlinked.
5. Verify the toolchain: `which uv` → `$(brew --prefix)/bin/uv` (NEVER a `.pyenv/shims`
   path); `uv python list --only-installed` shows 3.11 + 3.12.
6. Fresh shell → `mysandbox` (creates + seeds `~/.venv-sandbox`, ~110 packages, arm64 wheels).
7. **Clone all repos to their exact old paths** (`~/Code/00X-…`) — git `includeIf` and the
   gh account cd-hook key off these paths. Use `pull-all.sh` in 004-lewagon-spiced and
   `custom_scripts/code_manager.sh`. Copy the hand-carried non-git dirs into place.
8. Per-project envs are recreated ON TOUCH, not up front: `cd` prints a hint, then
   **`envup`** does the right thing for any manifest style (pyproject → `uv sync`;
   requirements.txt → venv + install). Explicit equivalents if needed:
   `uv sync` / `usevenv 3.12 && uv pip install -r requirements.txt`.
9. Rosetta: NOT needed (all-arm64 stack). Install only if some Intel-only cask appears.

## Phase 3 — Verification gauntlet (all must pass)

**One command:** `custom_scripts/preflight_gauntlet.sh` — the whole gauntlet as a PASS/FAIL
scorecard (syntax, pyenv-leak, autoenv 4 cases, identity matrix, uv toolchain, lfs filter,
docker). It MUST be **sourced** from an interactive shell (the autoenv checks need the shell's
functions): `zsh -i -c 'source .../custom_scripts/preflight_gauntlet.sh'`. It is the
SAME script that gated the Intel in-place cutover — identical gate both sides.
The manual walk-through below is kept for debugging individual failures:

```zsh
zsh -n ~/Code/000-config/001-dotfiles/shell/zshrc                       # syntax
zsh -ilc 'exit' 2>&1 | grep -iE 'pyenv|command not found|error' || echo CLEAN
# autoenv 4 cases (interactive shell):
cd /tmp                                    # → ~/.venv-sandbox active
cd <a project with .venv>                  # → project .venv active
mkdir -p /tmp/avt && echo 3.12 > /tmp/avt/.python-version && cd /tmp/avt
                                           # → hint printed ONCE, sandbox stays
cd ~/Code/004-lewagon-spiced/lewagon/official-content/data-science/data-challenges
                                           # → one legacy-env info line; git status CLEAN
# identity matrix:
cd ~/Code               && git config user.email && gh api user -q .login   # personal
cd ~/Code/002-engenious && git config user.email && gh api user -q .login   # work
# toolchain + containers + gates:
uv run --python 3.12 python -VV
colima start && docker run --rm hello-world
echo '{}' | ~/.claude/statusline-command.sh                                  # renders
custom_scripts/backup_env.sh --no-push                                       # secret gate passes
```

## Phase 4 — Finalize

1. **Apps & GUI sign-ins** (the `install.sh` Brewfile already installed the casks —
   Antigravity ×2, VS Code, DBeaver, Slack, Warp, gcloud, ngrok — and step 6b/6c restored
   all 48 VS Code/Antigravity extensions + the npm/go global CLIs): sign into **Antigravity**
   (Google account), Slack (`lewagon-alumni` + engenious workspaces), and run
   `gcloud auth login && gcloud auth application-default login`.
2. **macOS defaults** (optional, your muscle-memory): `zsh custom_scripts/macos_defaults.sh`
   (fast key-repeat, screenshots→Desktop, Finder tweaks — reversible, not run by install.sh).
3. **Rosetta**: only if an x86-only tool ever complains — `softwareupdate --install-rosetta`.
   The whole stack is arm64-native; you should not need it. (Also confirm your terminal app
   is NOT "Open using Rosetta" — Get Info on Warp/Terminal.)
4. **Docker**: this setup uses **colima** (not Docker Desktop — the 51G Intel fossil is gone):
   `colima start` gives you the docker daemon; `docker`/`docker compose` then work as normal.
5. Merge: `git checkout master && git merge uv-only && git push` (from the NEW machine only).
6. Old machine: it is NOT retired — it becomes the **Linux-primary travel machine** (see
   "Two-machine target architecture" below). It already runs uv-only (pyenv deleted in the
   2026-09-18 in-place cutover) and stays the working daily driver until the M5 is verified.
7. Later (separate work): build the 4 teaching-stack images
   (`~/Code/004-lewagon-spiced/teaching-containers/`) arm64-native and test the RISE
   present flow end-to-end before the first class. (Definitions already build+smoke GREEN
   on amd64 — validated 2026-09-18 via `custom_scripts/validate_teaching.sh`.)

## Intel in-place cutover — EXECUTED + VALIDATED 2026-09-18

The Intel machine was cut over to uv-only IN PLACE, one month ahead of the M5 — so every
migration layer is proven on real hardware and the M5 bring-up is execute-only.

**Mechanism** (`custom_scripts/flip_uvonly.sh`): the live dotfiles are symlinks into a repo
checkout; the cutover re-points `~/.zshrc ~/.zshenv ~/.zprofile ~/.aliases ~/.p10k.zsh
~/.gitconfig(-personal/-work) ~/.config/direnv/direnvrc` from `001-dotfiles/` (main) to this
worktree. `--rollback` restores the snapshot targets (`~/env-snapshots/live-symlinks-pre-cutover.txt`)
in seconds. Shell-config rollback still works; pyenv itself is gone (see below).

**Proven on Intel (the checklist the M5 can trust):**
- Gauntlet **17 PASS / 0 FAIL** live (sourced, per Phase 3); pyenv-on-PATH is a hard PASS.
- `envup` rebuilds envs from every manifest style (pep621 `uv sync`, requirements venv+install).
- **44 owned repos converted uv-native** (pyproject + uv.lock on `build/uv-native` branches,
  pushed; manifest: `~/env-snapshots/uvnative-sweep-2026-09-18.md`). 021-bootcamp already a
  uv workspace. Engenious NEVER touched (script hard-aborts on its path).
- **Engenious under uv**: ai_audit_service 180 tests ✓, discord-me-mcp 31 ✓, marketing_agent
  1529 ✓ (25 fails live in the repo's own June WIP), aiuw compose stack 7/7 containers +
  `/health` healthy. Zero git writes (tripwire verified).
- **All 4 teaching stacks build+smoke on amd64** (`validate_teaching.sh`); rehearsal caught+
  fixed a real DA bug (packaging>=23.2 pin).
- **pyenv deleted** (56G freed): `depyenv.sh --apply` fixed 92 legacy `.python-version` files
  (20 upstream left alone) → `migration_cleanup.sh --apply --python-only` → `brew uninstall pyenv`.
- **uv is the standalone binary** (`~/.local/bin/uv`, official installer — same as install.sh).
  Gotcha found on Intel: stale pip-user + pipx uv shims shadowed each other; deleted. Never
  install uv via pip/pipx again.
- Known Intel-only gaps (fine, M5 covers them): git-lfs binary not installed (Brewfile has it);
  root-owned python.org 3.7 framework needs a manual `sudo rm -rf` (or dies with the wipe);
  heavy torch/tf envs don't build on x86 wheels (locks are valid; arm64 syncs them).

## Two-machine target architecture (post-M5)

GitHub is the SOLE code-sync layer between two INDEPENDENT machines; they never sync to each
other; no git repo ever lives on shared storage.

- **NEW MAC (M5) = HOME** — macOS, full uv-only stack, `~/code` on APFS.
- **OLD 2015 MBP = TRAVEL** — after the M5 is verified: factory-reset → 500GB SSD repartitioned
  **300GB Linux/ext4 (PRIMARY)** + **100GB ExFAT (SHARED)** + **100GB macOS/APFS (fallback)**,
  dual-boot (one OS at a time; ExFAT mounts from whichever is booted).
- **Source-of-truth hierarchy**: code/history → GitHub · env definition → pyproject.toml +
  uv.lock (`uv sync`) · machine env → local per OS, never synced · cross-OS data → ExFAT ·
  backup → external drive (backup ≠ ExFAT).
- **ExFAT rules**: NEVER `.venv`, `node_modules`, git working copies, or Docker state on ExFAT;
  never treat it as backup. Genuinely cross-OS data only (datasets/documents/media).
- **gh routing is a hard requirement on every environment**: `gh_auto_switch` cd-hook —
  `~/Code/002-engenious*` → `j-garassino-engenious`, else `juan-garassino` (in this zshrc).

**Future bring-up phases** (when the M5 lands; done together with Claude):
1. M5 macOS: install.sh (uv-only) → git pull → envup on-touch → teaching containers arm64.
2. Old-Mac factory reset + SSD partition (300/100/100).
3. Linux-primary: install.sh Linux branch (rehearsed 12/12 in ubuntu:24.04) → git pull to
   ext4 `~/code` → Docker + uv + teaching containers native.
4. macOS-fallback: minimal uv-only (`DOTFILES_MINIMAL=1 install.sh`) → git pull.
5. ExFAT populate (datasets/documents/media).

**End-to-end acceptance layer** (system-level, over the per-phase gates):
- **Pre-reset git gate** before ANY destructive step: `repo_sweep.sh` + `verify_coverage.sh`
  = 0 uncovered, every owned repo visible on GitHub (`git ls-remote`).
- **Credentials are MACHINE-LOCAL** — recreate intentionally per environment, never sync via
  GitHub, never on ExFAT: gh (both accounts), SSH keys, git signing, Docker creds, cloud CLIs,
  API creds, `.env` values (keys-only `.env.sample` in-repo; values via rsync snapshot +
  `~/.secrets-cheatsheet.md`), Claude auth.
- **Cold-boot test** (post-partition): boot Linux → ExFAT mounts → git pull → Claude/Docker/uv
  work; reboot macOS → ExFAT mounts → git pull.
- **Per-environment acceptance**: each of the 3 (M5 macOS / 2015 Linux / 2015 macOS-fallback)
  independently green on git pull · uv sync · envup · Claude Code · Docker · teaching stacks.
- **Definition of done**: all three operational + independent; no repo on ExFAT; ExFAT visible
  from both OSes; external backup verified; either OS boots; no machine depends on another.

## Rollback

Shell-config rollback on the Intel machine: `custom_scripts/flip_uvonly.sh --rollback`
(re-points the symlinks back to `001-dotfiles` main in seconds). Note pyenv itself is gone
(deleted 2026-09-18) — the pyenv-era config would fall back to brew/system python; real
rollback for environments is `uv sync` (locks are committed). For the M5 migration the old
machine keeps working as the uv-only daily driver — it IS the rollback until the M5 passes
this runbook's gauntlet.
