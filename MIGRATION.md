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

## Phase 0 — OLD machine pre-flight (run days before, re-run as final gate)

1. **Repo hygiene sweep** — `custom_scripts/repo_sweep.sh` must print **RECLONE-READY**
   (checks every repo for dirty trees, unpushed commits, missing remotes; exit 1
   otherwise). Run it days before AND on migration morning — do not proceed on ❌.
   State 2026-09-17: 82 dirty / 42 unpushed / **31 with NO REMOTE** (incl. 021-bootcamp,
   020-autoresearch, 024-dino, 025-ltm, teaching-containers). Fix recipes:
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
| Non-git project dirs (~4.2G) | same paths under `~/Code` | 026-Noema, 028-nano-universe, 003-kp/miniprojects/{multiagent-orchestration, codeact, multi-agents-workflow, mini-agent-as-a-service, mini-deepagents}, 006-rp/{OTH-candidate-assistant, AGT-rlm-graph-unix} |
| `spiced/ds-book-template/` | same path | has LOCAL-ONLY commits (origin = neuefische, no push rights) — re-cloning loses them; carry the folder or add a personal fork remote first |
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
