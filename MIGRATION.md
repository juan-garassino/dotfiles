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
2. **pyenv snapshots** — `custom_scripts/depyenv.sh` (dry-run default; Phase A freezes all
   envs to `~/env-snapshots/`). Only during migration week: `depyenv.sh --apply` to fix
   Juan-owned `.python-version` files (upstream-tracked ones are always left alone).
3. 🙋 **Review loose data**: `~/Downloads`, `~/Desktop`, `~/Documents` (teaching zips live
   there), `~/Library/LaunchAgents`.

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
| Reviewed Downloads/Desktop/Documents picks | wherever | from Phase 0.3 |

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
6. Fresh shell → `mysandbox` (creates + seeds `~/.venv-sandbox`, ~137 packages, arm64 wheels).
7. **Clone all repos to their exact old paths** (`~/Code/00X-…`) — git `includeIf` and the
   gh account cd-hook key off these paths. Use `pull-all.sh` in 004-lewagon-spiced and
   `custom_scripts/code_manager.sh`. Copy the hand-carried non-git dirs into place.
8. Per-project envs are recreated ON TOUCH, not up front: `cd` prints a hint, then
   **`envup`** does the right thing for any manifest style (pyproject → `uv sync`;
   requirements.txt → venv + install). Explicit equivalents if needed:
   `uv sync` / `usevenv 3.12 && uv pip install -r requirements.txt`.
9. Rosetta: NOT needed (all-arm64 stack). Install only if some Intel-only cask appears.

## Phase 3 — Verification gauntlet (all must pass)

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

1. Merge: `git checkout master && git merge uv-only && git push` (from the NEW machine only).
2. Old machine: nothing to do — retire it whenever. `~/.pyenv` dies with it.
3. Later (separate work): build the 4 teaching-stack images
   (`~/Code/004-lewagon-spiced/teaching-containers/`) arm64-native and test the RISE
   present flow end-to-end before the first class.

## Rollback

The old machine is never modified by this runbook — it IS the rollback. If the new Mac
misbehaves, keep working on the old one and iterate on the `uv-only` branch.
