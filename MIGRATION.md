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
   `teaching_postgres` volume — RESOLVED 2026-09-18: `docker volume ls` showed no such volume
   before the Docker VM was reset; only aiuw pgdata existed (tarred). Postgres data is the raw
   datadir tar (see Phase 1), not a pg_dump (postgres@14 could not start: icu4c mismatch).
5. 🟠 **Extra SSH keys** (add to Phase-1): `~/.ssh/google_compute_engine`, `~/.ssh/dc_trader`,
   `~/.ssh/known_hosts` (only `id_ed25519_personal/_work` were listed).
6. 🟡 **Teaching:** re-run the spiced RISE nbconfig `echo` one-liners (see `004-lewagon-spiced/CLAUDE.md`)
   for BARE `ds-book-template` use (the container bakes it, bare dev doesn't). Snapshot VS Code
   extensions (`code --list-extensions > ~/env-snapshots/vscode-ext.txt`) — Dev Containers ext is
   needed for the spiced container. Carry `~/Library/Application Support/Claude/` if you use custom MCPs.

Hand-carry payload is **~8.5G** (Noema 2.6G + nano-universe 949M + ds-book-template 3.0G + the
non-git source dirs) — size the SSD/AirDrop accordingly, not the old "~4.2G" line below.

---

## 🗺️ THE MASTER ORDER — end-to-end sequence (drafted 2026-09-18, Intel already uv-only)

Governing rule: **nothing destructive happens until a byte-verified vault of ~/Code exists in
TWO places off this machine.** GitHub protects what was pushed; the vault protects EVERYTHING
(dirty trees, untracked files, .git history of no-remote repos). Detailed steps live in the
Phases below; this is the order that stitches them.

### T0 — now (Intel = only machine, cutover done)
Dogfood uv-only daily. The 44 `build/uv-native` branches are being merged (2026-09-18; manifest
`~/env-snapshots/uvnative-merge-2026-09-18.txt`). **Linux distro for the 2015 MBP: Ubuntu 24.04 LTS**
(matches the rehearsed installer). **Standby after T1 until the M5 lands** — R0/R1 are everything
doable without it; the standby state is safe by construction (Intel clean, GitHub complete, vault
verified). Resume-prep = one delta re-vault the day before M5 day.

**Byte-the-same proof tool:** `custom_scripts/code_fingerprint.sh` → `repo|branch|HEAD|clean` per
repo, machine-independent; `diff` of two machines' outputs MUST be empty (used T2.5, T3.1, T4.7).

### T0.5 — GitHub completeness + brew hygiene (this week, before T1)
Goal: **every personal commit lives on GitHub** (the vault covers the rest) and **brew is
Brewfile-clean on both machines**.
1. **Brew ring-1** (done 2026-09-18): orphaned build-deps uninstalled (autoconf/bison/cmake/meson/
   swig/texinfo/libgit2×2/icu4c@77/hyperkit/sphinx-doc/...), autoremove + cleanup -s --prune=all.
2. **Brew ring-2 + ring-3 (DONE 2026-09-18):** llvm, openvino, postgresql@15 + @14 (DBs =
   containers), fluid-synth, gcc/openblas/numpy/krb5/z3/ninja/libgit2/… removed → **197 → 149
   formulas, 7.5G → 4.4G**. Every remaining leaf is in the Brewfile or plumbing.
3. **Brewfile prune (DONE 2026-09-18 — defines the M5's brew from birth):** dropped `postgresql@14`
   and explicit `python@3.12`; added `cloud-sql-proxy`. Principle: the M5 installs ONLY Brewfile
   leaves → brew is born clean and stays clean. **Janitor rule (learned 2026-09-18):**
   `brew bundle cleanup --file packages/Brewfile` (dry-run) lists installed-but-not-in-Brewfile
   formulas, BUT it does not see transitive deps — it once listed `icu4c@78` + `sdl2-compat`, which
   ffmpeg/tesseract actually need. ALWAYS `brew uses --installed <f>` before `--force`; only remove
   what nothing uses. Trust the third-party taps once (`brew trust azure/functions hashicorp/tap
   runpod/runpodctl`).
4. **GitHub completeness sweep** (fresh scan 2026-09-18: 5 no-remote / 32 unpushed / 60 dirty):
   - Personal dirty repos: agent triage — build junk → .gitignore; real WIP → honest
     `wip:` snapshot commit on the current branch; push. NEVER blind-commit; ambiguous → flag.
   - Personal unpushed branches: push all (SSH per-path identity).
   - `012-temps`: scratch-by-design → DECIDED 2026-09-18: vault-only (accepted exception).
   - `000-config` root repo: **NEVER GitHub** (contains gcp-credentials) — vault-only, forever.
   - Engenious no-remotes (my-ai-underwriter 572 commits, engenious_university, discord-me-mcp):
     WORK IP — pushing needs the org decision; until then covered by refreshed bundles + vault.
   - Gate: re-run the completeness scan → personal repos must be 100% remote+pushed+clean.

**"Both machines, byte-the-same code" — the two proofs, precisely:**
- **Working sets** (M5 `~/code` vs 2015 `~/code`): every repo at the same commit SHA as origin —
  git's content-addressing makes same-SHA = byte-identical content; the check is a per-repo
  `HEAD == origin/HEAD && status clean` sweep on each machine.
- **The vault** (everything incl. untracked/dirty history): literal `rsync -c` byte-compare,
  twice (source↔SSD, SSD↔M5) — see T1/T2.

**`.env` traceability (added 2026-09-18):** `custom_scripts/env_registry.sh` writes
`~/env-snapshots/env-registry.tsv` (chmod 600) — every real `.env`-like file under `~/Code`
with its repo, git status (`ignored` = correct, `TRACKED!` = in history → untrack/rotate),
key NAMES (never values), size, mtime. First scan: **124 files: 57 ignored · 36 non-git ·
5 untracked · 26 TRACKED!**. The registry rides in `~/env-snapshots` (hand-carried + vaulted).
Post-reclone on any machine: `env_registry.sh --restore-from /Volumes/CodeVault/Code-final-snapshot`
copies every file back into place (never overwrites, re-applies 600). Real `.env` values thus
travel ONLY via the vault, never via GitHub. Pair with `~/.secrets-cheatsheet.md` for re-issuing.

### T1 — SSD vault (any day before the M5; ~1h; repeatable)
0. **SSD format gate:** the vault volume MUST be APFS (never exFAT — symlinks, permissions and
   macOS metadata must survive byte-compare). Name it e.g. `CodeVault`.
1. Git gate: `repo_sweep.sh` + `verify_coverage.sh` → 0 uncovered.
2. Vault: `rsync -aE --delete --exclude .venv --exclude node_modules --exclude __pycache__
   --exclude .pytest_cache ~/Code/ /Volumes/CodeVault/Code-final-snapshot/`
   (envs are regenerable from committed locks; code, .git dirs, notebooks, data ALL included).
   Also vault `~/env-snapshots`, `~/git-bundles`, and `stage_handcarry.sh --to /Volumes/CodeVault/handcarry/`.
3. **Byte-verify pass 1 (source ↔ SSD):** same rsync with `-c --dry-run --itemize-changes`
   → MUST print zero lines. Record file-count + du totals in the scorecard.

### T2 — M5 day 1 (machines side by side; zero destructive; done together with Claude)
1. Bring-up = Phase 2 (`install.sh` on `uv-only`) → Phase 3 gauntlet (SOURCED) all green.
2. Hand-carry the machine-local credentials (gh ×2 + routing, SSH keys, cloud CLIs, `.env`
   values, Claude auth) — recreate intentionally, never through GitHub.
3. **Vault copy #2:** rsync SSD → M5 `~/Archive/Code-final-snapshot/` →
   **byte-verify pass 2 (SSD ↔ M5):** `rsync -c --dry-run` silent. The vault now exists twice
   off the Intel machine — this is the lose-nothing guarantee.
4. Working set: fresh `git clone` fleet → `~/code` (GitHub is the source; the archive stays read-only).
5. **Lose-nothing reconciliation:** run `verify_coverage.sh` pointed at the ARCHIVE — every
   branch tip of every archived repo must be contained in its GitHub clone or a bundle; diff
   archive-vs-clone for dirty/untracked files and hand-port the few that matter.
6. Validate on M5: envup spot-checks · `validate_engenious.sh` · teaching containers arm64
   (`validate_teaching.sh`) · acceptance column "M5 macOS" green.
7. Merge `uv-only` → master (Phase 4.5). **Soak 1–2 weeks** with the M5 as daily driver;
   Intel stays untouched — it IS the rollback.

### T3 — wipe gate (only after the soak)
1. Intel delta: `repo_sweep` + `verify_coverage` (anything born during the soak → push),
   rsync delta to SSD, re-verify byte-equal.
2. Gate checklist: M5 acceptance green ✓ · vault ×2 byte-verified ✓ · secrets recreated ✓.
   Then: sign out iCloud/iMessage/Find-My, deauthorize apps → wipe authorized.

### T4 — 2015 MBP rebirth (dual-boot travel machine)
1. Internet Recovery → Disk Utility: erase the whole 500G disk → APFS container **100G**
   (macOS fallback) + leave ~400G free.
2. Install macOS into the 100G → minimal bring-up: `DOTFILES_MINIMAL=1 install.sh` → git pull
   the handful of needed repos → acceptance column "2015 macOS".
3. **Ubuntu 24.04 LTS** USB (matches the rehearsed install.sh Linux branch): partition the free
   space **300G ext4 `/`** + **100G exFAT `SHARED`** → install. 2015-MBP quirks: Broadcom Wi-Fi
   needs `broadcom-sta`/`bcmwl` (bring USB tethering for first boot); boot picker = hold-Option
   (rEFInd optional, not required).
4. Linux bring-up: `install.sh` Linux branch (rehearsed 12/12 in ubuntu:24.04) → git pull to
   ext4 `~/code` → Docker Engine + uv → gauntlet → teaching containers → acceptance "2015 Linux".
5. ExFAT: populate datasets/documents/media from the SSD vault; automount from both OSes.
   ExFAT rules enforced: never repos, `.venv`, node_modules, or Docker state; never "the backup".
6. **Cold-boot test:** power on → Linux → ExFAT mounts → git pull → Claude Code/Docker/uv work;
   reboot → macOS → ExFAT mounts → git pull. Never both at once.

### T5 — steady state
Two independent machines, one git workflow: each OS pulls/pushes GitHub on its own; machines
never sync to each other. Keep the SSD vault ≥3 months as the historical archive. Close with
the system-level Definition-of-Done (acceptance layer E).

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
| `~/env-snapshots/postgresql14-datadir-2026-09-17.tar.gz` | anywhere | postgres@14 raw datadir tar (129M; pg_dump impossible — icu4c mismatch) |
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
