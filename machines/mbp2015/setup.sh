#!/usr/bin/env bash
# 2015 15" MacBook Pro (MacBookPro11,4 / 11,5) on Ubuntu — everything this machine needs on top of
# install.sh: SSD write cap, fan curve, battery turbo guard, battery-display + Bluetooth recovery,
# zram, leaner services, Toshy user slices, reversed workspace swipe, tap-to-click off.
# Why each piece exists: MIGRATE.md → "2015 MacBook Pro → Ubuntu". Idempotent.
#
#   machines/mbp2015/setup.sh           install / re-apply (asks for sudo)
#   machines/mbp2015/setup.sh --check   only report what differs from this folder
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
mode="${1:-install}"
model="$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)"
case "$model" in
  MacBookPro11,4|MacBookPro11,5) ;;
  *) [[ " $* " == *" --force "* ]] || { echo "Not a 2015 15\" MacBook Pro ('$model') — nothing to do (add --force to override)."; exit 1; } ;;
esac

# file list: <repo path under root/ or home/>  →  live path
root_files() { (cd "$here/root" && find . -type f | sed 's|^\./||' | sort); }
home_files() { (cd "$here/home" && find . -type f | sed 's|^\./||' | sort); }
fthd_src="$(ls -d /usr/src/facetimehd-* 2>/dev/null | sort -V | tail -1)"

# merge_toshy_slices [--dry-run] — copy each slice body in toshy-slices.py into the live toshy_config.py
merge_toshy_slices() {
  python3 - "$here/toshy-slices.py" "$HOME/.config/toshy/toshy_config.py" "${1:-}" <<'PY'
import re, sys
src, dst, dry = sys.argv[1], sys.argv[2], sys.argv[3] == "--dry-run"
mark = r"(###  SLICE_MARK_START: {0}  ###[^\n]*\n)(.*?)(###  SLICE_MARK_END: {0}  ###)"
old = new = open(dst).read()
for name, body in re.findall(r"###  SLICE_MARK_START: (\w+)  ###[^\n]*\n(.*?)###  SLICE_MARK_END: \1  ###",
                             open(src).read(), re.S):
    new = re.sub(mark.format(name), lambda x: x.group(1) + body + x.group(3), new, flags=re.S)
if new != old and not dry:
    open(dst, "w").write(new)
print("changed" if new != old else "same")
PY
}

if [ "$mode" = --check ]; then
  rc=0
  while read -r f; do
    if [ ! -e "/$f" ]; then echo "missing  /$f"; rc=1
    elif ! cmp -s "$here/root/$f" "/$f"; then echo "differs  /$f"; rc=1; fi
  done < <(root_files)
  while read -r f; do
    if [ ! -e "$HOME/$f" ]; then echo "missing  ~/$f"; rc=1
    elif ! cmp -s "$here/home/$f" "$HOME/$f"; then echo "differs  ~/$f"; rc=1; fi
  done < <(home_files)
  if [ -f ~/.config/toshy/toshy_config.py ]; then
    [ "$(merge_toshy_slices --dry-run)" = same ] || { echo "differs  Toshy user slices"; rc=1; }
  else echo "missing  Toshy (~/.config/toshy/toshy_config.py)"; rc=1; fi
  grep -q 'libata.force=noncq' /proc/cmdline || { echo "missing  libata.force=noncq on the kernel command line"; rc=1; }
  dpkg -s kdump-tools >/dev/null 2>&1 && { echo "present  kdump-tools (reserves 512 MB)"; rc=1; }
  if [ -n "$fthd_src" ]; then
    grep -q crbug.com/249953 "$fthd_src/fthd_v4l2.c" || { echo "missing  facetimehd discrete-sizes patch (Chrome/Meet see no camera)"; rc=1; }
    [ "$(cat /sys/module/facetimehd/srcversion 2>/dev/null)" = "$(modinfo -F srcversion facetimehd 2>/dev/null)" ] \
      || { echo "stale    loaded facetimehd module (reboot, or close camera apps and reload it)"; rc=1; }
  fi
  [ $rc = 0 ] && echo "✓ machine matches machines/mbp2015"
  exit $rc
fi

echo "▶ packages"
sudo apt-get install -y mbpfan systemd-zram-generator usbutils >/dev/null
dpkg -s kdump-tools >/dev/null 2>&1 && sudo apt-get purge -y kdump-tools >/dev/null

echo "▶ system files"
initramfs=0
while read -r f; do
  cmp -s "$here/root/$f" "/$f" && continue
  case "$f" in usr/local/sbin/*) m=755 ;; *) m=644 ;; esac
  sudo install -D -m $m "$here/root/$f" "/$f" && echo "  → /$f"
  case "$f" in etc/udev/rules.d/60-*|etc/modprobe.d/*) initramfs=1 ;; esac
done < <(root_files)

if ! grep -q 'libata.force=noncq' /etc/default/grub; then
  sudo sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 libata.force=noncq"/' /etc/default/grub
fi
sudo update-grub >/dev/null 2>&1
[ $initramfs = 1 ] && sudo update-initramfs -u

# facetimehd lists one STEPWISE size range, which Chrome skips: patch it to discrete sizes, rebuild for every kernel
if [ -n "$fthd_src" ] && ! grep -q crbug.com/249953 "$fthd_src/fthd_v4l2.c"; then
  echo "▶ camera driver"
  if sudo patch -s -p1 -d "$fthd_src" < "$here/facetimehd-discrete-sizes.patch"; then
    v="${fthd_src##*/facetimehd-}"
    for k in $(dkms status "facetimehd/$v" 2>/dev/null | sed -n 's|^facetimehd/[^,]*, \([^,]*\),.*installed.*|\1|p'); do
      sudo dkms build --force "facetimehd/$v" -k "$k" >/dev/null && sudo dkms install --force "facetimehd/$v" -k "$k" >/dev/null \
        && echo "  → rebuilt for $k"
    done
    { sudo modprobe -r facetimehd && sudo modprobe facetimehd; } 2>/dev/null \
      && echo "  → reloaded (restart Chrome)" || echo "  ! camera in use — reboot to load the new driver"
  else
    echo "  ! patch didn't apply to $fthd_src — new driver version? check machines/mbp2015/facetimehd-discrete-sizes.patch"
  fi
fi

echo "▶ services"
sudo systemctl daemon-reload
sudo systemctl enable upower-refresh.service bt-recover.service battery-turbo.service mbpfan.service >/dev/null 2>&1
sudo systemctl restart mbpfan.service
sudo systemctl enable --now battery-turbo.timer >/dev/null 2>&1
sudo systemctl start battery-turbo.service
systemctl is-active -q systemd-zram-setup@zram0.service || sudo systemctl start systemd-zram-setup@zram0.service
sudo sysctl --system >/dev/null
sudo udevadm control --reload
# idle on this machine: docker starts on first use via docker.socket; no modem; no printer discovery
for s in docker.service containerd.service ModemManager.service cups-browsed.service; do
  systemctl is-enabled -q "$s" 2>/dev/null && sudo systemctl disable --now "$s"
done
snap services cups.cups-browsed 2>/dev/null | grep -q ' enabled ' && sudo snap stop --disable cups.cups-browsed

echo "▶ user files"
while read -r f; do
  install -D -m 644 "$here/home/$f" "$HOME/$f"
done < <(home_files)
systemctl --user daemon-reload
python3 - <<'PY'
import ast, subprocess
uuid = "reverse-workspace-swipe@garassino"
cur = subprocess.run(["gsettings", "get", "org.gnome.shell", "enabled-extensions"],
                     capture_output=True, text=True).stdout.strip().removeprefix("@as ")
exts = ast.literal_eval(cur or "[]")
if uuid not in exts:
    subprocess.run(["gsettings", "set", "org.gnome.shell", "enabled-extensions", str(exts + [uuid])], check=True)
    print("  → enabled", uuid, "(log out and back in once)")
PY
gsettings set org.gnome.desktop.peripherals.touchpad tap-to-click false

if [ -f ~/.config/toshy/toshy_config.py ]; then
  [ "$(merge_toshy_slices)" = changed ] && systemctl --user restart toshy-config.service && echo "  → Toshy slices merged"
else
  echo "  ! Toshy not installed — see MIGRATE.md (Mac-style keys), then re-run this script"
fi
grep -q "^facetimehd " /proc/modules || echo "  ! FaceTime camera driver missing — see MIGRATE.md (facetimehd via DKMS)"

echo "✓ done — reboot once if this was the first run"
