# MIGRATE.md — move the whole dev setup + code to a new machine (Claude Code runs this)

**Claude Code: this is an executable runbook.** Run it ON THE NEW MACHINE (the target), top to
bottom; verify each step; STOP at every 🙋 (human-only: passwords, logins, clicks on the source).
The **source** machine is read-only and stays the rollback: only read from it — never modify,
delete or push from it.

**Goal: exactly the same dev setup** — shell, prompt, terminal, tools, configs, credentials,
Claude memory, and `~/Code` byte-for-byte (every repo, branch, stash, uncommitted change,
work repos, `.env`). NOT the OS itself: personal apps, documents and media are out of scope.

**How:** `install.sh` rebuilds the environment from this repo; `rsync` over ssh pulls `~/Code` +
`packages/home-carry.txt` from the source. `.venv`/`node_modules`/build caches are not copied —
they're OS/arch-specific and rebuilt (`envup`). GitHub is complete for personal repos (backup layer).
`~/Code` is then PROVEN identical with `custom_scripts/verify_code.sh` (checksum manifest + git
refs/stash/index/status per repo), twice on the target (step 7b and step 10) and three ways when a
buffer machine exists (step 10b).

| Target (this machine) | `$OS` | Notes |
|---|---|---|
| Ubuntu desktop / laptop (incl. a 2015 MacBook running Ubuntu) | linux | path-compat symlink. 2015 MBP: see **"2015 MacBook Pro → Ubuntu"** below — its SSD corrupts writes under Linux unless capped first |
| WSL2 (Ubuntu inside Windows) | wsl | `~/Code` in the WSL ext4 home, **never** `/mnt/c`; font + Warp on the Windows side; systemd for Docker |
| Apple Silicon Mac | mac | Homebrew in `/opt/homebrew` + Brewfile; the account may differ (`garassino-juan` → `/Users/garassino-juan`), step 5 handles it |

| Source (old machine) | ssh on | home |
|---|---|---|
| Mac (e.g. the Intel today, later the Apple Silicon one) | System Settings/Preferences → Sharing → **Remote Login** | `/Users/juan-garassino` |
| Linux (e.g. the Intel Mac once it runs Ubuntu, or the buffer) | `sudo apt install -y openssh-server` | `/home/<user>` |

### 2015 MacBook Pro → Ubuntu (measured 2026-10-24, Ubuntu 26.04.1, APPLE SSD SM0512G)

**Scripted:** after `install.sh` (and Toshy, below), run `machines/mbp2015/setup.sh` — it installs every file below from
`machines/mbp2015/{root,home}/`, merges the Toshy user slices, purges kdump, trims services and enables the units; `--check`
lists what differs. The SSD cap must still be done by hand in the live session (it protects the install itself), and the
FaceTime camera driver stays manual. The bullets explain why each piece exists.

- **The SSD silently corrupts writes** under Linux: AHCI `host bus error` on large transfers (NCQ and non-NCQ), ext4 `potential data
  loss`, broken files (`dpkg -V` → `??5??????`), a gnome-shell that segfaults in `libLLVM` (black screen after the passphrase), a
  snap seed that fails (`cannot find signatures with metadata`, so no Firefox). SMART is clean — the disk is fine. Measured on a 2 GB
  write: 4 MB transfers → 210 errors, 512 KB → 0.
- **Install with the cap on:** in the live session ("Try Ubuntu", Ctrl+Alt+T), before starting the installer:
  `for d in /sys/block/sd*; do grep -q APPLE $d/device/model && { echo 1 | sudo tee $d/device/queue_depth; echo 512 | sudo tee $d/queue/max_sectors_kb; }; done`
  First boot: the same line, then make it permanent — udev rule
  `ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="sd[a-z]", ATTRS{model}=="APPLE SSD*", ATTR{queue/max_sectors_kb}="512"` in
  `/etc/udev/rules.d/60-apple-ssd-max-sectors.rules` + `update-initramfs -u`, and `libata.force=noncq` in `GRUB_CMDLINE_LINUX_DEFAULT`
  + `update-grub`.
- **Then verify:** `sudo dpkg -V | grep -v " c /"` must be empty (reinstall every package it names; files written before the cap
  are suspect — e.g. `ubuntu-wallpapers-resolute` needed a reinstall). If it aborts on `pritunl-client-electron` "md5sums … missing
  final newline" (vendor bug, hides later packages): `echo | sudo tee -a /var/lib/dpkg/info/pritunl-client-electron.md5sums`. And
  `journalctl -k -b | grep -c -i -E "host bus error|I/O error"` must stay 0. A failed snap seed: stop snapd, move
  `/var/lib/snapd/seed` and `state.json` aside, start snapd, `snap install` the snaps from the store.
- Wi-Fi: the 15" (BCM43602) works out of the box (`brcmfmac`); `bcmwl-kernel-source` is only for the older BCM4360. An offline install
  leaves stale apt lists — `sudo apt update` before the first `apt install`. Without `bootstrap.sh`: `sudo apt install -y zsh perl curl git`
  first (`install.sh` is `#!/bin/zsh`). The GDM login may need Ctrl+Alt+F3 (text console) to get in until it's fixed.
- Mac-style keys: **Toshy** (`git clone https://github.com/RedBearAK/toshy.git ~/src/toshy && cd ~/src/toshy && ./setup_toshy.py install`,
  in a real terminal — it prompts) — ⌘C/⌘V copy/paste everywhere incl. terminals, physical Ctrl+C still interrupts. GNOME Wayland needs a
  window-info extension first (`window-calls-extended@hseliger.eu` has a GNOME 50 build). Don't combine with `hid_apple swap_ctrl_cmd=1`
  (the older approach; terminals then needed ⌘⇧C/⌘⇧V). Toshy moves the overview to ⌘Space. Reboot after (it adds you to `input`). Pin the built-in keyboard's type in
  `~/.config/toshy/toshy_config.py` → `keyboards_UserCustom_dct`: `'Apple Inc. Apple Internal Keyboard / Trackpad': 'Apple'`, then
  `systemctl --user restart toshy-config` (not `toshy-config-restart`, which stops the service and runs Toshy outside it). At login Toshy can start before the extension answers and then never learns the focused app (⌘V fails in terminals): add `~/.config/systemd/user/toshy-config.service.d/wait-for-gnome-extension.conf` with an `ExecStartPre=` that polls `gdbus call … /org/gnome/Shell/Extensions/WindowsExt …FocusClass` for up to 30 s. Screenshots into Claude Code with ⌘V: a `user_custom_functions` helper that runs `wl-paste --list-types` and sends `C-v` for `image/*` else `C-Shift-v`, bound to `C("RC-V")` in a "User overrides terminals" keymap in the `user_apps` slice.
- Bluetooth (BCM20703, `05ac:8290`) on kernel 7.0.0-38 fails its reset at boot (`hci0: BCM: Reset failed (-110)`, adapter DOWN,
  address 00:00:…) — 7.0.0-30 didn't; a full power-off doesn't help, `sudo usbreset 05ac:8290` does. Fix: `options btusb
  enable_autosuspend=0` in `/etc/modprobe.d/btusb.conf` + `/usr/local/sbin/bt-recover` (sleep 10, then up to 3× `bluetoothctl list |
  grep -q Controller || usbreset 05ac:8290`, logged as `bt-recover`) run by a `Type=exec` `bt-recover.service` with the same
  `After=`/`WantedBy=` targets as `upower-refresh` (exec, not oneshot: a oneshot holds `multi-user.target` through its sleeps).
- Memory: 16 GB fills up (Chrome + several Claude sessions) and the 4 GB swap file is slow on this SSD (NCQ off). zram:
  `systemd-zram-generator` with `/etc/systemd/zram-generator.conf` (`zram-size = ram / 2`, zstd, `swap-priority = 100`) +
  `/etc/sysctl.d/99-zram.conf` (`vm.swappiness = 180`, `vm.page-cluster = 0`); the swap file stays as overflow. Installing the package
  starts zram0 with its defaults (4 GB lzo-rle) — the config applies at the next reboot. Purge `kdump-tools` (its `crashkernel=` reserves
  512 MB) and disable `docker.service`/`containerd.service` (docker.socket starts them on demand), `ModemManager`, `cups-browsed`
  (deb + `snap stop --disable cups.cups-browsed`).
- Reverse the 3-finger workspace swipe (GNOME 50 has no setting; it follows `natural-scroll`): a local extension
  `~/.local/share/gnome-shell/extensions/reverse-workspace-swipe@garassino/` that hands `Main.wm._workspaceAnimation._swipeTracker`
  and `Main.overview._overview.controls._workspacesDisplay._swipeTracker`'s `_touchpadGesture._touchpadSettings` an inverted
  `natural-scroll`. Uses shell internals — re-check after GNOME upgrades.
- Cooling: this unit idles at 86–92°C with both fans maxed and thermald caps it to 800 MHz under load (dust / dried paste — needs a
  clean + repaste). Software help: `sudo apt install mbpfan` with `/etc/mbpfan.conf` low/high/max_temp 55/65/80 (min/max fan1 2160/6156, fan2 2000/5700, polling 1) — the SMC only ramps near 95°C; with it idle drops to ~78°C at full clock and full load holds 1.4–2.8 GHz instead of 800 MHz. Battery (11 yrs, 116 cycles) sags to ~10.5 V at ~50% under a ~70 W load and the Mac hard-powers-off (journal just stops, RTC resets to 2023-01-01) — run heavy work (Blender, Ollama) on AC; replace the battery with the repaste. Guard: `/usr/local/sbin/battery-turbo` (AC → `no_turbo=0` first, then max freq — with turbo off `cpuinfo_max_freq` reads only 2.5 GHz; battery → `no_turbo=1` + `scaling_max_freq=2500000`; on AC too while the battery is < 40 %, released at 50 %, state in
`/run/battery-turbo.capped` — a heavy load can outrun the charger and the battery then covers the rest; it only ever lowers
`scaling_max_freq` so thermald's throttling stays), oneshot `battery-turbo.service` (WantedBy multi-user + sleep targets) re-run every
minute by `battery-turbo.timer` (power-profiles-daemon can flip `no_turbo` back), and `/etc/udev/rules.d/90-battery-turbo.rules` (`SUBSYSTEM=="power_supply", KERNEL=="ADP1", ACTION=="change", RUN+="/usr/bin/systemctl start --no-block battery-turbo.service"`). Local LLMs: Ollama runs CPU-only; prefer small-active MoE (`lfm2.5:8b`, ~12 tok/s) over dense 9B (~1 tok/s throttled).
- Battery shows e.g. 13% at 94% (upower caches a bogus `energy-full` ~712 Wh from the SBS gauge at boot; `/sys/class/power_supply/BAT0/capacity`
  is right). Draining while plugged in (status flapping Charging/Discharging with a net loss under load) = an undersized charger:
  this 15" needs the 85 W MagSafe 2 — a weaker charger ran it down to 6 % / 10.0 V even with the CPU capped at 2.2 GHz (2026-10-28);
  the 85 W one charged at once. Fix: `/etc/systemd/system/upower-refresh.service` — `Type=exec`, `ExecStart=/bin/sh -c 'sleep 20; exec systemctl try-restart upower.service'`
  (the sleep inside ExecStart — in `ExecStartPre` it holds boot 20 s even with exec),
  `After=`+`WantedBy=` multi-user + suspend/hibernate/hybrid-sleep/suspend-then-hibernate targets; `systemctl enable` it. Sitting at 93–95% on
  AC with charging/discharging flapping is normal (Apple SMC hysteresis + trickle charge).
- FaceTime HD camera (`14e4:1570`): no in-tree driver — needs `patjak/facetimehd-firmware` (`make && sudo make install`) +
  `patjak/facetimehd` via DKMS (`sudo dkms install .`; builds on kernel 7.0, driver 0.7.0.1). Build deps: `dkms build-essential
  linux-headers-$(uname -r) curl xz-utils cpio`. The sensor set-file extraction fails its hash check (2026-10) — `sudo make install` still
  installs `firmware.bin`; the camera runs without calibration. DKMS ignores the driver's `MODULES_CONF`, so add
  `echo "blacklist bdc_pci" | sudo tee /etc/modprobe.d/facetimehd.conf && sudo update-initramfs -u`.

## State across Bash calls — `~/.migration/` (read before step 1)

Every Bash call Claude makes is a fresh `zsh -c`: shell variables, arrays and `export`s vanish
between calls. All migration state therefore lives in files under **`~/.migration/`** (chmod 700,
created in step 1a, deleted by the hygiene gate):

| File | Holds |
|---|---|
| `env` | `S` (user@host), `SRC` (host/IP), `SRC_HOME`, `OS`, `RSYNC_RSH`, `MIGRATE_SSH`, `MIGRATE_EXCL`, the `src()` helper and the guard |
| `code-excl.txt` | rsync exclude patterns for `~/Code`: the fixed list + every folder declined in step 5b (`--exclude-from`) |
| `claude-include.txt` / `claude-exclude.txt` | the light Claude-history filter (both empty = full history) |
| `home-carry.txt` | trimmed copy of `packages/home-carry.txt` (Round G) — the tracked file is never edited |
| `answers.md` / `skipped.md` | interview answers · every path the user declined (with sizes) |
| `state` | number of the last completed step (resume point) |
| `logs/` | output of every long run (`07-code.log`, `08-install.log`, …) |

**Rule: every Bash call from step 2 on starts with `source ~/.migration/env`.** The file ends with a
guard that aborts the call when `S` or `SRC_HOME` is empty (an empty `SRC_HOME` would corrupt
`~/.claude.json` in step 9), so nothing runs with half a configuration. Never type `ssh $S …`:
use `src …` (it carries the migration key, `IdentitiesOnly`, `BatchMode`), and never build
`"${EXCL[@]}"`-style arrays — pass the files. Answers for `install.sh` go on its command line
(step 8), not in an `export`.

## P. Before the freeze — reconcile a buffer that already holds an older `~/Code` (run on the SOURCE, only if a buffer exists)

A Linux buffer filled by an earlier migration may hold work done **on the buffer** since then. The buffer is later mirrored from the
source with `--delete` (step 10b), so that work must come to the source first. This is the only place where this runbook changes the
source — deliberately, before the freeze, with the user approving every item. Run it from a Claude session on the source:
1. 🙋 Buffer on, `sshd` + `rsync` + `perl` + `git`; the source can ssh to it without a password (`ssh-copy-id <user>@<buffer-ip>`). `BUF=<user>@<buffer-ip>`.
2. **Find what exists only on the buffer** (all read-only on both sides):
   - Files: `rsync -ani --update --exclude-from=<code-excl.txt> "${BUF}:Code/" ~/Code/` — lists files missing here or newer there.
   - Commits: per repo present on both, `git -C <repo> fetch --no-tags "ssh://$BUF/~/Code/<repo>" '+refs/heads/*:refs/remotes/buffer/*'`
     (adds only `refs/remotes/buffer/*`, which the proof ignores), then `git -C <repo> rev-list --count --remotes=buffer --not --branches --tags`
     → repos with buffer-only commits. Repos that exist only on the buffer: from the `rsync -ani` list.
   - Uncommitted work: per repo on the buffer `git --no-optional-locks status --porcelain`; for each dirty one save
     `git diff --binary HEAD` and a tar of the untracked files into `~/migration-staging/buffer-wip/<repo>/` (on the source).
3. 🙋 Show the user one list (repo / commits / dirty files / loose files) and decide **one item at a time**: merge or cherry-pick the
   `buffer/*` branch, apply the patch, copy the file, or drop it. Nothing is discarded without a "drop".
4. Remove the `refs/remotes/buffer/*` refs when done (`git update-ref -d`), then **freeze** `~/Code` on the source. From here on the
   buffer is a disposable copy.

## 0. Bootstrap (human, one command — done if you are reading this inside Claude)

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/main/bootstrap.sh)"
```
Pinned to a reviewed tag instead of `main` (the clone is then left on that tag, detached HEAD; after the migration `git checkout main`):
`DOTFILES_BRANCH=<tag> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/juan-garassino/dotfiles/<tag>/bootstrap.sh)"`.
Use the `/bin/bash -c "$(curl …)"` form, not `curl … | bash`: on macOS the piped form can't start Claude (Bun can't re-open
`/dev/tty` with kqueue — EINVAL) and only prints this line; on Linux both forms work.
On Linux, `bootstrap.sh` also installs `zsh` and `perl` (the verification needs `Digest::SHA`).

## 1. Preflight (read-only)

- `git -C ~/Code/000-config/001-dotfiles status -sb` — on the pinned tag? `git fetch -q && git log -1 --oneline` — re-read this file if it changed.
- Detect target: `uname` (Darwin → mac), `grep -qi microsoft /proc/version` → wsl, else linux.
- Disk: `df -h ~`. Size the need from the step-5b measurement — the source was ≈110 G before skips
  and ≈68 G after the recommended ones (2026-10-22, drifts): plan **≥ 1.3 × the chosen size** free
  (≈150 G without skips, ≈90 G with them). Re-check `df -h ~` in step 5b once the real number is known.
  Linux/WSL: `~/Code` on ext4 under `$HOME`.
- `rsync --version | head -1`. macOS ≥ 15.4 ships **openrsync** as `/usr/bin/rsync` (partial option
  set; dry-run numbers won't match) and Homebrew is not installed until step 8. If it says
  `openrsync`: 🙋 ask, then install Homebrew now (the line `install.sh` uses:
  `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`)
  and `brew install rsync` (it is in the Brewfile anyway). `rsync --version` must then say `rsync  3.x`.
  Homebrew's bin is not on Claude's PATH until install.sh links the shell config, so after step 1a also run
  `sed -i '' '1a\
export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
' ~/.migration/env` — otherwise every later `rsync` is still openrsync.
- Leftover from an interrupted run: `[ -e /etc/sudoers.d/99-migration ] && echo LEFTOVER`. If present,
  `sudo -n rm -f /etc/sudoers.d/99-migration` (the leftover itself makes it passwordless) — step 4 recreates it.
  Also `ls -d ~/.migration 2>/dev/null` → an earlier run: read `~/.migration/state` and **resume** from
  the next step instead of starting over (see step 8).
- Verification prerequisites: `perl -MDigest::SHA -e1 && echo perl-ok` (macOS system perl has it;
  Debian/Ubuntu need the full `perl` package — `bootstrap.sh`/`packages/apt.txt` install it).
- The **source** is chosen in step 2 (auto-detected on the network). Its user is `juan-garassino`
  on the Macs → `$SRC_USER`.

## 1a. Create the migration state

```bash
mkdir -p ~/.migration/logs && chmod 700 ~/.migration ~/.migration/logs && cd ~/.migration   # -p -m only sets the LAST dir's mode
cat > code-excl.txt <<'EOF'
/000-config/001-dotfiles/
/000-config/dotfiles-uv-worktree/
.venv
venv
.venv-*
node_modules
.next
__pycache__
.pytest_cache
.mypy_cache
.terraform
.DS_Store
._*
EOF
printf '%s\n' '.claude/projects/*/memory/***' '.claude/projects/*/standing/***' > claude-include.txt
printf '%s\n' '.claude/projects/*/*' > claude-exclude.txt       # light history (default); full = empty both files
cp ~/Code/000-config/001-dotfiles/packages/home-carry.txt home-carry.txt   # trim THIS copy in Round G
: > answers.md; : > skipped.md; echo 1 > state
OS=$( [ "$(uname)" = Darwin ] && echo mac || { grep -qi microsoft /proc/version 2>/dev/null && echo wsl || echo linux; } )
cat > env <<EOF
# ~/.migration/env — sourced at the start of every Bash call. S/SRC: step 2. SRC_HOME + guard: step 3.
OS=$OS
export RSYNC_RSH="ssh -i \$HOME/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes"
export MIGRATE_SSH="\$RSYNC_RSH"
export MIGRATE_EXCL="\$HOME/.migration/code-excl.txt"
src() { ssh -i ~/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes "\$S" "\$@"; }
EOF
chmod 600 env
```
`RSYNC_RSH` is a plain string (rsync splits it itself) — never word-split it yourself.
Declined step-5b folders are appended to `code-excl.txt` anchored to the `~/Code` root with a leading
and trailing slash, e.g. `/005-products/027-ml-workspace/building-segmentation/out/`.

## 1b. 🙋 Interview — configure everything up front (then run without interrupting)

The user wants a **really interactive migration**. After preflight and before touching the source, ask in **rounds of ≤ 4
questions with AskUserQuestion** (recommended option first, one-line consequence in every description; `multiSelect`
for lists). Don't start copying or installing until the last round is answered. Record every answer in
`~/.migration/answers.md` (outside `~/Code`), print a one-screen summary, and ask **"Start?"** once. After that, run
unattended except at 🙋 human-only steps. Questions that need the source's sizes are asked in step 5b (after ssh works).

**Target-aware.** Step 1 detects `$OS` = mac | linux | wsl. Say what was detected (the target may also be a Mac that was just
turned into Linux, with a Linux machine as `$SRC` — step 5 handles the different home), then ask **only the questions that exist for
that target**: tags below are **[mac] [linux] [wsl]**, untagged = every target. Skip a question rather than ask a pointless one.

**Round A — role.** (1) *What is this machine for?* Coding + local AI/training · Personal daily driver · Both — drives every default
below (a coding/training machine skips Steam, WhatsApp, Spotify, VPNs; a personal one keeps them). (2) *Hostname* — keep or set:
[mac] `sudo scutil --set ComputerName|LocalHostName|HostName …` · [linux] `sudo hostnamectl set-hostname …` · [wsl] `/etc/wsl.conf`
`[network] hostname=` then 🙋 `wsl --shutdown`. (3) *Account / home* — only report; step 5 fixes a mismatch automatically.
(4) *Disk encryption* — [mac] turn FileVault on (recommended) / later · [linux] can't be added after install: report `lsblk -f`
(LUKS?) and tell the user if it is not encrypted · [wsl] skip (BitLocker is a Windows setting).
**Note for later (write it in `answers.md`):** before the source Mac is ever wiped or handed on, the user must sign out of
iCloud / Find My (Activation Lock), the App Store and Messages on it, and revoke that machine's keys and tokens
(GitHub ssh keys + `gh` tokens, gcloud/aws sessions, Claude/Codex logins). Not now — the source stays the rollback.

**Round B — apps (multiSelect, ≤ 4 options per question).**
[mac] declined casks → written to `answers.md` and passed as `HOMEBREW_BUNDLE_CASK_SKIP="<declined…>"` on the `install.sh` command line (step 8).
(1) *Editors + AI*: visual-studio-code · cursor · antigravity / antigravity-ide · claude + chatgpt.
(2) *Data + dev tools*: dbeaver-community · pgadmin4 · elasticvue · postman · gephi · balenaetcher.
(3) *Comms + notes*: slack · discord · zoom · telegram · spotify · obsidian · notion.
(4) *Sync + network + design*: dropbox · google-drive · nordvpn · pritunl · ngrok · inkscape · blender · gcloud-cli.
[linux] by group, then `packages/linux-apps.sh <chosen groups>` (amd64 only — on arm64 say nothing is installed):
(1) *core* (dbeaver pritunl slack antigravity discord obsidian cursor postman notion claude chatgpt) · *dev* (pgadmin elasticvue gephi etcher);
(2) *comms* (zoom telegram spotify) · *sync* (dropbox nordvpn) · *graphics* (inkscape blender — Blender LTS snap; Sverchok + MCP: `claude/mcp-servers.md`).
[wsl] no desktop apps inside WSL: 🙋 the user runs `packages/windows-apps.txt` with winget in PowerShell — ask which lines first.

**Round C — toolchain.** (1) *Containers*: [mac] colima (the deliberate default, in the Brewfile) vs Docker Desktop (cask, ask) —
on Apple Silicon **Docker has no GPU either way**, so it only runs deploy images and the teaching stacks ·
[linux] native Docker Engine; if `lspci | grep -i nvidia` finds a GPU also ask about the NVIDIA driver + container toolkit ·
[wsl] Docker Engine inside WSL2 (needs systemd). (2) *Local AI*: [mac] training/inference run **natively**, not in Docker —
ollama native (Metal) + `llm` CLI: install only / install + pull models (ask which, show sizes) / skip; and the ML stack:
uv env with PyTorch (MPS backend) / MLX (`uv pip install mlx mlx-lm`, Apple-Silicon-only) / both / skip ·
[linux]/[wsl] ollama + `llm` as above; CUDA only if a GPU was found. (3) *Python/Node*: uv 3.11 + 3.12 + 3.13 and `~/.venv-sandbox`;
nvm LTS + the global CLIs — as-is / add a Python version / skip Node. (4) *Terminal*: [mac] Warp + the dracula/MesloLGS settings
(`terminal/warp-settings.toml`) or Terminal.app · [linux] Warp from its apt repo or the default terminal · [wsl] font + terminal live on the Windows side → 🙋.

**Round D — look and feel.** (1) *Bauhaus icons* (step 8c): [mac] **recommend NO on macOS ≥ 13** — writing icons into other
vendors' app bundles is likely blocked by the App Management privacy control (untested on 15/26); the user can test
`custom_scripts/bauhaus_icons.py --mac` by hand later. Options: none (recommended) / icons / icons + Dock tiles + re-apply after updates →
`BAUHAUS_ICONS`, `BAUHAUS_MAC_EXTRAS` · [linux GNOME, needs `gsettings`] yes / no → `BAUHAUS_ICONS` · [wsl] skip.
[mac] (2) *macOS defaults* (`custom_scripts/macos_defaults.sh`: key repeat, Finder, Dock, …): run all / let me pick each / skip.
[mac] (3) *Dock layout*: keep default / clean. [mac] (4) *Screenshots folder*: Desktop (default) / elsewhere.

**Round E — accounts and secrets (🙋, one at a time, never echo values).** Which to set up now vs later (multiSelect):
GitHub CLI for both accounts · SSH keys (personal + work) · `~/.secrets` values · GCP service-account JSON ·
gcloud/aws logins · ngrok token · Claude Code login (done) · Google Drive/Dropbox sign-in.

**Round F — safety and proof.** (1) *Verification depth*: full (`verify_code.sh --canary` after step 7 AND at step 10 + `check_setup.sh --code`
scorecard) / quick (one `verify_code.sh` run at step 10). (2) *Second target*: also copy `~/Code` to another machine (buffer) and cross-check
three ways (step 10b) — needs a Linux box with ssh + full perl. (3) *When done*: remind to turn Remote Login / ssh off and stop `caffeinate`
(Mac source) or `systemd-inhibit` (Linux source); keep the source untouched until every check passes. (4) *Answers file*: show
`~/.migration/answers.md` and `~/.migration/skipped.md` at the end.

**Round G — keep the machine clean (ask last; the user wants it to stay really clean).** (1) *Dev-tool state*: carry only what's needed
(secrets, keys, Claude light) / also shell history + `.codex`, `.gemini`, `.promptplot`, `.aivss` → delete the unwanted lines from
**`~/.migration/home-carry.txt`** (never from the tracked `packages/home-carry.txt`). (2) *Caches*: prune at the end — recommended / keep
([mac] `brew cleanup -s`; [linux]/[wsl] `sudo apt-get clean && sudo apt-get autoremove --purge`; all: `uv cache prune`, npm, docker).
(3) *Installer backups* (`<file>.<YYYYmmdd-HHMMSS>.backup` that install.sh leaves next to every file it replaces): delete once the
scorecard passes / keep. (4) *Migration notes* (`~/.migration/answers.md`, `skipped.md`): delete at the end / move to `~/Documents`.
Everything not chosen in rounds B–D stays uninstalled; **no ad-hoc installs** afterwards.

## 2. Guide the user on the source (they sit there; Claude instructs from here)

One at a time, wait for "done":
1. 🙋 **Enable ssh.** Mac: macOS 12 Monterey → Apple menu → **System Preferences → Sharing** → tick
   **Remote Login** → "Only these users" includes the user. macOS 13+ → **System Settings → General →
   Sharing → Remote Login** (ⓘ → allow the user). Linux source: `sudo apt install -y openssh-server`.
2. **Detect + choose.** Run `custom_scripts/find_sources.sh` (mDNS + a port-22 sweep of this subnet,
   ~10 s). Show the user the list (IP · name · ssh banner — `dropbear` is usually the router, `OpenSSH`
   + an Apple/Ubuntu name is a computer) and ask with **AskUserQuestion** which one is the source →
   `$SRC` (prefer the IP). Nothing found → re-check step 1, or 🙋 ask for the address the Sharing pane
   shows (`ssh user@<name>`), or the IP (Mac `ipconfig getifaddr en0`; Linux `hostname -I`).
   Then record it: `printf 'export SRC=%s\nexport S=%s@%s\n' "<ip>" "<user>" "<ip>" >> ~/.migration/env`
   (`export`, not a plain assignment: `verify_code.sh` and `check_setup.sh` are child processes and read `S` from the environment).
3. 🙋 **Keep it awake:** Mac → `caffeinate -dis` in a Terminal window left open; Linux →
   `systemd-inhibit --what=sleep:idle sleep infinity`. On power, same network (ethernet = fastest).
4. Verify from here: `source ~/.migration/env; ping -c 2 "$SRC" && nc -zv "$SRC" 22`.
Afterwards (step 10): remind the user to turn Remote Login off and stop caffeinate/inhibit.

## 3. ssh key to the source (no passwords inside Claude)

```bash
source ~/.migration/env
mkdir -p -m 700 ~/.ssh && ssh-keygen -t ed25519 -f ~/.ssh/id_migrate -N "" -C "migrate-$(hostname)"
```
Trust the source's host key first — `ssh-copy-id` can't answer the `yes/no` prompt from Claude's `!` prompt and fails with
`Host key verification failed`: `ssh-keyscan -t ed25519 "$SRC" 2>/dev/null | tee -a ~/.ssh/known_hosts | ssh-keygen -lf -`
(show the fingerprint; the user may compare it on the source with `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub`).
🙋 User runs in a **normal terminal window** (⌘N — not Claude's `!` prompt, which can't take a password; asks the source password once):
`ssh-copy-id -i ~/.ssh/id_migrate.pub <user>@<ip>` (no ssh-copy-id → `cat ~/.ssh/id_migrate.pub | ssh <user>@<ip> 'mkdir -p -m 700 ~/.ssh && cat >> ~/.ssh/authorized_keys'`).
Then complete the env — `SRC_HOME` must be non-empty before anything uses it:
```bash
source ~/.migration/env
src 'echo ok; uname; echo "$HOME"; du -sh ~/Code'                  # must print ok
h=$(src 'printf %s "$HOME"'); [ -n "$h" ] || { echo "SRC_HOME empty — STOP"; exit 1; }
printf 'export SRC_HOME=%s\n' "$h" >> ~/.migration/env
cat >> ~/.migration/env <<'EOF'
[ -n "$S" ] && [ -n "$SRC_HOME" ] || { echo "migration env incomplete — STOP"; return 1 2>/dev/null || exit 1; }
EOF
source ~/.migration/env && echo "env complete: S=$S SRC_HOME=$SRC_HOME OS=$OS" && echo 3 > ~/.migration/state
```
From here on the guard is live: a Bash call whose `source ~/.migration/env` prints `migration env incomplete — STOP`
must not continue.

## 4. Temporary passwordless sudo (Linux/WSL/mac — Claude can't type passwords)

🙋 The user runs once in a normal terminal:
```bash
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/99-migration && sudo chmod 440 /etc/sudoers.d/99-migration && sudo visudo -cf /etc/sudoers.d/99-migration
```
Verify `sudo -n true` (and `visudo -cf` printed `parsed OK`). **Removed as the LAST item of step 10's hygiene gate.**
(Declined → the user runs `./install.sh` in a second terminal and Claude follows its output.)

## 5. Path compatibility (any target, when `$SRC_HOME` ≠ `$HOME`) — automatic, detect it, don't ask

Code, git worktrees (63 use absolute gitdirs), `~/.claude` memory and ~700 configs hard-code
the source home. `source ~/.migration/env; [ "$HOME" = "$SRC_HOME" ] && echo same || echo differs`; if they differ
(e.g. a Mac account called `garassino-juan` → `/Users/garassino-juan`, or a Linux target pulling from `/Users/juan-garassino`),
make the source path resolve here — one sudo:
- linux/wsl: `sudo mkdir -p "$(dirname "$SRC_HOME")" && sudo ln -sfn "$HOME" "$SRC_HOME"`.
- mac: `[ -e "$SRC_HOME" ] && echo "already exists — STOP and ask" || sudo ln -s "$HOME" "$SRC_HOME"`
  (never `-f` over a real folder: it could be another account's home).
Files stay byte-identical, so the verification steps still hold; the symlink just lets the old absolute paths work.

## 5b. 🙋 Scope: clean and light — ASK before copying anything

Default to **light**. Measure on the source first (`src 'du -sk <path>'`; the sizes below were measured
2026-10-22 and drift), then ask with **AskUserQuestion** — recommended option first, sizes in the descriptions:

1. **Claude history** — *Light (recommended, ~80 MB)*: memory, standing notes, plans, skills, agents, plugins,
   prompt history; old sessions can't be resumed. *Full (~25 GB)*: also every session transcript.
   Light = the filter files written in step 1a (include first, then exclude). Full = `: > ~/.migration/claude-include.txt; : > ~/.migration/claude-exclude.txt`.
   Dry-run measured: 24.6 GB → 77 MB with the light filter (step 6 re-checks that number before the real copy).
2. **Work data under `~/Code/002-engenious/`** (multiSelect; recommend **include** — slow or costly to regenerate):
   `src 'cd Code/002-engenious && du -sk */* 2>/dev/null | sort -n | tail -8'` and offer each folder above ~1 GB (eval caches,
   extraction results, OCR data were 5–14 GB each). Paths and sizes go in `answers.md`, not in this public file.
3. **Training outputs** (multiSelect; recommend **skip** — regenerated by training, or carried on the USB stick):
   `005-products/027-ml-workspace/building-segmentation/out` ~18 GB · `005-products/027-ml-workspace/landcover-segmentation/out` ~2.7 GB ·
   `005-products/027-ml-workspace/building-segmentation/data` ~2 GB · `001-archives/downloads_projects_2026/garassino-ml-results` ~2 GB.
4. **Re-cloneable / course material** (multiSelect; recommend **skip**): `007-sandbox/openclaw` (5.6 GB `.git` of a public
   project) · `004-lewagon-spiced/spiced` + `004-lewagon-spiced/lewagon/official-content` (~7 GB) ·
   `005-products/004-creative-tools/001-PromptPlot/gallery` (2.5 GB) · `005-products/009-mini-networks/playground/.lab-shots` (2.2 GB).

Every path the user declines is appended to `~/.migration/code-excl.txt` as `/<path-relative-to-Code>/` (leading AND trailing
slash) and listed with its size in `~/.migration/skipped.md`, so nothing is missing silently. The same file drives rsync (step 7),
`verify_code.sh` and `check_setup.sh --code` (via `MIGRATE_EXCL`), so the skipped paths never show up as differences.
Then total it: `src 'du -sk Code'` minus the skipped sizes = what will be copied; re-check `df -h ~` ≥ 1.3 × that.
Build output (`dist`, `build`, `target`, `.cache`) was measured: 0 GB extra, no need to exclude. Regenerable environments stay
out either way (fixed list in step 1a). `echo 5 > ~/.migration/state`.

## 6. Pull the dev setup outside ~/Code

**Personal machine restored through a buffer (10d)?** Then the dev config comes from `"${S}:handover/home/"` and the credentials from the
encrypted archive — follow 10d steps 6–7 for this step, not the commands below as written.

Gate first — the light filter must really be light (include file FIRST, then exclude):
```bash
source ~/.migration/env
rsync -arn --stats --files-from="$HOME/.migration/home-carry.txt" \
  --include-from="$HOME/.migration/claude-include.txt" --exclude-from="$HOME/.migration/claude-exclude.txt" \
  "${S}:" ~/ 2>/dev/null | grep -E 'Total transferred file size'     # light ≈ 77 MB; full ≈ 25 GB. GBs with light → filter wrong, STOP
```
Then the real copy:
```bash
source ~/.migration/env
rsync -ar --stats --files-from="$HOME/.migration/home-carry.txt" \
  --include-from="$HOME/.migration/claude-include.txt" --exclude-from="$HOME/.migration/claude-exclude.txt" \
  --exclude .ssh/config --exclude .ssh/known_hosts --exclude .ssh/authorized_keys --exclude .claude/settings.json \
  --exclude .claude/statusline-command.sh "${S}:" ~/ 2>&1 | tee ~/.migration/logs/06-home.log   # exit 23 = some listed path absent: fine
rsync -a "${S}:.claude.json" ~/.claude.json.src            # MCP servers, merged in step 9
```
- ngrok token (path has a space — don't let rsync/ssh split it): Mac source → Mac target
  `(umask 077; mkdir -p ~/Library/Application\ Support/ngrok; src 'cat "Library/Application Support/ngrok/ngrok.yml"' > ~/Library/Application\ Support/ngrok/ngrok.yml)`;
  Linux/WSL target: `(umask 077; mkdir -p ~/.config/ngrok; src 'cat "Library/Application Support/ngrok/ngrok.yml"' > ~/.config/ngrok/ngrok.yml)`;
  Linux source: read `.config/ngrok/ngrok.yml` instead.
- Perms: `chmod 600 ~/.secrets ~/.secrets-cheatsheet.md ~/.engenious_university.env; chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_*; chmod 644 ~/.ssh/*.pub`.
- Keys: linux → `eval $(ssh-agent) && ssh-add ~/.ssh/id_ed25519_personal ~/.ssh/id_ed25519_work`;
  mac → `ssh-add --apple-use-keychain …`. Verify `ssh -T git@github.com` → `Hi juan-garassino`.
- **Claude history is keyed by path** — only when `$SRC_HOME` ≠ `$HOME`, so sessions can be resumed here.
  Sessions, memory, plans, standing: copy each `~/.claude/projects/<src-slug>-*` to the slug with `$HOME`
  (`/` → `-`), keeping the original and never overwriting what this machine already wrote. The old slug comes
  from `$SRC_HOME` (it is NOT always `-Users-juan-garassino` — a Linux buffer source has `-home-<user>`):
  ```bash
  source ~/.migration/env
  old="$(printf %s "$SRC_HOME" | tr / -)"; new="$(printf %s "$HOME" | tr / -)"
  cd ~/.claude/projects && for d in ./"$old"*; do [ -d "$d" ] || continue; d=${d#./}
    n="$new${d#"$old"}"; mkdir -p -- "./$n" && rsync -a --ignore-existing -- "./$d/" "./$n/"; done
  ```
  (`rsync --ignore-existing` is the portable `cp --update=none`: macOS `cp` has no such flag.)
  The prompt-history rewrite needs `jq` and is done in step 9 (fresh Ubuntu has no jq until install.sh ran).
  Old transcripts contain the source's absolute paths; they keep working through step 5's symlink.
- Code comes ONLY from `~/Code` (step 7). Never copy Desktop/Downloads/Documents — not even code found there.
- `echo 6 > ~/.migration/state`.

## 7. Pull ~/Code (≈110 G before the 5b skips, ≈68 G after the recommended ones; resumable — re-run if interrupted)

Long run: start it with the Bash tool's **`run_in_background`**, logging to `~/.migration/logs/07-code.log`,
and watch the log instead of blocking (Intel Mac → Apple Silicon over gigabit ethernet: expect 20–40 min; Wi-Fi: hours).
```bash
source ~/.migration/env
rsync -aH --partial --stats --exclude-from="$MIGRATE_EXCL" "${S}:Code/" ~/Code/ > ~/.migration/logs/07-code.log 2>&1
echo "rsync exit $?" >> ~/.migration/logs/07-code.log
```
When the log ends with `rsync exit 0` (24 = a file vanished on the source — re-run; anything else → read the log), `echo 7 > ~/.migration/state`.
The dotfiles checkouts are excluded (this machine has its own clone). macOS sources ship
rsync 2.6.9 — it works, just scans all ~665k files before sending; it rejects every `--info=` flag (use `--stats`); **don't `brew install rsync` on an
unsupported (old) Mac** (it compiles OpenSSL from source). An rsync checksum dry-run (`-anc --itemize-changes`, same
`--exclude-from`, no `--stats`) is an optional extra: any itemized line is a difference — but it is NOT the proof; step 7b is.

## 7b. Prove ~/Code — BEFORE step 8/9 touch it

The proof is `custom_scripts/verify_code.sh` (read-only on every side; works with BSD/GNU userland, zsh or bash):
`verify_code.sh [--excl-file F] [--source SPEC] [--peer SPEC]... [--root DIR] [--canary] [--keep DIR] [-h]`,
SPEC = `'SSHCMD USER@HOST'` or `local:/abs/dir`. Defaults: `--excl-file "$MIGRATE_EXCL"`, `--source "$MIGRATE_SSH $S"` — both come
from `~/.migration/env`, so with the env sourced no flags are needed. It runs `custom_scripts/code_manifest.pl` locally and on every
remote (`perl - Code --exclude-b64 <b64> < code_manifest.pl` over ssh — nothing is copied to the remote) with the same excludes:
one line per entry `type mode size sha256 linktarget-or-dash path` (NFC + escaped paths, bytewise sort) plus, with `--git`, per-repo
`G <repo> HEAD|REF|STASH|INDEX|STATUS …` lines (all refs except `refs/remotes/*`, stash, `ls-files -s` hash, porcelain status hash;
git runs with `--no-optional-locks`, `GIT_OPTIONAL_LOCKS=0`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `LC_ALL=C` — never
writes). It compares every pair and prints `PASS a=b` / `FAIL a≠b` (+ first differing lines) and `CASE-COLLISION <path>` /
`ERRORS <n>` from each side. Exit **0** = every pair PASS and every side `ERRORS 0`; **1** = any FAIL; **2** = usage; **3** = the canary
was missed. `--canary` is the positive control: it briefly creates `~/Code/.migration-canary-<random>` locally only (by design — a
trap removes it even on failure), checks that run FAILS, removes it, then runs for real — so a PASS can't be a false pass.
Other side specs: `USER@HOST` alone uses `$MIGRATE_SSH`; `local:/abs/dir` compares a directory on this machine (tests, a mounted disk).
**Duration:** measured 2026-10-23 on the Intel source: ~20 min for its side (≈632 k entries, 331 repos). Sides run in parallel; with
`--canary` the remotes are computed once (their canary-pass manifests are reused — they are frozen and the canary is local only) and
only `here` is computed twice, so a check takes ≈ the slowest side + one local pass (≈25–30 min with a fast new Mac as `here`). Always launch it with the Bash tool's **`run_in_background: true`** (the tool stops
foreground commands after 10 min) and wait for the completion notice; never poll in a loop.
```bash
source ~/.migration/env
cd ~/Code/000-config/001-dotfiles && custom_scripts/verify_code.sh --canary > ~/.migration/logs/07b-verify.log 2>&1; rc=$?
echo "verify exit $rc" >> ~/.migration/logs/07b-verify.log; tail -5 ~/.migration/logs/07b-verify.log   # run_in_background: true
```
Must end in `verify exit 0` (`PASS here=source`). A FAIL here means the copy is incomplete: re-run step 7, then this. Only then
`echo 7b > ~/.migration/state` and continue. Normalisations the manifest applies (so later steps don't break the proof): a worktree
`.git` FILE is hashed with its absolute prefix up to `/Code/` stripped, `.git/config` is hashed without `ignorecase =` lines, and
`.git/index`, `.git/worktrees/*/{index,gitdir}`, `.git/FETCH_HEAD` are skipped — step 9's `core.ignorecase` flip and `git worktree
repair` are therefore the ONLY allowed post-copy changes. Anything else (commits, checkouts, `envup`, prune) waits until step 10 PASSED.

## 8. Install the toolchain (Claude runs it, narrating each phase)

Long run: `run_in_background`, log to `~/.migration/logs/08-install.log`. Interview answers go **on the command line** (nothing to `export`;
each Bash call is fresh). `install.sh` is non-interactive and idempotent — re-run it as often as needed.
```bash
source ~/.migration/env
cd ~/Code/000-config/001-dotfiles
git remote set-url origin git@github.com:juan-garassino/dotfiles.git && git fetch -q
HOMEBREW_BUNDLE_CASK_SKIP="<declined casks from answers.md, space-separated>" BAUHAUS_ICONS=yes|no BAUHAUS_MAC_EXTRAS=yes|no \
  ./install.sh > ~/.migration/logs/08-install.log 2>&1 < /dev/null; echo "install exit $?" >> ~/.migration/logs/08-install.log
```
`install.sh` writes nothing in `~/Code` outside this (excluded) clone, so it may run **in parallel with the 7b proof** to save ~30 min —
but no re-login (it would kill the proof) and no `claude mcp list` (it starts stdio MCP servers, e.g. `uv run` inside `~/Code`) until
the final proof passed. "Some bundle entries failed" with exit 0 is common — read the `Error:` lines:
- `Refusing to load formula <tap>/<name> from untrusted tap` (Homebrew ≥ 7 tap trust): the Brewfile line needs `, trusted: true`;
  until then `brew trust <tap>` + `brew install <tap>/<name>`.
- [mac] a cask whose app is already in `/Applications` (e.g. preinstalled Chrome) fails on `chgrp … Operation not permitted`
  (macOS App Management): the app is fine — leave it, or give the terminal App Management and `brew install --cask --force`.
- **linux/wsl:** apt (core, build deps, ffmpeg, tesseract, git-lfs, go, mkcert, `postgresql-client`, `perl`, `rsync`, `jq`) +
  `linux-tools.sh` (docker+compose, gcloud, terraform, kubectl, helm, aws, minikube, k3d, act, runpodctl,
  cloud-sql-proxy, ngrok, rustup, Warp, llm, ollama). wsl: skips Warp (use Warp for Windows) and enables
  systemd → 🙋 `wsl --shutdown` in PowerShell, reopen, re-run `./install.sh`.
- **mac:** Homebrew (noninteractive) + Brewfile (incl. the desktop-app casks minus `HOMEBREW_BUNDLE_CASK_SKIP`); `docker compose` via
  `cliPluginsExtraDirs` merged into `~/.docker/config.json`; `libpq` linked (`psql`, `pg_dump`); `tlrc` provides `tldr`.
- **Desktop apps (official sources only)** — linux: 🙋 ask which groups, then `packages/linux-apps.sh [core dev comms sync graphics]`
  (`--check` to verify); mac: the Brewfile casks; wsl: 🙋 user runs `packages/windows-apps.txt` with winget in PowerShell.
  Bauhaus icons are **opt-in** (Round D; macOS ≥ 13 → recommended `no`): install.sh asks on a terminal and without one it skips
  them, so pass the answer: `BAUHAUS_ICONS=yes|no` (Mac extras — Dock tiles + re-apply after app updates: `BAUHAUS_MAC_EXTRAS=yes|no`).
  Mac: one sudo prompt for root-owned apps; or run `custom_scripts/bauhaus_icons.py --mac` / `--mac-dock` / `--mac-watch` later by hand.
- **all:** MesloLGS NF + terminal font 14, OMZ + plugins, Powerlevel10k + `~/.p10k.zsh`, Warp settings
  (`dracula`), uv + Python 3.11/3.12/3.13 + ruff/pre-commit, nvm + LTS + npm globals, VS Code
  settings + 48 extensions, global git ignore, Claude status line/settings/skills/agents. Every file it replaces is kept
  next to the original as `<file>.<YYYYmmdd-HHMMSS>.backup` (the hygiene gate lists them).
- **Postgres = containers only** (host gets `psql`/`pg_dump`). See step 9 for data.
- [mac] No re-login needed: zsh is already the login shell and colima needs no group. 🙋 The user opens a **new** Warp window (new
  fonts + PATH; decline the p10k wizard) and runs the guided logins there; this Claude session — and any running proof — stays alive.
  Start Docker once with `colima start --ssh-config=false` (without the flag colima appends an `Include` to `~/.ssh/config`, which is
  a symlink into this public repo; install.sh turns it off for later starts).
- [linux]/[wsl] After the log ends with `install exit 0`: `sudo chsh -s $(command -v zsh) $USER`; **write `echo 8 > ~/.migration/state` NOW**, then
  🙋 **re-login** (zsh + docker group) — the re-login ends this Claude session. The user reopens Claude in
  `~/Code/000-config/001-dotfiles`; on restart read `~/.migration/state` (and `answers.md`) and **resume at step 8's guided logins** —
  don't redo earlier steps. First zsh: **decline** the p10k wizard. Open Warp → should look like the old machine.
  Terminals opened before install.sh don't see the new fonts (glyphs show as boxes) — the re-login fixes it.

### Guided logins (one at a time; print the command, user runs it, verify)
1. 🙋 `gh auth login` → GitHub.com · SSH · skip key upload · browser → Authorize as `juan-garassino`.
2. 🙋 again → Authorize as `j-garassino-engenious`. Verify `gh auth status` (both) and the cd-switch:
   `~/Code` → `juan-garassino`, `~/Code/002-engenious` → `j-garassino-engenious`.
3. GCP: carried `~/.config/gcloud` usually works — `gcloud auth list`; `gcloud projects list` shows the expected personal
   and work projects (compare with the source: `src 'gcloud projects list --format="value(projectId)"'`). Else 🙋 `gcloud auth login` + `gcloud auth application-default login`.
4. AWS: `aws sts get-caller-identity` (carried `~/.aws`); report failures, don't guess.
5. runpod: `runpodctl config --apiKey "$RUNPOD_API_KEY"` (key from `~/.secrets`). Codex: 🙋 `codex login`.
   ngrok: `ngrok config check`.

## 9. Settle the code and data (only the two allowed changes touch `~/Code`)

- **MCP servers:** merge the source's `~/.claude.json` servers (user + per-project), rewriting paths. `SRC_HOME` must be non-empty
  (the env guard enforces it — an empty `$s` would make `sub("^"; $h)` prefix every key):
  ```bash
  source ~/.migration/env; [ -n "$SRC_HOME" ] || exit 1
  jq -s --arg h "$HOME" --arg s "$SRC_HOME" '.[0] as $n | .[1] as $o
    | $n + {mcpServers: (($n.mcpServers // {}) + ($o.mcpServers // {})),
            projects: (($n.projects // {}) * (($o.projects // {}) | with_entries(.key |= sub("^"+$s; $h))
                       | map_values({mcpServers: (.mcpServers // {})})))}' \
    ~/.claude.json ~/.claude.json.src > ~/.migration/cj.tmp && mv ~/.migration/cj.tmp ~/.claude.json && chmod 600 ~/.claude.json
  ```
  Then restart Claude and check `claude mcp list` against the source (`src 'claude mcp list'`) and `claude/mcp-servers.md` — **after the
  final proof**: it launches stdio servers (`uv run --directory ~/Code/…` creates a `.venv` there) on both machines.
- **Prompt history (up-arrow)** — only when `$SRC_HOME` ≠ `$HOME`; append path-rewritten copies of the source entries:
  ```bash
  source ~/.migration/env; [ -n "$SRC_HOME" ] || exit 1
  jq -c --arg s "$SRC_HOME" --arg h "$HOME" 'select((.project // "") | startswith($s)) | .project |= sub("^"+$s; $h)' \
    ~/.claude/history.jsonl > ~/.migration/h.tmp && cat ~/.migration/h.tmp >> ~/.claude/history.jsonl && rm ~/.migration/h.tmp
  ```
- **git, per repo** (Linux is case-sensitive; Mac paths moved) — allowed change 1, **[linux]/[wsl] only**:
  `find ~/Code -name .git -prune -exec sh -c 'git -C "$(dirname "$1")" config core.ignorecase false' _ {} \;`
  [mac] skip it: APFS is case-insensitive like the source, so `core.ignorecase = true` is correct there.
  Allowed change 2: `git worktree repair` in every repo that has worktrees
  (`find ~/Code -path '*/.git/worktrees' -prune -print`). **No `git worktree prune` yet** — it happens in step 10c, after the final
  proof. First `git status` per repo rehashes — normal. Fresh WIP of every source worktree outside `~/Code` is captured in 10c too.
- **Tracked `.DS_Store`** (committed by mistake, excluded by rsync → shows as deleted): leave it until step 10 PASSED, then restore from git —
  `git ls-files -d | grep -E '(^|/)(\.DS_Store|\._[^/]*)$' | xargs -r git checkout --` in each repo (changes `~/Code` → after the proof).
- **Scratch-worktree WIP** (uncommitted work from `~/.claude-tmp` worktrees), **if present**: `~/Archive/migration/env-snapshots/worktree-wip-*/INDEX.txt`
  lists branch + repo; apply `*.patch` and untar `*.untracked.tgz` in a fresh worktree of that branch when the user wants it (after step 10).
- **Databases, if present:** start each compose stack, then restore its dump from `~/Archive/migration/env-snapshots/` (`*-pgdumpall-*.sql.gz`
  → `gunzip -c … | docker exec -i <postgres-container> psql -U <user> -d postgres`; `*-pgdata-*.tgz` → untar into the named volume before first start).
- **Envs:** `mysandbox` once; project envs on touch with `envup` — **after step 10** (`.venv` is excluded from the proof, but `uv sync`
  can touch lockfiles). `terraform init` where `.terraform` was dropped.
- **macOS-only bits in code** (report, fix only if the user asks): `caffeinate` in Makefiles (→ `systemd-inhibit`), `brew install`
  hints in Makefiles, launchd plists / cron wrappers (→ a systemd user timer on Linux). Find them: `grep -rl --include=Makefile -e caffeinate -e 'brew install' ~/Code`.
- `echo 9 > ~/.migration/state`.

## 10. Verify + clean up (print a PASS/FAIL scorecard)

**Code first** (work repos are irreplaceable) — the same proof as 7b, now after install.sh and step 9:
```bash
source ~/.migration/env
cd ~/Code/000-config/001-dotfiles && custom_scripts/verify_code.sh --canary > ~/.migration/logs/10-verify.log 2>&1; echo "verify exit $?" >> ~/.migration/logs/10-verify.log   # run_in_background: true (~20 min)
custom_scripts/check_setup.sh > ~/.migration/logs/10-scorecard.log 2>&1; echo "scorecard exit $?" >> ~/.migration/logs/10-scorecard.log
```
`verify_code.sh` must exit 0 again (the manifest normalises the two step-9 changes). `check_setup.sh` prints the setup scorecard (shell,
look, identity, uv, every tool, docker, Claude + MCPs, secrets perms, migration hygiene, git worktrees). Its `--code SPEC` option runs the
same code proof by delegating to `verify_code.sh` (honours `MIGRATE_EXCL`/`MIGRATE_SSH`; SPEC = `USER@HOST`, `'SSHCMD USER@HOST'` or
`local:/dir`; `--deep` is accepted and ignored — the proof is always byte-level) — not needed here because the line above already ran
it. Exit code = FAIL count (capped at 125). Fix every FAIL (or explain it), re-run until clean. The bullets below are the manual equivalents/extras.

- `zsh -i -c 'source custom_scripts/preflight_gauntlet.sh'` (OS-specific checks → N/A with reason).
- Look: p10k icons + green `personal`; `cd ~/Code/002-engenious` → orange `work`; Warp `dracula`.
- Tools: `docker compose version`, `minikube version`, `kubectl version --client`, `psql --version`,
  `terraform -version`, `gcloud --version`, `rustc --version`, `ngrok version`, `claude mcp list`.
- Fingerprint by eye: `custom_scripts/code_fingerprint.sh --exclude-from "$MIGRATE_EXCL"` here; on the source the same script
  only exists if its checkout has this version — otherwise compare the `G` lines of the manifests that
  `verify_code.sh --keep ~/.migration/manifests` leaves behind → `diff` empty.
- Teaching stacks (containers only): ask first (GBs) → `custom_scripts/validate_teaching.sh` + `make build-mle`.
- 3 `envup` spot-checks; `docker run --rm hello-world`; `uv run --python 3.12 python -V`.

### 10b. 3-way proof (Round F.2: a Linux buffer machine exists — needed before the source Mac becomes Linux)

Three independent pairs must PASS: new Mac ↔ source, buffer ↔ source, new Mac ↔ buffer. Run it **before step 10c** (and, if the buffer
was filled early, also right after 7b): the only post-copy differences the manifest tolerates are the step-9 ones.
1. Buffer prerequisites (🙋 on the buffer, Ubuntu/Debian): `sudo apt install -y openssh-server rsync perl && perl -MDigest::SHA -e1 && echo perl-ok`
   (Debian/Ubuntu base images lack `Digest::SHA`; the full `perl` package has it). Its user@host → `BUF`.
2. Authorize this machine's migration key on the buffer — trust its host key first, as in step 3
   (`ssh-keyscan -t ed25519 <buffer-ip> 2>/dev/null | tee -a ~/.ssh/known_hosts | ssh-keygen -lf -`), then 🙋 in a normal terminal
   `ssh-copy-id -i ~/.ssh/id_migrate.pub <user>@<buffer-ip>`; then
   `printf 'export BUF=%s\n' '<user>@<buffer-ip>' >> ~/.migration/env` (appending after the guard line is fine — it only tests `S`/`SRC_HOME`).
   The buffer itself needs ssh to the source:
   🙋 on the buffer `ssh-keygen -t ed25519 -f ~/.ssh/id_migrate -N ""` + `ssh-copy-id -i ~/.ssh/id_migrate.pub <user>@<source-ip>`.
3. Make the buffer an **exact mirror** of the source with the **same exclude list**. A buffer that already holds an older `~/Code` is
   only updated (fast), but it needs `--delete` — otherwise files deleted or renamed on the source since then stay there and check 2
   FAILs. **Section P must have been done first** if the buffer ever had its own work. Excluded paths (the buffer's Linux `.venv`,
   `node_modules`, …) are protected from deletion; never use `--delete-excluded`. Dry run first, then the real run:
   ```bash
   source ~/.migration/env
   scp -i ~/.ssh/id_migrate -o IdentitiesOnly=yes "$MIGRATE_EXCL" "${BUF}:code-excl.txt"
   B="mkdir -p ~/Code && rsync -aH --partial --delete -e 'ssh -i ~/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes' --exclude-from=code-excl.txt"
   ssh -i ~/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes "$BUF" "$B -n --itemize-changes '${S}:Code/' ~/Code/" > ~/.migration/logs/10b-buffer-dry.log 2>&1
   grep -c '^\*deleting' ~/.migration/logs/10b-buffer-dry.log; grep '^\*deleting' ~/.migration/logs/10b-buffer-dry.log | head -50
   ```
   🙋 Show the user the number of deletions and the list (grouped by top-level folder) and wait for "go". Then the real run
   (`run_in_background`, log it):
   ```bash
   source ~/.migration/env
   B="mkdir -p ~/Code && rsync -aH --partial --delete --stats -e 'ssh -i ~/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes' --exclude-from=code-excl.txt"
   ssh -i ~/.ssh/id_migrate -o IdentitiesOnly=yes -o BatchMode=yes "$BUF" "$B '${S}:Code/' ~/Code/" > ~/.migration/logs/10b-buffer.log 2>&1
   ```
   `--delete` only ever points at the buffer (the destination); the source is never written.
   (`--exclude-from=code-excl.txt` is relative to the buffer's home, where the ssh command starts — never `=~/…`: a `~` after `=` is not
   expanded, and rsync would abort on a missing file.) After the proof: `ssh … "$BUF" 'rm -f ~/code-excl.txt'`.
4. **Freeze the source** (🙋 nothing edits `~/Code` there; `caffeinate` still running) and run all three pairs from here:
   ```bash
   source ~/.migration/env
   cd ~/Code/000-config/001-dotfiles && custom_scripts/verify_code.sh --canary --source "$MIGRATE_SSH $S" --peer "$MIGRATE_SSH $BUF" > ~/.migration/logs/10b-3way.log 2>&1; echo "3way exit $?" >> ~/.migration/logs/10b-3way.log   # run_in_background: true
   ```
   Expected: three `PASS` lines (`PASS here=source`, `PASS here=peer1`, `PASS source=peer1`) and `3way exit 0`. Linux `core.ignorecase` noise in `.git/config` is
   normalised by the manifest; any other FAIL is real — re-sync that side and re-run. Record the three PASS lines in `answers.md`.
   **One known Mac↔Linux exception:** a repo that tracks a path in one case while the disk has another (`makefile` in git,
   `Makefile` on disk — seen in `lewagon/official-content/data-engineering/data-engineering-solutions`) reads ` M` on macOS
   (case-insensitive) and ` D` on Linux. Only the `G … STATUS` line differs, never a file line, and no copy can remove it. Confirm it
   rather than assume it: run `git --no-optional-locks status --porcelain` in that repo on both sides and `diff` — every differing
   line must name a path that differs from a tracked one only by case. Anything else is real.
   The buffer is now a valid source for the next target (`S=<BUF>`, `SRC_HOME=/home/<user>` — step 5's symlink handles the different home).

### 10c. After the proof: worktree rescue + prune, `.DS_Store` restore, envs

Only now `~/Code` may change. For every repo with worktrees: before any `git worktree prune`, save the commit each dangling worktree
HEAD points to — one commit was reachable ONLY from a worktree HEAD (its branch had moved on):
```bash
# zsh (save to a file and run `zsh <file>` — Claude's Bash shell disables extended globs)
setopt extended_glob null_glob
for wt in ~/Code/**/.git/worktrees/*(N); do
  repo="${wt%/.git/worktrees/*}"; name="${wt##*/}"
  gd="$(cat "$wt/gitdir" 2>/dev/null)"; [ -e "$gd" ] && continue            # worktree still exists (or repair fixed it)
  h="$(cat "$wt/HEAD")"
  if [[ "$h" == "ref: "* ]]; then                                           # on a branch: the branch holds the commit
    git -C "$repo" rev-parse --verify -q "${h#ref: }" >/dev/null || echo "MISSING BRANCH ${h#ref: } ($name, $repo)"
  else                                                                       # detached: only the worktree holds it
    git -C "$repo" branch "rescue/$name" "$h" 2>/dev/null && echo "rescue/$name = $h ($repo)" | tee -a ~/.migration/answers.md
  fi
done
```
Any `MISSING BRANCH` line → STOP and ask. Then, **before the source is wiped**, check whether the dangling worktrees still exist **on
the source** (Claude scratch worktrees live in `~/.claude-tmp/…/scratchpad/`, outside `~/Code` — in the 2026-10-24 run all 81 did, 20
with uncommitted work). Their commits are already here (worktrees share the repo's `.git`); only uncommitted changes are at risk:
```bash
source ~/.migration/env
cat > ~/.migration/wtpaths.zsh <<'EOF'
setopt extended_glob null_glob
for wt in ~/Code/**/.git/worktrees/*(N); do gd="$(cat "$wt/gitdir" 2>/dev/null)"; [ -e "$gd" ] || echo "${gd%/.git}"; done
EOF
zsh ~/.migration/wtpaths.zsh | sed "s|^$HOME|$SRC_HOME|" | sort -u > ~/.migration/wt-dangling.txt
src 'while read -r p; do [ -d "$p" ] && { n=$(git -C "$p" --no-optional-locks status --porcelain | wc -l); [ "$n" -gt 0 ] && echo "$n $p"; }; done' \
  < ~/.migration/wt-dangling.txt > ~/.migration/wt-dirty.txt                 # src reads the list on stdin here — intended
D=~/Archive/migration/env-snapshots/worktree-wip-$(date +%F); mkdir -p "$D"; : > "$D/INDEX.txt"
while read -r n p <&3; do                                                    # list on fd 3: every src below gets </dev/null,
  tag="$(basename "$(dirname "$(dirname "$p")")" | cut -c1-8)-${p##*/}"     # otherwise ssh eats the rest of the list
  hd="$(src "git -C '$p' rev-parse HEAD" </dev/null)"; br="$(src "git -C '$p' rev-parse --abbrev-ref HEAD" </dev/null)"
  src "git -C '$p' --no-optional-locks diff --binary HEAD" </dev/null > "$D/$tag.patch"
  src "cd '$p' && git ls-files -o --exclude-standard -z | tar -czf - --null -T -" </dev/null > "$D/$tag.untracked.tgz"
  printf '%s\tbranch=%s\thead=%s\tpath=%s\tchanged=%s\n' "$tag" "$br" "$hd" "$p" "$n" >> "$D/INDEX.txt"
done 3< ~/.migration/wt-dirty.txt
wc -l < "$D/INDEX.txt"; wc -l < ~/.migration/wt-dirty.txt                  # must be equal
```
Check every `head=` commit exists here (`git -C <repo> cat-file -e <sha>^{commit}`) so each patch can be applied later.
Then `git worktree prune` and check every rescued HEAD is reachable (`git branch --contains <sha>`). Then the `.DS_Store` restore and the
`envup`/`mysandbox` runs from step 9. These are deliberate divergences from the source — list them in `answers.md`.

### 10d. Personal data through the buffer (only for a personal machine — Round A role = Personal or Both)

Used when a source machine is about to be wiped and re-used as the personal machine (e.g. the Intel Mac becoming Linux). This runbook
otherwise never copies Documents/Downloads/Pictures; this section is the explicit exception, and its data never goes to a coding-only target.
Everything flows OUT of the source: a Claude session **on the source** pushes to the buffer (only a source → buffer key is needed:
`ssh-keygen -t ed25519 -f ~/.ssh/id_buffer -N ""` + 🙋 `ssh-copy-id -i ~/.ssh/id_buffer.pub <user>@<buffer-ip>`). The buffer stores
the personal data under `~/handover/` — never mixed with the buffer's own files, and deleted later with one `rm -rf ~/handover`.
On the source: `BUF=<user>@<buffer-ip>; R="ssh -i $HOME/.ssh/id_buffer -o IdentitiesOnly=yes -o BatchMode=yes"; $R "$BUF" 'mkdir -p ~/handover/home'`.
Lists live in `~/migration-staging/` on the source (never in `~/Code`).

**Out (source → buffer, before the wipe gate; every copy `run_in_background` and logged):**
1. **Code mirror** (instead of 10b step 3, which pulls): the buffer will be the source of the personal machine, so it gets ALL of `~/Code`
   — only the fixed exclude list (`code-excl-fixed.txt`: the regenerable dirs + the two dotfiles checkouts), not the user's 5b skips.
   `rsync -aH --partial --delete -e "$R" --exclude-from=code-excl-fixed.txt -n --itemize-changes ~/Code/ "${BUF}:Code/"` →
   🙋 user reviews the `*deleting` count/list → same without `-n` and with `--stats`. Then tell the target's agent: "the buffer is
   already mirrored from the source — skip 10b step 3, run step 4 only" (its exclude list still applies to every side of the proof).
2. **Personal folders.** Exclude list `data-excl.txt`: `.DS_Store`, `._*`, `/Photos Library.photoslibrary/` (an iCloud cache — the
   photos live in iCloud Photos; check them on another device), `.Trash/`. Folders (user's list; default Documents, Downloads,
   Pictures, Movies, `migration-staging`, `git-bundles`, `env-snapshots`, `migration-snapshot`; Dropbox only as a fallback copy):
   `rsync -aH --partial --stats -e "$R" --exclude-from=data-excl.txt ~/<folder>/ "${BUF}:handover/<folder>/"`.
   Never open or describe files in `private_unopened` folders or `Downloads/to_drive`; copy them as-is.
3. **Dev config of THIS machine** (non-secret part of `home-carry.txt`, light Claude history) into `handover/home/` — the personal
   machine takes it from there, never from the buffer's own home (that one has the buffer's keys and Claude):
   `printf '%s\n' .claude .codex/config.toml .gemini/antigravity .promptplot .aivss > home-plain.txt` and
   `rsync -aHr --partial --stats -e "$R" --files-from=home-plain.txt --include-from=claude-include.txt --exclude-from=claude-exclude.txt --exclude .claude/settings.json --exclude .claude/statusline-command.sh ~/ "${BUF}:handover/home/"`
   (claude include/exclude = the light filter of step 1a; the dry run with `-n --stats` must show ≈ 80 MB).
4. **Credentials + histories** — one encrypted archive (they are NOT taken from the buffer's home). Build the list of what exists:
   `cd ~ && for p in .secrets .secrets-cheatsheet.md .engenious_university.env .ssh .ssh_backup_20241029 .aws .config/gcloud .bigqueryrc .config/dotfiles .claude.json "Library/Application Support/ngrok/ngrok.yml" .config/ngrok/ngrok.yml .zsh_history .psql_history .python_history; do [ -e "$p" ] && printf '%s\n' "$p"; done > ~/migration-staging/creds-list.txt`
   then 🙋 the user runs, with OpenSSL 3 (`openssl version`; on the Intel Mac `/usr/local/bin/openssl`, not the system LibreSSL):
   `cd ~ && tar -czf - -T migration-staging/creds-list.txt | /usr/local/bin/openssl enc -aes-256-cbc -pbkdf2 -salt -out ~/migration-staging/handover-credentials.tgz.enc`
   (passphrase twice — store it in a password manager; without it the keys are gone). 🙋 **Test-decrypt before the wipe**:
   `/usr/local/bin/openssl enc -d -aes-256-cbc -pbkdf2 -in ~/migration-staging/handover-credentials.tgz.enc | tar -tzf - | wc -l` (= the
   file count, no error). The archive travels with `migration-staging` (step 2); check its `shasum -a 256` on both sides.
   **Unencrypted variant (the user's choice on 2026-10-24 — this is the one that exists):** `cd ~ && (umask 077; tar -czf
   ~/migration-staging/handover-credentials.tgz -T migration-staging/creds-list.txt)` → copied to the buffer as
   `~/handover/migration-staging/handover-credentials.tgz` (file 600, `~/handover` 700). It holds plain SSH keys, `.secrets`, cloud
   credentials and tokens, so it **must be erased** on the buffer and on the target right after step 7 (and the hygiene gate checks it).
5. **Proof** per folder of 2 and 3: `perl ~/Code/000-config/001-dotfiles/custom_scripts/code_manifest.pl <dir> --exclude-from data-excl.txt`
   here vs on the buffer (`$R "$BUF" "perl - handover/<folder> --exclude-b64 <b64>" < code_manifest.pl`; for `home` use an exclude list of
   just `.DS_Store`): `cmp` silent, both stderr end with `ERRORS 0`. For `~/Code`: the target's 3-way proof (10b step 4).

**In (buffer → personal machine; the buffer is `$S`):** the target's agent runs the runbook with the buffer as the source, with these changes:
6. **Step 6 (dev setup outside ~/Code)** takes `"${S}:handover/home/"` as the rsync source instead of `"${S}:"`, with `~/.migration/home-carry.txt`
   reduced to the 5 plain entries of 3; skip the `rsync -a "${S}:.claude.json"` line (it is in the archive). For the Claude-slug copy loop
   (step 6) and the prompt-history rewrite (step 9) the old prefix is the ORIGINAL machine's home, not the buffer's:
   `printf 'ORIG_HOME=/Users/juan-garassino\n' >> ~/.migration/env` and use `$ORIG_HOME` where those steps say `$SRC_HOME`.
7. **Credentials** — never extract straight into `~` (it would overwrite this machine's new `~/.claude.json` and `~/.ssh`). Use whichever
   archive exists on the buffer (`ls ~/handover/migration-staging/handover-credentials.tgz*` there):
   - **unencrypted `.tgz`** (what exists for the 2026-10-24 migration) — the agent runs, no passphrase:
     `mkdir -p -m 700 ~/.migration/creds && rsync -a "${S}:handover/migration-staging/handover-credentials.tgz" ~/.migration/ && tar -xzf ~/.migration/handover-credentials.tgz -C ~/.migration/creds`
     (GNU tar prints `Ignoring unknown extended header keyword 'LIBARCHIVE.xattr…'` — harmless macOS metadata.)
   - encrypted `.tgz.enc` — 🙋 the user runs
     `mkdir -p -m 700 ~/.migration/creds && rsync -a "${S}:handover/migration-staging/handover-credentials.tgz.enc" ~/.migration/ && openssl enc -d -aes-256-cbc -pbkdf2 -in ~/.migration/handover-credentials.tgz.enc | tar -xzf - -C ~/.migration/creds`

   then the agent places them:
   ```bash
   source ~/.migration/env; C=~/.migration/creds
   rsync -a --exclude config --exclude 'known_hosts*' --exclude authorized_keys --exclude 'id_buffer*' --exclude 'id_migrate*' "$C/.ssh/" ~/.ssh/
   for p in .secrets .secrets-cheatsheet.md .engenious_university.env .ssh_backup_20241029 .aws .config/gcloud .bigqueryrc .config/dotfiles .zsh_history .psql_history .python_history; do
     [ -e "$C/$p" ] && mkdir -p "$HOME/$(dirname "$p")" && rsync -a "$C/$p" "$HOME/$(dirname "$p")/"; done
   [ -f "$C/.claude.json" ] && cp "$C/.claude.json" ~/.claude.json.src          # merged in step 9 like a normal source
   for n in "$C/Library/Application Support/ngrok/ngrok.yml" "$C/.config/ngrok/ngrok.yml"; do [ -f "$n" ] && mkdir -p ~/.config/ngrok && cp "$n" ~/.config/ngrok/ngrok.yml; done
   chmod 700 ~/.ssh; chmod 600 ~/.ssh/id_* ~/.secrets 2>/dev/null; chmod 644 ~/.ssh/*.pub 2>/dev/null; chmod 600 ~/.config/ngrok/ngrok.yml 2>/dev/null
   rm -rf "$C" ~/.migration/handover-credentials.tgz ~/.migration/handover-credentials.tgz.enc
   ```
   **Then erase the archive on the buffer too** — it holds plain credentials (the unencrypted variant) and nothing needs it any more:
   `src 'rm -f ~/handover/migration-staging/handover-credentials.tgz ~/handover/migration-staging/handover-credentials.tgz.enc && ls ~/handover/migration-staging | grep -c handover-credentials || true'`
   → must print `0`. Record "credentials archive erased (buffer + here)" in `~/.migration/answers.md`. (The source machine's own copy in
   `~/migration-staging/` disappears with its wipe.)
8. **Personal folders**: `rsync -aH --partial "${S}:handover/<folder>/" ~/<folder>/` for each — on Linux **Movies → `~/Videos`** — then the
   manifest `cmp` of 5 against the buffer (must be silent).
9. Dropbox: install the app and let it sync from the cloud (no folder copy → no conflict copies).
10. Backup from day one: Déjà Dup or restic to an encrypted external drive (or cloud). **`~/handover` on the buffer is deleted only after
    the first full backup finished** — until then it is the second copy of the personal files. The buffer then keeps only `~/Code`.

### Hygiene gate — leave nothing behind (run even if a step above failed or the run was interrupted; print a residue table)

Order matters: sudo is needed until the very last item. The zshrc aliases `mv -i` / `cp -i` apply inside Claude's Bash and block on a
prompt when overwriting — use `command mv -f` / `command cp -f` here.
  0. **Credentials archive gone (10d):** `ls ~/.migration/handover-credentials.tgz* ~/.migration/creds 2>/dev/null` here and
     `src 'ls ~/handover/migration-staging/handover-credentials.tgz* 2>/dev/null'` on the buffer must both print nothing — if not, erase them now.
  1. `<file>.<YYYYmmdd-HHMMSS>.backup` files install.sh made (`find ~ -maxdepth 4 -name '*.backup' -not -path '*/Code/*'`) → list, then delete if Round G said so.
  2. Caches (Round G): [mac] `brew cleanup -s` · [linux]/[wsl] `sudo apt-get clean && sudo apt-get autoremove --purge` · all: `uv cache prune`, `docker system prune -af` only if no wanted container runs, `npm cache clean --force`.
  3. Software audit against the interview answers: [mac] `brew list --cask` + `brew leaves`, `ls ~/Library/LaunchAgents` (only what was
     asked, e.g. the icon watcher) · [linux]/[wsl] `apt-mark showmanual` vs `packages/apt.txt` + chosen app groups, `systemctl --user list-unit-files --state=enabled`.
     Everywhere: no stray `pip install --user`, global npm or pyenv.
  4. Path-compat symlink from step 5 is intentional: say so and how to remove it (`sudo rm "$SRC_HOME"` — it is a symlink, check with `ls -l` first).
  5. [linux]/[wsl] `sudo systemctl disable --now ssh` unless this machine will be a source or buffer later (Round F.2) — then say it stays on.
  6. `rm -f ~/.claude.json.src` once the MCPs work; rsync partials and temp lists in `~/` (`ls -A ~ | grep -i -E 'rsync|partial|migrat'` → only `.migration` may remain).
  7. Migration key: `rm -f ~/.ssh/id_migrate ~/.ssh/id_migrate.pub`; `ssh-keygen -R "$SRC"` (and `-R "$BUF"`) drops them from `known_hosts`; then `rm -f ~/.ssh/known_hosts.old`.
  8. Migration notes: per Round G move `~/.migration/answers.md` + `skipped.md` to `~/Documents/migration-$(date +%F)/` or let them go; then `rm -rf ~/.migration`
     (logs included — print the residue table BEFORE this, from the logs).
  9. On the **source**, remind (the user does it): Remote Login / sshd off, stop `caffeinate` (Mac) or `systemd-inhibit` (Linux), and delete the `migrate-<host>` line
     from `~/.ssh/authorized_keys` (same on the buffer). `git checkout main` in this dotfiles clone.
  10. **LAST:** `sudo rm -f /etc/sudoers.d/99-migration` → `sudo -n true` must now FAIL (this is the most dangerous leftover).
  Finish with a residue report: `sudoers.d` empty of ours · no `id_migrate` · no `known_hosts` entry · no `known_hosts.old` · no `*.backup` · no `~/.migration` ·
  no temp files · sshd state · caches size · `df -h`.

## Hard rules

- Source is read-only: only `rsync`/`ssh` reads. No `--delete` toward it, no installs on it.
- Never echo secret values; never commit `~/.secrets`, keys, GCP JSON, `.env` into any repo.
- Push protection / rule violations: report, never bypass. Work repos never go to personal remotes.
- **Leave nothing behind:** every temporary thing the migration creates (NOPASSWD sudoers file, `id_migrate` key, `known_hosts`
  entries, rsync partials, `~/.claude.json.src`, `*.backup`, `~/.migration`, caches) is removed by step 10's hygiene gate — also when
  the run is interrupted or fails. Install only what the interview selected.
- `~/Code` is not modified between step 7 and the step-10 PASS, except the two normalised step-9 changes.
- Ambiguous → one short question.

## State of GitHub (2026-10-14) — the backup layer

- All personal repos, all branches pushed; dirty trees committed (`wip/pre-migration-2026-10-14`
  where the branch was the default). Pre-rewrite backups: `~/Archive/migration/git-bundles/pre-fix-2026-10-14/`.
- 10 formerly loose dirs are private repos (`candidate-assistant`, `graphrag-integration`,
  `custom-graphrag`, `chroma-rag`, `emoji-generation`, `adversarial-diffusion`, `orchestration-coreo`,
  `multiagent-orchestrator`, `nlsql`, `assessment`). SelfGPT → fork `juan-garassino/SelfGPT` (remote `mine`).
- rsync-only by design: `002-engenious`, `000-config` root, `012-temps`, loose non-repo
  files, neuefische `ds-curriculum` local commit, `.env`, `~/.claude`, keys.
- Keys to rotate (were in local-only history): SelfGPT OpenAI key, achievementsAI Azure key.
