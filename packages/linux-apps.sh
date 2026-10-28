#!/usr/bin/env bash
# Installers/repo setups are dispatched indirectly ("install_$app", "repo_$app").
# shellcheck disable=SC2329,SC1091
# linux-apps.sh — desktop GUI apps for a Linux (Ubuntu/GNOME, x86_64) workstation.
# The GUI counterpart of linux-tools.sh. Official, vendor-supported sources only:
# vendor apt repos (signed-by=, keys fingerprint-checked), verified/vendor snaps,
# vendor .debs, and vendor GitHub releases. Idempotent: an app that is already
# installed is skipped, never reinstalled.
#
# Usage: linux-apps.sh [--check] [--list] [group ...]
#   groups: core dev comms sync graphics   (no group = all)
#   --check  only report installed/missing per app (no changes)
#   --list   print groups and their apps
# Exit status = number of apps that failed to install (or are missing, with --check).
set -uo pipefail

# ---------------------------------------------------------------- platform gate
if [ "$(uname -s)" != Linux ]; then
  echo "linux-apps.sh: not Linux ($(uname -s)) — macOS apps come from the Brewfile. Nothing to do."
  exit 0
fi
if grep -qi microsoft /proc/version 2>/dev/null; then
  echo "linux-apps.sh: WSL detected — install desktop apps on the Windows side. Nothing to do."
  exit 0
fi
if [ "$(dpkg --print-architecture 2>/dev/null)" != amd64 ]; then
  echo "linux-apps.sh: only amd64 is supported (got $(dpkg --print-architecture 2>/dev/null || uname -m)). Nothing to do."
  exit 0
fi

# ---------------------------------------------------------------- groups
declare -A GROUP_APPS=(
  [core]="dbeaver pritunl slack antigravity discord obsidian cursor postman notion claude chatgpt"
  [dev]="pgadmin elasticvue gephi etcher"
  [comms]="zoom telegram spotify"
  [sync]="dropbox nordvpn"
  [graphics]="inkscape blender"
)
GROUP_ORDER=(core dev comms sync graphics)

declare -A LABEL=(
  [dbeaver]="DBeaver CE"        [pritunl]="Pritunl client"   [slack]="Slack"
  [antigravity]="Antigravity IDE" [discord]="Discord"        [obsidian]="Obsidian"
  [cursor]="Cursor"             [postman]="Postman"          [notion]="Notion (web launcher)"
  [claude]="Claude desktop"     [chatgpt]="ChatGPT / Codex desktop"
  [pgadmin]="pgAdmin 4"         [elasticvue]="elasticvue"    [gephi]="Gephi"
  [etcher]="balenaEtcher"       [zoom]="Zoom"                [telegram]="Telegram"
  [spotify]="Spotify"           [dropbox]="Dropbox"          [nordvpn]="NordVPN"
  [inkscape]="Inkscape"         [blender]="Blender (LTS)"
)

# kind: snap:<name>[:classic][@<channel>] | apt:<pkgs> (vendor repo) | deb:<pkg> (vendor .deb) | local (~/.local)
declare -A KIND=(
  [dbeaver]="snap:dbeaver-ce:classic"  [slack]="snap:slack"   [obsidian]="snap:obsidian:classic"
  [postman]="snap:postman"            [telegram]="snap:telegram-desktop"
  [spotify]="snap:spotify"            [inkscape]="snap:inkscape"
  [blender]="snap:blender:classic@5.2lts/stable"
  [pritunl]="apt:pritunl-client-electron" [pgadmin]="apt:pgadmin4-desktop"
  [nordvpn]="apt:nordvpn nordvpn-gui"     [claude]="apt:claude-desktop"
  [discord]="deb:discord"   [cursor]="deb:cursor"     [chatgpt]="deb:chatgpt"
  [zoom]="deb:zoom"         [etcher]="deb:balena-etcher" [elasticvue]="deb:elasticvue"
  [dropbox]="deb:dropbox"
  [antigravity]="local"     [gephi]="local"           [notion]="local"
)

# ---------------------------------------------------------------- paths / helpers
OPT="$HOME/.local/opt"
APPS_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons"
KEYRINGS=/etc/apt/keyrings
SOURCES=/etc/apt/sources.list.d
CODENAME="$(lsb_release -cs 2>/dev/null)"
[ -n "$CODENAME" ] || CODENAME="$(. /etc/os-release && echo "${VERSION_CODENAME:-noble}")"
FALLBACK_CODENAME=noble
APT_ENV=(sudo env DEBIAN_FRONTEND=noninteractive)

declare -a NOTES=()
declare -A RESULT=()

log()  { printf '  %s\n' "$*"; }
warn() { printf '  !! %s\n' "$*" >&2; }

# Fail-fast curl with retries; never prints the body to the terminal.
fetch() { curl -fsSL --retry 2 --connect-timeout 20 -o "$2" "$1"; }

# Echo $CODENAME if <template> (with {CS} placeholder) resolves to a Release file,
# else the fallback LTS codename. Generic "probe suite URL, else noble".
suite_or_noble() {
  local tmpl="$1" url
  url="${tmpl//\{CS\}/$CODENAME}"
  if curl -fsI --connect-timeout 20 "$url" >/dev/null 2>&1; then
    echo "$CODENAME"
  else
    echo "$FALLBACK_CODENAME"
  fi
}

# Download an armored/binary key, check its primary fingerprint, install it.
#   install_key <url> <dest-path> <expected-fpr> <dearmor:yes|no>
install_key() {
  local url="$1" dest="$2" want="$3" dearmor="$4" tmp got
  tmp="$(mktemp)"
  if ! fetch "$url" "$tmp"; then warn "key download failed: $url"; rm -f "$tmp"; return 1; fi
  got="$(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"
  if [ "$got" != "$want" ]; then
    warn "key fingerprint mismatch for $url (got '${got:-none}', want $want)"
    rm -f "$tmp"; return 1
  fi
  sudo install -m 0755 -d "$(dirname "$dest")"
  if [ "$dearmor" = yes ]; then
    sudo gpg --dearmor --yes -o "$dest" "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
    sudo chmod 0644 "$dest"
  else
    sudo install -m 0644 "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
  fi
  rm -f "$tmp"
}

write_list() { echo "$2" | sudo tee "$SOURCES/$1" >/dev/null; }

# Latest GitHub release asset URL whose name matches an ERE (no gh dependency).
gh_asset() {
  local repo="$1" re="$2"
  curl -fsSL --connect-timeout 20 -H 'Accept: application/vnd.github+json' \
      "https://api.github.com/repos/$repo/releases/latest" \
    | grep -oE '"browser_download_url": *"[^"]+"' \
    | sed -E 's/.*"(https[^"]+)"$/\1/' \
    | grep -E "$re" | head -n1
}

deb_installed()  { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'install ok installed'; }
snap_installed() { snap list "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------- detection
is_installed() {
  local app="$1" kind="${KIND[$1]}" p
  case "$kind" in
    snap:*) p="${kind#snap:}"; snap_installed "${p%%:*}" ;;
    apt:*)  for p in ${kind#apt:}; do deb_installed "$p" || return 1; done ;;
    deb:*)  deb_installed "${kind#deb:}" ;;
    local)
      case "$app" in
        antigravity) [ -x "$OPT/antigravity-ide/antigravity-ide" ] && [ -f "$APPS_DIR/antigravity-ide.desktop" ] ;;
        gephi)       [ -x "$OPT/gephi/bin/gephi" ] && [ -f "$APPS_DIR/gephi.desktop" ] ;;
        notion)      [ -f "$APPS_DIR/notion-web.desktop" ] ;;
      esac ;;
  esac
}

# ---------------------------------------------------------------- apt repo setup (batched)
repo_pritunl() {
  local cs; cs="$(suite_or_noble 'https://repo.pritunl.com/stable/apt/dists/{CS}/Release')"
  install_key https://raw.githubusercontent.com/pritunl/pgp/master/pritunl_repo_pub.asc \
    "$KEYRINGS/pritunl.gpg" 7568D9BB55FF9E5287D586017AE645C0CF8E292A yes || return 1
  write_list pritunl.list \
    "deb [arch=amd64 signed-by=$KEYRINGS/pritunl.gpg] https://repo.pritunl.com/stable/apt $cs main"
}
repo_pgadmin() {
  local cs; cs="$(suite_or_noble 'https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/{CS}/dists/pgadmin4/Release')"
  install_key https://www.pgadmin.org/static/packages_pgadmin_org.pub \
    "$KEYRINGS/pgadmin.gpg" E8697E2EEF76C02D3A6332778881B2A8210976F2 yes || return 1
  write_list pgadmin4.list \
    "deb [arch=amd64 signed-by=$KEYRINGS/pgadmin.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$cs pgadmin4 main"
}
repo_nordvpn() {
  # NordVPN uses a distro-independent "stable" suite — no codename probing needed.
  install_key https://repo.nordvpn.com/gpg/nordvpn_public.asc \
    "$KEYRINGS/nordvpn.gpg" BC5480EFEC5C081CE5BCFBE26B219E535C964CA1 yes || return 1
  write_list nordvpn.list \
    "deb [arch=amd64 signed-by=$KEYRINGS/nordvpn.gpg] https://repo.nordvpn.com/deb/nordvpn/debian stable main"
}
repo_claude() {
  # Path + armored .asc exactly as Anthropic's docs (code.claude.com/docs/en/desktop-linux).
  install_key https://downloads.claude.ai/claude-desktop/key.asc \
    /usr/share/keyrings/claude-desktop-archive-keyring.asc 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE no || return 1
  write_list claude-desktop.list \
    "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main"
}

# ---------------------------------------------------------------- installers
install_snap() {
  local spec="${KIND[$1]#snap:}" name classic=() channel=()
  [[ $spec == *@* ]] && { channel=(--channel="${spec#*@}"); spec="${spec%@*}"; }
  name="${spec%%:*}"
  [ "$spec" != "$name" ] && classic=(--classic)
  sudo snap install "$name" "${classic[@]}" "${channel[@]}"
}

install_apt() { local pkgs; read -ra pkgs <<<"${KIND[$1]#apt:}"; "${APT_ENV[@]}" apt-get install -y "${pkgs[@]}"; }

# Download a vendor .deb into a fresh temp dir and install it with apt (resolves deps).
install_deb_url() {
  local url="$1" name="$2" dir rc
  dir="$(mktemp -d)"
  if ! fetch "$url" "$dir/$name"; then warn "download failed: $url"; rm -rf "$dir"; return 1; fi
  "${APT_ENV[@]}" apt-get install -y "$dir/$name"; rc=$?
  rm -rf "$dir"; return "$rc"
}

install_discord() { install_deb_url "https://discord.com/api/download?platform=linux&format=deb" discord.deb; }
install_zoom()    { install_deb_url https://zoom.us/client/latest/zoom_amd64.deb zoom_amd64.deb; }
install_cursor()  { install_deb_url "https://api2.cursor.sh/updates/download/golden/linux-x64-deb/cursor/latest" cursor.deb; }
# Official ChatGPT Linux app (includes Codex); its postinst adds OpenAI's signed apt repo.
install_chatgpt() { install_deb_url https://persistent.oaistatic.com/codex-app-prod/linux/deb/latest/chatgpt_amd64.deb chatgpt_amd64.deb; }

install_elasticvue() {
  local url; url="$(gh_asset cars10/elasticvue '_amd64\.deb$')"
  [ -n "$url" ] || { warn "elasticvue: no amd64 .deb in latest release"; return 1; }
  install_deb_url "$url" elasticvue.deb
}

install_etcher() {
  local deb sums dir want got rc
  deb="$(gh_asset balena-io/etcher '_amd64\.deb$')"
  sums="$(gh_asset balena-io/etcher 'SHA256SUMS\.Linux\.x64\.txt$')"
  [ -n "$deb" ] && [ -n "$sums" ] || { warn "etcher: release assets not found"; return 1; }
  dir="$(mktemp -d)"
  if ! fetch "$deb" "$dir/etcher.deb" || ! fetch "$sums" "$dir/sums.txt"; then rm -rf "$dir"; return 1; fi
  want="$(grep -F "$(basename "$deb")" "$dir/sums.txt" | awk '{print $1}')"
  got="$(sha256sum "$dir/etcher.deb" | awk '{print $1}')"
  if [ -z "$want" ] || [ "$want" != "$got" ]; then
    warn "etcher: SHA256 mismatch (want ${want:-none}, got $got)"; rm -rf "$dir"; return 1
  fi
  "${APT_ENV[@]}" apt-get install -y "$dir/etcher.deb"; rc=$?
  rm -rf "$dir"; return "$rc"
}

install_dropbox() {
  local latest rc cs
  latest="$(curl -fsSL https://linux.dropbox.com/packages/ubuntu/ \
            | grep -oE 'dropbox_[0-9.]+_amd64\.deb' | sort -uV | tail -n1)"
  [ -n "$latest" ] || { warn "dropbox: could not resolve latest .deb"; return 1; }
  install_deb_url "https://linux.dropbox.com/packages/ubuntu/$latest" "$latest"; rc=$?
  # Its postinst writes dropbox.list with this release's codename; Dropbox lags new releases.
  if [ -f "$SOURCES/dropbox.list" ]; then
    cs="$(suite_or_noble 'http://linux.dropbox.com/ubuntu/dists/{CS}/Release')"
    sudo sed -i -E "s#(linux\.dropbox\.com/ubuntu) [a-z]+ main#\1 $cs main#" "$SOURCES/dropbox.list"
  fi
  NOTES+=("Dropbox: launch it once to download the sync daemon, then link your account.")
  return "$rc"
}

install_antigravity() {
  local url dir rc=0
  # The IDE tarball URL is versioned; scrape it from Google's download page.
  url="$(curl -fsSL --compressed https://antigravity.google/download 2>/dev/null \
         | grep -oE 'https://[^"'\'' <>]*/linux-x64/Antigravity%20IDE\.tar\.gz' | head -n1)"
  if [ -z "$url" ]; then
    warn "Antigravity: could not find the linux-x64 IDE tarball on antigravity.google/download."
    NOTES+=("Antigravity: manual — download 'Antigravity IDE' (Linux x64 tar.gz) from https://antigravity.google/download, extract to $OPT/antigravity-ide, re-run.")
    return 1
  fi
  dir="$(mktemp -d)"
  fetch "$url" "$dir/ag.tar.gz" || { rm -rf "$dir"; return 1; }
  mkdir -p "$OPT" "$APPS_DIR" "$ICONS_DIR"
  rm -rf "$OPT/antigravity-ide.new"; mkdir -p "$OPT/antigravity-ide.new"
  tar xzf "$dir/ag.tar.gz" -C "$OPT/antigravity-ide.new" --strip-components=1 || rc=1
  rm -rf "$dir"
  [ "$rc" = 0 ] && [ -x "$OPT/antigravity-ide.new/antigravity-ide" ] || { rm -rf "$OPT/antigravity-ide.new"; return 1; }
  rm -rf "$OPT/antigravity-ide"; mv "$OPT/antigravity-ide.new" "$OPT/antigravity-ide"
  # Electron sandbox from a home dir needs a setuid-root helper on Ubuntu (userns restriction).
  sudo chown root:root "$OPT/antigravity-ide/chrome-sandbox" && sudo chmod 4755 "$OPT/antigravity-ide/chrome-sandbox"
  cp "$OPT/antigravity-ide/resources/app/resources/linux/code.png" "$ICONS_DIR/antigravity-ide.png"
  cat > "$APPS_DIR/antigravity-ide.desktop" <<EOF
[Desktop Entry]
Name=Antigravity IDE
Comment=Google Antigravity agentic IDE
Exec="$OPT/antigravity-ide/antigravity-ide" %F
Icon=$ICONS_DIR/antigravity-ide.png
Type=Application
Terminal=false
Categories=Development;IDE;
StartupWMClass=Antigravity IDE
StartupNotify=true
EOF
  NOTES+=("Antigravity IDE lives in $OPT (not apt-managed): re-run after removing it to update.")
}

install_gephi() {
  local url dir rc=0
  url="$(gh_asset gephi/gephi 'linux-x64\.tar\.gz$')"
  [ -n "$url" ] || { warn "gephi: no linux-x64 tarball in latest release"; return 1; }
  dir="$(mktemp -d)"
  fetch "$url" "$dir/gephi.tar.gz" || { rm -rf "$dir"; return 1; }
  mkdir -p "$OPT" "$APPS_DIR" "$ICONS_DIR"
  rm -rf "$OPT/gephi.new"; mkdir -p "$OPT/gephi.new"
  tar xzf "$dir/gephi.tar.gz" -C "$OPT/gephi.new" --strip-components=1 || rc=1
  rm -rf "$dir"
  [ "$rc" = 0 ] && [ -x "$OPT/gephi.new/bin/gephi" ] || { rm -rf "$OPT/gephi.new"; return 1; }
  rm -rf "$OPT/gephi"; mv "$OPT/gephi.new" "$OPT/gephi"
  cp "$OPT/gephi/flathub/gephi.png" "$ICONS_DIR/gephi.png" 2>/dev/null
  cat > "$APPS_DIR/gephi.desktop" <<EOF
[Desktop Entry]
Name=Gephi
Comment=Graph visualization and exploration
Exec="$OPT/gephi/bin/gephi" %F
Icon=$ICONS_DIR/gephi.png
Type=Application
Terminal=false
Categories=Science;DataVisualization;
StartupWMClass=Gephi
EOF
}

install_notion() {
  # Notion has no official Linux app: Chrome app-window on notion.so (no third-party code).
  local icon="applications-internet"
  command -v google-chrome >/dev/null 2>&1 || warn "notion: google-chrome not on PATH (launcher written anyway)"
  mkdir -p "$APPS_DIR" "$ICONS_DIR"
  if fetch https://www.notion.so/images/logo-ios.png "$ICONS_DIR/notion.png.tmp" \
     && file "$ICONS_DIR/notion.png.tmp" | grep -q 'PNG image'; then
    mv "$ICONS_DIR/notion.png.tmp" "$ICONS_DIR/notion.png"; icon="$ICONS_DIR/notion.png"
  else
    rm -f "$ICONS_DIR/notion.png.tmp"
  fi
  cat > "$APPS_DIR/notion-web.desktop" <<EOF
[Desktop Entry]
Name=Notion
Comment=Notion (web app via Chrome)
Exec=google-chrome --app=https://www.notion.so
Icon=$icon
Type=Application
Terminal=false
Categories=Office;
StartupWMClass=www.notion.so
EOF
}

post_nordvpn() {
  sudo usermod -aG nordvpn "$USER" \
    && NOTES+=("NordVPN: log out and back in (nordvpn group), then 'nordvpn login' or use the GUI.")
}

# ---------------------------------------------------------------- arg parsing
MODE=install
declare -a GROUPS_SEL=()
for a in "$@"; do
  case "$a" in
    --check) MODE=check ;;
    --list)  MODE=list ;;
    -h|--help) sed -n '4,14p' "$0"; exit 0 ;;
    *) if [ -n "${GROUP_APPS[$a]+x}" ]; then GROUPS_SEL+=("$a")
       else echo "unknown group: $a (groups: ${GROUP_ORDER[*]})" >&2; exit 64; fi ;;
  esac
done
[ ${#GROUPS_SEL[@]} -eq 0 ] && GROUPS_SEL=("${GROUP_ORDER[@]}")

if [ "$MODE" = list ]; then
  for g in "${GROUP_ORDER[@]}"; do
    printf '%-9s' "$g"
    for app in ${GROUP_APPS[$g]}; do printf ' %s,' "${LABEL[$app]}"; done | sed 's/,$//'
    echo
  done
  exit 0
fi

declare -a SELECTED=()
for g in "${GROUPS_SEL[@]}"; do
  for app in ${GROUP_APPS[$g]}; do SELECTED+=("$app"); done
done

print_table() {
  local fails=0 app st
  printf '\n%-26s %-10s %s\n' APP STATUS SOURCE
  printf '%-26s %-10s %s\n' -------------------------- ---------- ------------------------
  for app in "${SELECTED[@]}"; do
    st="${RESULT[$app]}"
    case "$st" in installed|skipped) ;; *) fails=$((fails + 1)) ;; esac
    printf '%-26s %-10s %s\n' "${LABEL[$app]}" "$st" "${KIND[$app]}"
  done
  return $fails
}

# ---------------------------------------------------------------- check mode
if [ "$MODE" = check ]; then
  for app in "${SELECTED[@]}"; do
    if is_installed "$app"; then RESULT[$app]=installed; else RESULT[$app]=missing; fi
  done
  print_table; fails=$?
  echo; echo "$fails missing."
  exit $fails
fi

# ---------------------------------------------------------------- install mode
sudo -n true 2>/dev/null || sudo -v || { echo "sudo required" >&2; exit 1; }
sudo install -m 0755 -d "$KEYRINGS"

declare -a TODO=()
for app in "${SELECTED[@]}"; do
  if is_installed "$app"; then RESULT[$app]=skipped; log "✓ ${LABEL[$app]} already installed"
  else TODO+=("$app"); fi
done

# 1) vendor apt repos for the apt-kind apps, then a single apt-get update
need_update=0
for app in "${TODO[@]}"; do
  case "${KIND[$app]}" in
    apt:*)
      log "→ repo for ${LABEL[$app]}"
      if "repo_$app"; then need_update=1; else RESULT[$app]="FAILED(repo)"; fi ;;
  esac
done
if [ $need_update = 1 ]; then
  sudo apt-get update -y || warn "apt-get update reported errors"
fi

# 2) install everything still pending
for app in "${TODO[@]}"; do
  [ -n "${RESULT[$app]:-}" ] && continue
  log "→ installing ${LABEL[$app]}"
  case "${KIND[$app]}" in
    snap:*) install_snap "$app" ;;
    apt:*)  install_apt "$app" ;;
    *)      "install_$app" ;;
  esac
  rc=$?
  if [ "$rc" -eq 0 ] && is_installed "$app"; then
    RESULT[$app]=installed
    [ "$app" = nordvpn ] && post_nordvpn
  else
    RESULT[$app]=FAILED
  fi
done

command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS_DIR" 2>/dev/null

print_table; fails=$?
if [ ${#NOTES[@]} -gt 0 ]; then
  echo; echo "Notes / human steps:"
  for n in "${NOTES[@]}"; do echo "  - $n"; done
fi
echo; echo "$fails failure(s)."
exit $fails
