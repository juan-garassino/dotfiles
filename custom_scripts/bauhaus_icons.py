#!/usr/bin/env python3
"""Bauhaus app icons — one design language for every launcher on Linux (GNOME).

Same palette as the p10k prompt / Claude status line: cobalt, ochre, burgundy + grays.
Every icon is a charcoal rounded tile carrying a flat glyph built from circles, squares
and triangles — no gradients, no text.

  bauhaus_icons.py                 write SVGs to ~/.local/share/icons/bauhaus + apply overrides
  bauhaus_icons.py --labels        same, but the variant with the app name set small (Jost)
  bauhaus_icons.py --preview PNG   only write SVGs + render a contact sheet (ImageMagick), no overrides
  bauhaus_icons.py --undo     remove the overrides (system icons come back)

Overrides are per-user copies of each app's .desktop file in ~/.local/share/applications
(same file name → same dock pin) with Icon= pointing at our SVG. Apps that aren't
installed are skipped. Re-run after an app update rewrites its launcher.
"""
import re
import subprocess
import sys
from pathlib import Path

C, O, R = "#6496D7", "#E6B446", "#B94655"          # cobalt · ochre · burgundy
L, M, BG = "#DCDCDC", "#9E9E9E", "#232323"          # light gray · mid gray · tile

ICONS = {
    "warp": f'<polygon points="72,72 140,128 72,184" fill="{C}"/>'
            f'<rect x="140" y="166" width="60" height="18" fill="{O}"/>',
    "terminal": f'<rect x="58" y="66" width="140" height="124" rx="12" fill="none" stroke="{M}" stroke-width="12"/>'
                f'<polygon points="86,100 114,124 86,148" fill="{L}"/>'
                f'<rect x="122" y="140" width="44" height="10" fill="{C}"/>',
    "vscode": f'<polygon points="104,72 52,128 104,184" fill="{C}"/>'
              f'<polygon points="152,72 204,128 152,184" fill="{C}"/>'
              f'<rect x="120" y="64" width="16" height="128" fill="{O}" transform="rotate(18 128 128)"/>',
    "cursor": f'<polygon points="78,56 78,188 112,156 176,154" fill="{L}"/>'
              f'<circle cx="172" cy="184" r="18" fill="{C}"/>',
    "antigravity": f'<polygon points="128,120 198,196 58,196" fill="{C}"/>'
                   f'<circle cx="128" cy="80" r="28" fill="{O}"/>',
    "claude": "".join(f'<rect x="118" y="54" width="20" height="148" rx="10" fill="{O}" transform="rotate({a} 128 128)"/>'
                      for a in (0, 45, 90, 135)),
    "chatgpt": f'<circle cx="128" cy="128" r="64" fill="none" stroke="{O}" stroke-width="20"/>'
               f'<polygon points="110,102 140,128 110,154" fill="{L}"/>',
    "dbeaver": f'<rect x="64" y="66" width="128" height="34" rx="17" fill="{C}"/>'
               f'<rect x="64" y="112" width="128" height="34" rx="17" fill="{M}"/>'
               f'<rect x="64" y="158" width="128" height="34" rx="17" fill="{M}"/>',
    "pgadmin": f'<circle cx="118" cy="114" r="54" fill="{C}"/>'
               f'<rect x="150" y="128" width="20" height="70" rx="10" fill="{M}"/>'
               f'<circle cx="138" cy="100" r="9" fill="{BG}"/>',
    "elasticvue": f'<circle cx="112" cy="112" r="44" fill="none" stroke="{C}" stroke-width="18"/>'
                  f'<rect x="146" y="140" width="22" height="64" rx="6" fill="{O}" transform="rotate(-45 157 172)"/>',
    "postman": f'<circle cx="128" cy="128" r="62" fill="none" stroke="{M}" stroke-width="12"/>'
               f'<circle cx="128" cy="128" r="28" fill="{R}"/>'
               f'<circle cx="172" cy="84" r="15" fill="{O}"/>',
    "slack": f'<rect x="62" y="62" width="58" height="58" rx="14" fill="{C}"/>'
             f'<rect x="136" y="62" width="58" height="58" rx="14" fill="{O}"/>'
             f'<rect x="62" y="136" width="58" height="58" rx="14" fill="{R}"/>'
             f'<rect x="136" y="136" width="58" height="58" rx="14" fill="{M}"/>',
    "discord": f'<rect x="54" y="78" width="148" height="100" rx="42" fill="{R}"/>'
               f'<circle cx="100" cy="126" r="15" fill="{L}"/><circle cx="156" cy="126" r="15" fill="{L}"/>',
    "telegram": f'<circle cx="128" cy="128" r="72" fill="{C}"/>'
                f'<polygon points="82,126 178,88 148,172" fill="{L}"/>'
                f'<polygon points="126,140 148,172 178,88" fill="{M}"/>',
    "zoom": f'<rect x="50" y="86" width="108" height="84" rx="16" fill="{C}"/>'
            f'<polygon points="166,128 206,94 206,162" fill="{O}"/>',
    "firefox": f'<circle cx="128" cy="128" r="72" fill="{O}"/>'
               f'<circle cx="150" cy="114" r="60" fill="{R}"/>',
    "chrome": f'<path d="M128,128 L128,56 A72,72 0 0,1 190.35,164 Z" fill="{R}"/>'
              f'<path d="M128,128 L190.35,164 A72,72 0 0,1 65.65,164 Z" fill="{O}"/>'
              f'<path d="M128,128 L65.65,164 A72,72 0 0,1 128,56 Z" fill="{M}"/>'
              f'<circle cx="128" cy="128" r="34" fill="{BG}"/><circle cx="128" cy="128" r="25" fill="{C}"/>',
    "files": f'<rect x="56" y="70" width="64" height="32" rx="8" fill="{O}"/>'
             f'<rect x="56" y="88" width="144" height="100" rx="12" fill="{O}"/>'
             f'<rect x="56" y="112" width="144" height="10" fill="{BG}" fill-opacity=".25"/>',
    "settings": "".join(f'<rect x="114" y="50" width="28" height="156" rx="6" fill="{M}" transform="rotate({a} 128 128)"/>'
                        for a in (0, 45, 90, 135))
                + f'<circle cx="128" cy="128" r="54" fill="{M}"/><circle cx="128" cy="128" r="26" fill="{BG}"/>'
                  f'<circle cx="128" cy="128" r="11" fill="{C}"/>',
    "obsidian": f'<polygon points="128,50 190,128 128,206 66,128" fill="{C}"/>'
                f'<polygon points="128,50 190,128 128,206" fill="{L}" fill-opacity=".28"/>',
    "notion": f'<rect x="62" y="58" width="132" height="140" rx="12" fill="{L}"/>'
              f'<rect x="90" y="86" width="20" height="84" fill="{BG}"/>'
              f'<rect x="146" y="86" width="20" height="84" fill="{BG}"/>'
              f'<polygon points="90,86 110,86 166,170 146,170" fill="{BG}"/>',
    "gephi": f'<polygon points="80,170 128,80 180,150" fill="none" stroke="{M}" stroke-width="8" stroke-linejoin="round"/>'
             f'<circle cx="80" cy="170" r="20" fill="{C}"/><circle cx="128" cy="80" r="24" fill="{O}"/>'
             f'<circle cx="180" cy="150" r="17" fill="{R}"/>',
    "etcher": f'<rect x="116" y="54" width="24" height="40" fill="{O}"/>'
              f'<polygon points="84,88 172,88 128,150" fill="{O}"/>'
              f'<rect x="62" y="168" width="132" height="22" rx="6" fill="{M}"/>',
    "spotify": f'<circle cx="128" cy="128" r="72" fill="{O}"/>'
               + "".join(f'<path d="{d}" fill="none" stroke="{BG}" stroke-width="12" stroke-linecap="round"/>'
                         for d in ("M84,104 Q128,84 172,108", "M92,132 Q128,116 164,136", "M102,158 Q128,148 154,162")),
    "dropbox": f'<polygon points="92,70 132,98 92,126 52,98" fill="{C}"/>'
               f'<polygon points="164,70 204,98 164,126 124,98" fill="{C}"/>'
               f'<polygon points="128,134 168,162 128,190 88,162" fill="{M}"/>',
    "nordvpn": f'<polygon points="50,190 128,64 206,190" fill="{C}"/>'
               f'<polygon points="128,64 153,104 103,104" fill="{L}"/>',
    "pritunl": f'<path d="M128,54 L190,78 L190,130 Q190,180 128,206 Q66,180 66,130 L66,78 Z" fill="{R}"/>'
               f'<circle cx="128" cy="118" r="17" fill="{L}"/><rect x="121" y="122" width="14" height="40" rx="4" fill="{L}"/>',
    "inkscape": f'<polygon points="72,68 184,68 128,162" fill="{M}"/>'
                f'<circle cx="128" cy="186" r="18" fill="{C}"/>',
    # — system / GNOME apps (the "Show Apps" grid) —
    "security": f'<path d="M128,54 L190,78 L190,130 Q190,180 128,206 Q66,180 66,130 L66,78 Z" fill="{C}"/>'
                f'<polyline points="98,128 120,150 160,104" fill="none" stroke="{L}" stroke-width="16" '
                f'stroke-linecap="round" stroke-linejoin="round"/>',
    "imagemagick": f'<rect x="118" y="64" width="20" height="140" rx="6" fill="{M}" transform="rotate(40 128 134)"/>'
                   f'<polygon points="92,52 100,76 124,84 100,92 92,116 84,92 60,84 84,76" fill="{O}"/>',
    "firmware": "".join(f'<rect x="{x}" y="50" width="14" height="156" fill="{M}"/>' for x in (92, 121, 150))
                + f'<rect x="64" y="64" width="128" height="128" rx="14" fill="{M}"/>'
                  f'<polygon points="128,92 162,150 94,150" fill="{C}"/>',
    "language": f'<rect x="50" y="62" width="104" height="74" rx="18" fill="{O}"/>'
                f'<polygon points="74,130 74,158 100,134" fill="{O}"/>'
                f'<rect x="104" y="110" width="104" height="74" rx="18" fill="{C}"/>'
                f'<polygon points="184,178 184,206 158,182" fill="{C}"/>',
    "texinfo": f'<circle cx="128" cy="128" r="66" fill="none" stroke="{L}" stroke-width="14"/>'
               f'<circle cx="128" cy="96" r="12" fill="{C}"/><rect x="118" y="118" width="20" height="56" rx="6" fill="{C}"/>',
    "resources": f'<rect x="58" y="120" width="34" height="76" rx="6" fill="{C}"/>'
                 f'<rect x="111" y="68" width="34" height="128" rx="6" fill="{O}"/>'
                 f'<rect x="164" y="98" width="34" height="98" rx="6" fill="{R}"/>',
    "network": "".join(f'<path d="M{128 - r * .766:.1f},{172 - r * .643:.1f} A{r},{r} 0 0,1 {128 + r * .766:.1f},{172 - r * .643:.1f}" '
                       f'fill="none" stroke="{c}" stroke-width="16" stroke-linecap="round"/>' for r, c in ((96, M), (64, C), (32, C)))
               + f'<circle cx="128" cy="172" r="13" fill="{O}"/>',
    "nvidia": f'<path d="M48,128 Q128,48 208,128 Q128,208 48,128 Z" fill="{O}"/>'
              f'<circle cx="128" cy="128" r="32" fill="{BG}"/><circle cx="128" cy="128" r="14" fill="{O}"/>',
    "disk-usage": f'<circle cx="128" cy="128" r="58" fill="none" stroke="{M}" stroke-width="28"/>'
                  f'<path d="M128,70 A58,58 0 0,1 186,128" fill="none" stroke="{O}" stroke-width="28"/>'
                  f'<path d="M186,128 A58,58 0 0,1 128,186" fill="none" stroke="{R}" stroke-width="28"/>',
    "calculator": "".join(f'<rect x="{62 + 48 * (i % 3)}" y="{62 + 48 * (i // 3)}" width="36" height="36" rx="8" '
                          f'fill="{[M, M, C, M, M, C, M, M, O][i]}"/>' for i in range(9)),
    "characters": f'<polygon points="74,98 104,156 44,156" fill="{C}"/>'
                  f'<circle cx="134" cy="127" r="29" fill="{O}"/>'
                  f'<rect x="168" y="102" width="50" height="50" fill="{R}"/>',
    "clocks": f'<circle cx="128" cy="128" r="70" fill="none" stroke="{L}" stroke-width="14"/>'
              f'<rect x="121" y="78" width="14" height="58" rx="7" fill="{C}"/>'
              f'<rect x="121" y="121" width="14" height="48" rx="7" fill="{R}" transform="rotate(-120 128 128)"/>',
    "disks": f'<rect x="54" y="86" width="148" height="84" rx="16" fill="{M}"/>'
             f'<rect x="74" y="118" width="64" height="10" rx="4" fill="{BG}"/>'
             f'<rect x="74" y="136" width="44" height="10" rx="4" fill="{BG}"/>'
             f'<circle cx="174" cy="128" r="12" fill="{C}"/>',
    "fonts": f'<circle cx="114" cy="140" r="44" fill="none" stroke="{O}" stroke-width="20"/>'
             f'<rect x="158" y="84" width="20" height="102" rx="6" fill="{O}"/>'
             f'<rect x="60" y="62" width="40" height="14" fill="{C}"/>',
    "logs": f'<rect x="66" y="52" width="124" height="152" rx="12" fill="{L}"/>'
            + "".join(f'<rect x="86" y="{y}" width="{w}" height="10" rx="4" fill="{c}"/>'
                      for y, w, c in ((80, 84, M), (102, 64, M), (124, 84, R), (146, 50, M), (168, 72, M))),
    "images": f'<rect x="50" y="68" width="156" height="120" rx="14" fill="{C}"/>'
              f'<circle cx="168" cy="102" r="14" fill="{O}"/>'
              f'<polygon points="62,178 112,110 156,178" fill="{L}"/>',
    "papers": f'<polygon points="66,52 158,52 190,84 190,204 66,204" fill="{L}"/>'
              f'<polygon points="158,52 190,84 158,84" fill="{M}"/>'
              + "".join(f'<rect x="88" y="{y}" width="80" height="10" rx="4" fill="{C}"/>' for y in (108, 132, 156)),
    "passwords": f'<circle cx="96" cy="128" r="34" fill="none" stroke="{O}" stroke-width="18"/>'
                 f'<rect x="126" y="119" width="80" height="18" fill="{O}"/>'
                 f'<rect x="170" y="137" width="14" height="26" fill="{O}"/><rect x="192" y="137" width="14" height="18" fill="{O}"/>',
    "sysprof": f'<rect x="54" y="160" width="148" height="28" rx="6" fill="{R}"/>'
               f'<rect x="54" y="126" width="110" height="28" rx="6" fill="{O}"/>'
               f'<rect x="54" y="92" width="70" height="28" rx="6" fill="{C}"/>'
               f'<rect x="130" y="92" width="34" height="28" rx="6" fill="{M}"/>',
    "text-editor": f'<rect x="58" y="52" width="116" height="152" rx="12" fill="{L}"/>'
                   + "".join(f'<rect x="78" y="{y}" width="{w}" height="10" rx="4" fill="{M}"/>'
                             for y, w in ((80, 76), (102, 60), (124, 76)))
                   + f'<rect x="150" y="80" width="22" height="118" rx="4" fill="{O}" transform="rotate(30 161 139)"/>',
    "help": f'<circle cx="128" cy="128" r="58" fill="none" stroke="{R}" stroke-width="30"/>'
            + "".join(f'<rect x="120" y="66" width="16" height="32" fill="{L}" transform="rotate({a} 128 128)"/>'
                      for a in (45, 135, 225, 315)),
    "app-center": f'<path d="M100,96 V82 A28,28 0 0,1 156,82 V96" fill="none" stroke="{M}" stroke-width="12"/>'
                  f'<rect x="62" y="92" width="132" height="112" rx="14" fill="{O}"/>'
                  f'<rect x="94" y="132" width="68" height="12" rx="4" fill="{BG}" fill-opacity=".35"/>',
    "updater": f'<path d="M184,128 A56,56 0 1,1 160,82" fill="none" stroke="{C}" stroke-width="20" stroke-linecap="round"/>'
               f'<polygon points="140,58 196,62 176,112" fill="{C}"/>'
               f'<circle cx="128" cy="128" r="14" fill="{O}"/>',
    "vim": f'<polygon points="128,48 208,128 128,208 48,128" fill="{M}"/>'
           f'<polygon points="92,92 116,92 128,136 140,92 164,92 138,170 118,170" fill="{O}"/>',
    "virtualbox": f'<polygon points="128,52 194,90 128,128 62,90" fill="{L}"/>'
                  f'<polygon points="62,90 128,128 128,204 62,166" fill="{C}"/>'
                  f'<polygon points="194,90 128,128 128,204 194,166" fill="{M}"/>',
}

# desktop file ID → icon
APPS = {
    "dev.warp.Warp": "warp", "org.gnome.Ptyxis": "terminal", "com.microsoft.VSCode": "vscode",
    "cursor": "cursor", "antigravity-ide": "antigravity", "com.anthropic.Claude": "claude",
    "chatgpt": "chatgpt", "dbeaver-ce_dbeaver-ce": "dbeaver", "pgadmin4": "pgadmin",
    "elasticvue": "elasticvue", "postman_postman": "postman", "slack_slack": "slack",
    "discord": "discord", "telegram-desktop_telegram-desktop": "telegram", "Zoom": "zoom",
    "firefox_firefox": "firefox", "google-chrome": "chrome", "org.gnome.Nautilus": "files",
    "org.gnome.Settings": "settings", "obsidian_obsidian": "obsidian", "notion-web": "notion",
    "gephi": "gephi", "balena-etcher": "etcher", "spotify_spotify": "spotify",
    "dropbox": "dropbox", "nordvpn-gui": "nordvpn", "pritunl-client-electron": "pritunl",
    "inkscape_inkscape": "inkscape",
    "desktop-security-center_desktop-security-center": "security", "display-im7.q16": "imagemagick",
    "firmware-updater_firmware-updater": "firmware", "gnome-language-selector": "language",
    "info": "texinfo", "net.nokyan.Resources": "resources", "nm-connection-editor": "network",
    "nvidia-settings": "nvidia", "org.gnome.baobab": "disk-usage", "org.gnome.Calculator": "calculator",
    "org.gnome.Characters": "characters", "org.gnome.clocks": "clocks", "org.gnome.DiskUtility": "disks",
    "org.gnome.font-viewer": "fonts", "org.gnome.Logs": "logs", "org.gnome.Loupe": "images",
    "org.gnome.Papers": "papers", "org.gnome.seahorse.Application": "passwords",
    "org.gnome.Sysprof": "sysprof", "org.gnome.TextEditor": "text-editor", "org.gnome.Yelp": "help",
    "snap-store_snap-store": "app-center", "update-manager": "updater", "vim": "vim",
    "virtualbox": "virtualbox",
}

HOME = Path.home()
ICON_DIR = HOME / ".local/share/icons/bauhaus"
LABEL_DIR = HOME / ".local/share/icons/bauhaus-labels"
LOCAL_APPS = HOME / ".local/share/applications"
SYSTEM_APPS = [Path("/var/lib/snapd/desktop/applications"), Path("/usr/share/applications")]
MARK = "X-Bauhaus-Icon=true"


LABELS = {"vscode": "vs code", "disk-usage": "disk usage", "text-editor": "text editor",
          "app-center": "app center", "imagemagick": "magick"}                      # display name when it differs from the key
FONT = "Jost, Futura, 'Ubuntu Sans', sans-serif"     # Jost = open Futura revival (Google Fonts)


def svg(glyph, label=None):
    if label:   # glyph shrinks + lifts; name set small in the bottom band
        size = 30 if len(label) <= 8 else 26
        glyph = (f'<g transform="translate(128 106) scale(.74) translate(-128 -128)">{glyph}</g>'
                 f'<text x="128" y="218" text-anchor="middle" font-family="{FONT}" font-weight="500" '
                 f'font-size="{size}" letter-spacing="1" fill="{L}">{label}</text>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">'
            f'<rect x="8" y="8" width="240" height="240" rx="52" fill="{BG}"/>{glyph}</svg>\n')


def set_icon(text, icon):
    text = re.sub(r"^Icon=.*$", f"Icon={icon}", text, flags=re.M)
    if MARK not in text:
        text = text.replace("[Desktop Entry]\n", f"[Desktop Entry]\n{MARK}\n", 1)
    return text


def write_svgs():
    for d in (ICON_DIR, LABEL_DIR):
        d.mkdir(parents=True, exist_ok=True)
    for name, glyph in ICONS.items():
        (ICON_DIR / f"{name}.svg").write_text(svg(glyph))
        (LABEL_DIR / f"{name}.svg").write_text(svg(glyph, LABELS.get(name, name)))


def apply(icon_dir):
    write_svgs()
    LOCAL_APPS.mkdir(parents=True, exist_ok=True)
    for app, name in APPS.items():
        local = LOCAL_APPS / f"{app}.desktop"
        system = next((d / f"{app}.desktop" for d in SYSTEM_APPS if (d / f"{app}.desktop").exists()), None)
        # Re-copy from the system launcher each run so app updates are picked up;
        # launchers that only exist locally (tarball apps, web apps) are edited in place.
        src = system or (local if local.exists() else None)
        if not src:
            print(f"  ⏭️  {app} not installed")
            continue
        local.write_text(set_icon(src.read_text(), icon_dir / f"{name}.svg"))
        print(f"  🎨 {app} → {name}")
    subprocess.run(["update-desktop-database", str(LOCAL_APPS)], check=False)


def undo():
    for app in APPS:
        local = LOCAL_APPS / f"{app}.desktop"
        if not local.exists() or MARK not in local.read_text():
            continue
        system = any((d / f"{app}.desktop").exists() for d in SYSTEM_APPS)
        if system:
            local.unlink()                      # pure override → drop it
            print(f"  ↩️  {app}")
        else:
            print(f"  ⚠️  {app} launcher is local-only — restore its Icon= by hand")
    subprocess.run(["update-desktop-database", str(LOCAL_APPS)], check=False)


def preview(out):
    """Contact sheet (plain row over labelled row per app) via librsvg — what GNOME renders with."""
    write_svgs()
    tmp = Path(out).with_suffix("")
    tmp.mkdir(parents=True, exist_ok=True)
    pngs = []
    for d, tag in ((ICON_DIR, ""), (LABEL_DIR, "-l")):
        for n in ICONS:
            png = tmp / f"{n}{tag}.png"
            subprocess.run(["rsvg-convert", "-w", "128", "-h", "128", "-o", str(png), str(d / f"{n}.svg")], check=True)
            pngs.append(str(png))
    subprocess.run(["montage", "-background", "#F2F2F2", *pngs, "-geometry", "128x128+10+10",
                    "-tile", "14x", out], check=True)
    print(f"  🖼️  {out}")


if __name__ == "__main__":
    if "--undo" in sys.argv:
        undo()
    elif "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        preview(sys.argv[i + 1] if len(sys.argv) > i + 1 else "/tmp/bauhaus-icons.png")
    else:
        apply(LABEL_DIR if "--labels" in sys.argv else ICON_DIR)
