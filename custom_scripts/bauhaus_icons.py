#!/usr/bin/env python3
"""Bauhaus app icons — one design language for every launcher on Linux (GNOME).

Same palette as the p10k prompt / Claude status line: cobalt, ochre, burgundy + grays.
Every icon is a rounded tile in one primary (Kandinsky-balanced, ~a third each) carrying a
flat gray glyph built from circles, squares and triangles; the other primaries stay as
accents. No gradients.

  bauhaus_icons.py                 write SVGs to ~/.local/share/icons/bauhaus + apply overrides
  bauhaus_icons.py --labels        same, but the variant with the app name set small (Jost)
  … --dark                         the earlier charcoal-tile look (combine with --labels)
  bauhaus_icons.py --preview PNG   only write SVGs + render a contact sheet (ImageMagick), no overrides
  bauhaus_icons.py --undo     remove the overrides (system icons come back)
  bauhaus_icons.py --mac [--undo]  macOS: set (or clear) each installed app's custom icon + Apple-app launchers
  bauhaus_icons.py --mac-dock [--undo]  macOS: swap Apple-app Dock tiles for the launchers (backup → undo)
  bauhaus_icons.py --mac-watch [--undo] macOS: LaunchAgent that re-applies icons after app updates (--mac-heal)

Overrides are per-user copies of each app's .desktop file in ~/.local/share/applications
(same file name → same dock pin) with Icon= pointing at our SVG. Apps that aren't
installed are skipped. Re-run after an app update rewrites its launcher.
"""
import json
import plistlib
import re
import subprocess
import sys
from pathlib import Path
from urllib.parse import unquote

C, O, R = "#6496D7", "#E6B446", "#B94655"          # cobalt · ochre · burgundy
L, M, BG = "#DCDCDC", "#9E9E9E", "#232323"          # light gray · mid gray · tile

def cloud(c, dx=0, dy=0, k=1):
    return (f'<g transform="translate({dx} {dy}) translate(128 140) scale({k}) translate(-128 -140)">'
            f'<circle cx="94" cy="146" r="30" fill="{c}"/><circle cx="136" cy="122" r="44" fill="{c}"/>'
            f'<circle cx="172" cy="148" r="28" fill="{c}"/><rect x="64" y="140" width="136" height="36" rx="18" fill="{c}"/></g>')


ICONS = {
    "warp": f'<polygon points="72,72 140,128 72,184" fill="{C}"/>'
            f'<rect x="140" y="166" width="60" height="18" fill="{O}"/>',
    "terminal": f'<rect x="58" y="66" width="140" height="124" rx="12" fill="none" stroke="{M}" stroke-width="12"/>'
                f'<polygon points="86,100 114,124 86,148" fill="{L}"/>'
                f'<rect x="122" y="140" width="44" height="10" fill="{C}"/>',
    "vscode": f'<polygon points="88,92 52,128 88,164" fill="{C}"/><polygon points="168,92 204,128 168,164" fill="{C}"/>'
              f'<rect x="121" y="58" width="14" height="140" rx="4" fill="{O}" transform="rotate(20 128 128)"/>',
    "cursor": f'<polygon points="128,56 190,92 128,128 66,92" fill="{L}"/>'
              f'<polygon points="66,92 128,128 128,200 66,164" fill="{C}"/>'
              f'<polygon points="190,92 128,128 128,200 190,164" fill="{M}"/>',
    "antigravity": f'<path d="M70,204 V128 A58,58 0 0,1 186,128 V204" fill="none" stroke="{C}" stroke-width="30"/>'
                   f'<circle cx="128" cy="134" r="22" fill="{O}"/>',
    "claude": "".join(f'<rect x="118" y="54" width="20" height="148" rx="10" fill="{O}" transform="rotate({a} 128 128)"/>'
                      for a in (0, 45, 90, 135)),
    "chatgpt": f'<circle cx="128" cy="128" r="64" fill="none" stroke="{O}" stroke-width="20"/>'
               f'<polygon points="110,102 140,128 110,154" fill="{L}"/>',
    "dbeaver": f'<rect x="64" y="66" width="128" height="34" rx="17" fill="{C}"/>'
               f'<rect x="64" y="112" width="128" height="34" rx="17" fill="{M}"/>'
               f'<rect x="64" y="158" width="128" height="34" rx="17" fill="{M}"/>',
    "pgadmin": f'<rect x="54" y="74" width="96" height="108" fill="{C}"/>'
               f'<ellipse cx="102.0" cy="182" rx="48.0" ry="20" fill="{C}"/>'
               f'<path d="M54,110 Q102.0,138 150,110" fill="none" stroke="{BG}" stroke-width="6"/>'
               f'<path d="M54,146 Q102.0,174 150,146" fill="none" stroke="{BG}" stroke-width="6"/>'
               f'<ellipse cx="102.0" cy="74" rx="48.0" ry="20" fill="{M}"/>'
               f'<circle cx="166" cy="150" r="28" fill="none" stroke="{O}" stroke-width="14"/>'
               f'<rect x="186" y="168" width="16" height="40" rx="6" fill="{O}" transform="rotate(-45 194 188)"/>',
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
    "telegram": f'<polygon points="96,120 206,70 176,186" fill="{C}"/>'
                f'<polygon points="140,140 176,186 206,70" fill="{M}"/>'
                f'<rect x="48" y="104" width="36" height="10" rx="5" fill="{O}"/>'
                f'<rect x="58" y="128" width="26" height="10" rx="5" fill="{O}"/>'
                f'<rect x="48" y="152" width="36" height="10" rx="5" fill="{O}"/>',
    "zoom": f'<rect x="50" y="86" width="108" height="84" rx="16" fill="{C}"/>'
            f'<polygon points="166,128 206,94 206,162" fill="{O}"/>',
    "firefox": f'<circle cx="128" cy="128" r="72" fill="{O}"/>'
               f'<circle cx="150" cy="114" r="60" fill="{R}"/>',
    "chrome": f'<circle cx="128" cy="128" r="72" fill="{O}"/><circle cx="128" cy="128" r="42" fill="{BG}"/>'
              f'<circle cx="128" cy="128" r="22" fill="{C}"/>',
    "files": f'<rect x="56" y="70" width="64" height="32" rx="8" fill="{O}"/>'
             f'<rect x="56" y="88" width="144" height="100" rx="12" fill="{O}"/>'
             f'<rect x="56" y="112" width="144" height="10" fill="{BG}" fill-opacity=".25"/>',
    "settings": "".join(f'<rect x="114" y="50" width="28" height="156" rx="6" fill="{M}" transform="rotate({a} 128 128)"/>'
                        for a in (0, 45, 90, 135))
                + f'<circle cx="128" cy="128" r="54" fill="{M}"/><circle cx="128" cy="128" r="26" fill="{BG}"/>'
                  f'<circle cx="128" cy="128" r="11" fill="{C}"/>',
    "obsidian": f'<polygon points="140,46 186,120 150,208 84,170 96,90" fill="{C}"/>'
                f'<polygon points="140,46 186,120 150,208 122,128" fill="{M}"/>'
                f'<polygon points="72,58 84,70 72,82 60,70" fill="{O}"/>',
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
    "thunderbird": f'<circle cx="150" cy="102" r="52" fill="{C}"/>'
                   f'<rect x="52" y="108" width="136" height="92" rx="10" fill="{L}"/>'
                   f'<polyline points="56,114 120,160 184,114" fill="none" stroke="{M}" stroke-width="10" '
                   f'stroke-linejoin="round" stroke-linecap="round"/>'
                   f'<circle cx="172" cy="84" r="10" fill="{O}"/>',
    "inkscape": f'<line x1="62" y1="180" x2="96" y2="70" stroke="{M}" stroke-width="6"/>'
                f'<line x1="194" y1="76" x2="160" y2="186" stroke="{M}" stroke-width="6"/>'
                f'<path d="M62,180 C96,70 160,186 194,76" fill="none" stroke="{L}" stroke-width="12"/>'
                f'<circle cx="96" cy="70" r="10" fill="{M}"/><circle cx="160" cy="186" r="10" fill="{M}"/>'
                f'<rect x="50" y="168" width="24" height="24" fill="{C}"/>'
                f'<rect x="182" y="64" width="24" height="24" fill="{O}"/>',
    "blender": f'<polygon points="50,74 124,100 98,134" fill="{O}"/>'
               f'<circle cx="144" cy="138" r="50" fill="none" stroke="{O}" stroke-width="20"/>'
               f'<circle cx="144" cy="138" r="20" fill="{C}"/>',
    "toshy": f'<rect x="96" y="96" width="64" height="64" fill="none" stroke="{C}" stroke-width="14"/>'
             + "".join(f'<circle cx="{x}" cy="{y}" r="22" fill="none" stroke="{c}" stroke-width="14"/>'
                       for x, y, c in ((74, 74, O), (182, 74, C), (74, 182, C), (182, 182, C))),
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
    "input": f'<rect x="46" y="76" width="164" height="104" rx="14" fill="{M}"/>'
             + "".join(f'<rect x="{62 + 24 * i + (12 if r == 1 else 0)}" y="{92 + 24 * r}" width="16" height="16" rx="3" '
                       f'fill="{O if (r, i) == (0, 5) else L}"/>' for r in (0, 1) for i in range(6 if r == 0 else 5))
             + f'<rect x="86" y="148" width="84" height="16" rx="3" fill="{L}"/>',
    # — macOS-only apps —
    "docker": f'<path d="M50,138 H206 Q200,198 122,198 Q64,198 50,138 Z" fill="{C}"/>'
              + "".join(f'<rect x="{x}" y="{y}" width="28" height="28" rx="4" fill="{c}"/>'
                        for x, y, c in ((66, 104, M), (98, 104, M), (130, 104, M), (98, 72, M), (130, 72, O))),
    "github": f'<rect x="88" y="70" width="16" height="116" fill="{M}"/>'
              f'<path d="M168,90 Q168,150 104,150" fill="none" stroke="{M}" stroke-width="16"/>'
              f'<circle cx="96" cy="70" r="20" fill="{R}"/><circle cx="96" cy="186" r="20" fill="{R}"/>'
              f'<circle cx="168" cy="90" r="20" fill="{O}"/>',
    "whatsapp": f'<circle cx="132" cy="122" r="68" fill="{O}"/>'
                f'<polygon points="64,206 80,146 122,184" fill="{O}"/>'
                f'<path d="M108,94 Q102,146 156,154" fill="none" stroke="{C}" stroke-width="18" stroke-linecap="round"/>',
    "outlook": f'<circle cx="128" cy="128" r="70" fill="none" stroke="{C}" stroke-width="20"/>'
               f'<rect x="92" y="104" width="72" height="50" rx="6" fill="{O}"/>'
               f'<polyline points="94,108 128,134 162,108" fill="none" stroke="{BG}" stroke-width="7" stroke-linejoin="round"/>',
    "onedrive": f'<circle cx="168" cy="90" r="24" fill="{O}"/>' + cloud(M, -18, -16, .78) + cloud(C, 14, 18, .86),
    "deepl": f'<circle cx="128" cy="120" r="70" fill="{O}"/><polygon points="78,166 64,210 112,184" fill="{O}"/>'
             f'<rect x="92" y="98" width="58" height="12" fill="{C}"/>'
             f'<polygon points="148,88 172,104 148,120" fill="{C}"/>'
             f'<rect x="106" y="132" width="58" height="12" fill="{M}"/>'
             f'<polygon points="108,122 84,138 108,154" fill="{M}"/>',
    "comet": "".join(f'<line x1="{a}" y1="{b}" x2="{c}" y2="{d}" stroke="{C}" stroke-width="{w}" stroke-linecap="round"/>'
                     for a, b, c, d, w in ((140, 116, 64, 192, 18), (128, 90, 78, 140, 12), (166, 128, 116, 178, 12)))
             + f'<circle cx="162" cy="94" r="32" fill="{O}"/>',
    "mkplayer": f'<circle cx="128" cy="128" r="70" fill="{R}"/>'
                f'<polygon points="110,92 168,128 110,164" fill="{BG}"/>',
    "omniplayer": f'<rect x="50" y="68" width="156" height="106" rx="14" fill="{O}"/>'
                  f'<rect x="102" y="182" width="52" height="14" rx="5" fill="{M}"/>'
                  f'<polygon points="112,96 154,121 112,146" fill="{C}"/>',
    "pokerstars": f'<g transform="rotate(-10 128 128)"><rect x="70" y="50" width="116" height="156" rx="14" fill="{L}"/>'
                  f'<path d="M128,92 C139,106 163,119 163,138 C163,154 144,159 133,148 L140,170 H116 L123,148 '
                  f'C112,159 93,154 93,138 C93,119 117,106 128,92 Z" fill="{R}"/>'
                  f'<polygon points="160,64 163.5,73.1 173.3,73.7 165.7,79.9 168.2,89.3 160,84 151.8,89.3 154.3,79.9 '
                  f'146.7,73.7 156.5,73.1" fill="{O}"/></g>',
    "unarchiver": f'<rect x="56" y="126" width="144" height="78" rx="10" fill="{O}"/>'
                  f'<rect x="56" y="126" width="144" height="16" fill="{M}"/>'
                  f'<rect x="118" y="78" width="20" height="56" fill="{C}"/><polygon points="94,88 162,88 128,50" fill="{C}"/>',
    "ilovepdf": f'<polygon points="66,52 158,52 190,84 190,204 66,204" fill="{L}"/>'
                f'<polygon points="158,52 190,84 158,84" fill="{M}"/>'
                f'<circle cx="110" cy="126" r="22" fill="{R}"/><circle cx="146" cy="126" r="22" fill="{R}"/>'
                f'<polygon points="89,134 167,134 128,178" fill="{R}"/>',
    "mcafee": f'<path d="M128,54 L190,78 L190,130 Q190,180 128,206 Q66,180 66,130 L66,78 Z" fill="{R}"/>'
              f'<polygon points="92,158 92,98 128,130 164,98 164,158 146,158 146,136 128,152 110,136 110,158" fill="{BG}"/>',
    "idle": f'<rect x="62" y="62" width="84" height="84" rx="20" fill="{C}"/>'
            f'<rect x="110" y="110" width="84" height="84" rx="20" fill="{O}"/>'
            f'<circle cx="86" cy="86" r="9" fill="{L}"/><circle cx="170" cy="170" r="9" fill="{BG}"/>',
    "pylauncher": f'<rect x="54" y="72" width="112" height="112" rx="22" fill="{C}"/>'
                  f'<circle cx="84" cy="102" r="10" fill="{L}"/>'
                  f'<polygon points="150,92 206,128 150,164" fill="{O}"/>',
    "maps": f'<rect x="58" y="58" width="140" height="140" rx="12" fill="{L}"/>'
            f'<line x1="58" y1="106" x2="198" y2="106" stroke="{C}" stroke-width="12"/>'
            f'<line x1="106" y1="58" x2="106" y2="198" stroke="{C}" stroke-width="12"/>'
            f'<line x1="58" y1="190" x2="198" y2="96" stroke="{M}" stroke-width="8"/>'
            f'<circle cx="158" cy="130" r="20" fill="{O}"/><polygon points="141,140 175,140 158,168" fill="{O}"/>'
            f'<circle cx="158" cy="130" r="8" fill="{L}"/>',
    "safari": f'<circle cx="128" cy="128" r="72" fill="{R}"/>'
              f'<g transform="rotate(45 128 128)"><polygon points="128,64 146,128 110,128" fill="{C}"/>'
              f'<polygon points="128,192 146,128 110,128" fill="{M}"/></g>'
              f'<circle cx="128" cy="128" r="10" fill="{BG}"/>',
    "launchpad": "".join(f'<circle cx="{76 + 52 * (i % 3)}" cy="{76 + 52 * (i // 3)}" r="20" '
                         f'fill="{ {4: C, 8: R}.get(i, O) }"/>' for i in range(9)),
    "photos": f'<rect x="70" y="58" width="116" height="96" rx="8" fill="{M}" transform="rotate(-10 128 106)"/>'
              f'<rect x="64" y="88" width="128" height="104" rx="8" fill="{L}"/>'
              f'<polygon points="80,182 122,128 164,182" fill="{C}"/><circle cx="160" cy="114" r="12" fill="{R}"/>',
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
    "inkscape_inkscape": "inkscape", "thunderbird_thunderbird": "thunderbird", "thunderbird": "thunderbird",
    "desktop-security-center_desktop-security-center": "security", "display-im7.q16": "imagemagick",
    "firmware-updater_firmware-updater": "firmware", "gnome-language-selector": "language",
    "info": "texinfo", "net.nokyan.Resources": "resources", "nm-connection-editor": "network",
    "nvidia-settings": "nvidia", "org.gnome.baobab": "disk-usage", "org.gnome.Calculator": "calculator",
    "org.gnome.Characters": "characters", "org.gnome.clocks": "clocks", "org.gnome.DiskUtility": "disks",
    "org.gnome.font-viewer": "fonts", "org.gnome.Logs": "logs", "org.gnome.Loupe": "images",
    "org.gnome.Papers": "papers", "org.gnome.seahorse.Application": "passwords",
    "org.gnome.Sysprof": "sysprof", "org.gnome.TextEditor": "text-editor", "org.gnome.Yelp": "help",
    "snap-store_snap-store": "app-center", "update-manager": "updater", "vim": "vim",
    "virtualbox": "virtualbox", "im-config": "input", "org.freedesktop.IBus.Setup": "input",
    "blender_blender": "blender", "app.toshy.preferences": "toshy", "Toshy_Tray": "toshy",
}

# desktop file ID → the window class/app_id the app really reports (measured 2026-10-24). Without it GNOME
# can't tie the running window to the launcher and shows a second, stock-icon entry in the dock.
WMCLASS = {"virtualbox": "VirtualBox Manager", "balena-etcher": "balenaEtcher", "chatgpt": "Chatgpt",
           "inkscape_inkscape": "org.inkscape.Inkscape"}

HOME = Path.home()
ICON_DIR = HOME / ".local/share/icons/bauhaus"
LABEL_DIR = HOME / ".local/share/icons/bauhaus-labels"
LOCAL_APPS = HOME / ".local/share/applications"
SYSTEM_APPS = [Path("/var/lib/snapd/desktop/applications"), Path("/usr/share/applications")]
MARK = "X-Bauhaus-Icon=true"


LABELS = {"vscode": "vs code", "disk-usage": "disk usage", "text-editor": "text editor",
          "app-center": "app center", "imagemagick": "magick"}                      # display name when it differs from the key
FONT = "Jost, Futura, 'Ubuntu Sans', sans-serif"     # Jost = open Futura revival (Google Fonts)


INK = {C: L, R: L, O: BG}       # the gray drawn on each colored tile (charcoal on ochre for contrast)
SWAP = {C: {C: L, L: BG}, R: {R: L, L: BG}, O: {O: BG, BG: L, L: BG}}   # per tile: keep every shape visible
TILE = {**dict.fromkeys(["input", "warp", "vscode", "cursor", "antigravity", "dbeaver", "pgadmin", "elasticvue", "telegram",
                         "zoom", "obsidian", "nordvpn", "dropbox", "network", "disks", "updater", "security",
                         "images", "text-editor", "docker", "outlook", "onedrive", "comet", "pylauncher", "maps",
                         "toshy"], C),
        **dict.fromkeys(["claude", "chatgpt", "files", "etcher", "spotify", "notion", "firmware", "imagemagick",
                         "nvidia", "fonts", "passwords", "papers", "app-center", "vim", "calculator", "characters",
                         "clocks", "texinfo", "whatsapp", "deepl", "omniplayer", "unarchiver", "idle", "launchpad", "photos",
                         "blender"], O)}
# everything else → burgundy (terminal, postman, slack, discord, firefox, chrome, settings, gephi, pritunl, …)


def tile_of(name, glyph):
    return TILE.get(name, R)


def colorize(glyph, tile):
    """Kandinsky swap: the tile's primary turns gray; other primaries stay as accents."""
    m = SWAP[tile]
    return re.sub("|".join(map(re.escape, m)), lambda x: m[x.group(0)], glyph)


def svg(glyph, label=None, name="", dark=False):
    tile, ink = (BG, L) if dark else (tile_of(name, glyph), None)
    if not dark:
        ink = INK[tile]
        glyph = colorize(glyph, tile)
    if label:   # glyph shrinks + lifts; name set small in the bottom band
        size = 30 if len(label) <= 8 else 26
        glyph = (f'<g transform="translate(128 106) scale(.74) translate(-128 -128)">{glyph}</g>'
                 f'<text x="128" y="218" text-anchor="middle" font-family="{FONT}" font-weight="500" '
                 f'font-size="{size}" letter-spacing="1" fill="{ink}">{label}</text>')
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">'
            f'<rect x="8" y="8" width="240" height="240" rx="52" fill="{tile}"/>{glyph}</svg>\n')


def set_icon(text, icon, wmclass=None):
    text = re.sub(r"^Icon=.*$", f"Icon={icon}", text, flags=re.M)
    if MARK not in text:
        text = text.replace("[Desktop Entry]\n", f"[Desktop Entry]\n{MARK}\n", 1)
    if wmclass:     # only in the [Desktop Entry] group, which ends at the first [Desktop Action …]
        head, sep, rest = text.partition("\n[Desktop Action")
        head = re.sub(r"^StartupWMClass=.*\n", "", head, flags=re.M)
        head = head.replace(f"{MARK}\n", f"{MARK}\nStartupWMClass={wmclass}\n", 1)
        text = head + sep + rest
    return text


def chrome_profiles():
    """(directory, name, email) per Chrome profile, Default first — read from Chrome's own Local State."""
    try:
        cache = json.loads((HOME / ".config/google-chrome/Local State").read_text())["profile"]["info_cache"]
    except (OSError, ValueError, KeyError):
        return []
    return sorted(((d, v.get("name", d), v.get("user_name", "")) for d, v in cache.items()), key=lambda t: t[0] != "Default")


def add_chrome_profiles(text):
    """Right-click (dock) entry per Chrome profile, like the macOS dock menu. Re-read on every run."""
    profiles = chrome_profiles()
    if not profiles:
        return text
    exe = re.search(r"^Exec=(\S+)", text, flags=re.M).group(1)
    ids = [f"profile-{re.sub(r'[^a-z0-9]+', '-', d.lower())}" for d, _, _ in profiles]
    head, sep, rest = text.partition("\n[Desktop Action")
    old = re.search(r"^Actions=(.*)$", head, flags=re.M)
    keep = [a for a in (old.group(1).split(";") if old else []) if a and not a.startswith("profile-")]
    line = "Actions=" + ";".join(ids + keep) + ";"
    head = re.sub(r"^Actions=.*$", line, head, flags=re.M) if old else head.rstrip("\n") + "\n" + line + "\n"
    rest = re.sub(r"\n\[Desktop Action profile-[^\]]*\][^\[]*", "\n", sep + rest)
    actions = "".join(f"\n[Desktop Action {i}]\nName={n}" + (f" ({e})" if e else "") +
                      f"\nExec={exe} \"--profile-directory={d}\"\n" for i, (d, n, e) in zip(ids, profiles))
    return head.rstrip("\n") + "\n" + actions + rest


def write_svgs():
    for d in (ICON_DIR, LABEL_DIR):
        d.mkdir(parents=True, exist_ok=True)
    for name, glyph in ICONS.items():
        dark = "--dark" in sys.argv
        (ICON_DIR / f"{name}.svg").write_text(svg(glyph, name=name, dark=dark))
        (LABEL_DIR / f"{name}.svg").write_text(svg(glyph, LABELS.get(name, name), name=name, dark=dark))


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
        text = set_icon(src.read_text(), icon_dir / f"{name}.svg", WMCLASS.get(app))
        local.write_text(add_chrome_profiles(text) if app == "google-chrome" else text)
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


MAC_APPS = {"Warp": "warp", "Visual Studio Code": "vscode", "Cursor": "cursor", "Antigravity IDE": "antigravity",
            "Claude": "claude", "ChatGPT": "chatgpt", "DBeaver": "dbeaver", "pgAdmin 4": "pgadmin",
            "elasticvue": "elasticvue", "Postman": "postman", "Postman Agent": "postman", "Slack": "slack",
            "Discord": "discord", "Telegram": "telegram", "zoom.us": "zoom", "Firefox": "firefox",
            "Google Chrome": "chrome", "Obsidian": "obsidian", "Notion": "notion", "Gephi": "gephi",
            "balenaEtcher": "etcher", "Spotify": "spotify", "Dropbox": "dropbox", "NordVPN": "nordvpn",
            "Pritunl": "pritunl", "Inkscape": "inkscape", "VirtualBox": "virtualbox", "Blender": "blender",
            "GitHub Desktop": "github", "WhatsApp": "whatsapp", "Microsoft Outlook": "outlook",
            "OneDrive": "onedrive", "DeepL": "deepl", "Comet": "comet", "MKPlayer": "mkplayer",
            "OmniPlayerStore": "omniplayer", "PokerStarsDE": "pokerstars", "The Unarchiver": "unarchiver",
            "iLovePDF": "ilovepdf", "McAfee LiveSafe - Internet Security": "mcafee",
            "Python 3.7/IDLE": "idle", "Python 3.7/Python Launcher": "pylauncher"}
CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
JXA_SET = "ObjC.import('AppKit');function run(a){var i=a[0]?$.NSImage.alloc.initWithContentsOfFile(a[0]):$();" \
          "return $.NSWorkspace.sharedWorkspace.setIconForFileOptions(i,a[1],0)}"


# A custom icon writes Icon\r + FinderInfo into the bundle, which breaks its code signature
# ("resource fork, Finder information, or similar detritus not allowed"). Most apps still launch;
# apps whose privileged helpers verify the bundle do not (Docker Desktop's vmnetd: the engine never
# starts). These keep their stock icon and get a Bauhaus launcher instead, like Apple's apps below.
MAC_LAUNCH_ONLY = {"/Applications/Docker.app": "docker"}

# Apple's own apps sit on the sealed system volume (no custom icons without disabling SIP), so they
# get look-alike launchers in ~/Applications/Bauhaus that open the real app; --mac-dock swaps them
# into the Dock. While the real app runs, the Dock also shows its stock icon next to the launcher.
MAC_SYSTEM = {"/System/Applications/Utilities/Terminal.app": "terminal", "/Applications/Safari.app": "safari",
              "/System/Applications/System Preferences.app": "settings", "/System/Applications/App Store.app": "app-center",
              "/System/Applications/TextEdit.app": "text-editor", "/System/Applications/Photos.app": "photos",
              "/System/Applications/Maps.app": "maps", "/System/Applications/Launchpad.app": "launchpad"}
MAC_OUT = HOME / ".local/share/icons/bauhaus-mac"
LAUNCHERS = HOME / "Applications/Bauhaus"
DOCK_BACKUP = MAC_OUT / "dock-backup.plist"


def mac_png(name):
    svg_path, png = MAC_OUT / f"{name}.svg", MAC_OUT / f"{name}.png"
    svg_path.write_text(svg(ICONS[name], name=name).replace(
        'viewBox="0 0 256 256"', 'width="1024" height="1024" viewBox="-21 -21 298 298"'))
    subprocess.run([CHROME, "--headless", "--disable-gpu", "--hide-scrollbars",
                    "--default-background-color=00000000", "--window-size=1024,1024",
                    f"--screenshot={png}", svg_path.as_uri()], capture_output=True, check=True)
    return png


def mac_set_icon(png, path):
    cmd = ["osascript", "-l", "JavaScript", "-e", JXA_SET, str(png), str(path)]
    ok = subprocess.run(cmd, capture_output=True, text=True).stdout.strip() == "true"
    if not ok and sys.stdin.isatty():       # root-owned bundles (pkg installs): one sudo prompt
        ok = subprocess.run(["sudo", *cmd], capture_output=True, text=True).stdout.strip() == "true"
    return ok


def mac_launcher(target, png):
    stem = Path(target).stem
    app = LAUNCHERS / f"{stem} Bauhaus.app"   # distinct name: `tell application "Terminal"` must not hit it
    (app / "Contents/MacOS").mkdir(parents=True, exist_ok=True)
    exe = app / "Contents/MacOS/launch"
    exe.write_text(f'#!/bin/sh\nexec open -a "{target}"\n')
    exe.chmod(0o755)
    plistlib.dump({"CFBundleExecutable": "launch", "CFBundleName": f"{stem} Bauhaus", "CFBundlePackageType": "APPL",
                   "CFBundleIdentifier": "dev.garassino.bauhaus." + re.sub(r"\W", "", stem).lower(),
                   "LSUIElement": True}, (app / "Contents/Info.plist").open("wb"))
    mac_set_icon(png, app)
    return app


def refresh_dock():
    """killall Dock alone keeps stale icons — drop its icon cache first."""
    cache = subprocess.run(["getconf", "DARWIN_USER_CACHE_DIR"], capture_output=True, text=True).stdout.strip()
    Path(cache, "com.apple.dock.iconcache").unlink(missing_ok=True)
    subprocess.run(["killall", "Dock"], check=False)


def mac(undo=False):
    """macOS: custom Finder/Dock icon per app (Icon\\r in the bundle; this invalidates the bundle
    signature, harmless for most apps) + launchers for Apple's apps and MAC_LAUNCH_ONLY apps.
    Rendered by headless Chrome at Big Sur grid size (tile = 824/1024).
    An app update resets its icon — re-run."""
    MAC_OUT.mkdir(parents=True, exist_ok=True)
    for app, name in MAC_APPS.items():
        path = Path(f"/Applications/{app}.app")
        if not path.exists():
            continue
        ok = mac_set_icon("" if undo else mac_png(name), path)
        print(f"  {'↩️ ' if undo else '🎨'} {app}" if ok else f"  ⚠️  {app}: root-owned — run this in a terminal (one sudo prompt)")
    for target in MAC_LAUNCH_ONLY:            # always restore the stock icon so the signature is valid
        if Path(target).exists() and Path(target, "Icon\r").exists():
            mac_set_icon("", target)
            print(f"  🔏 {Path(target).stem}: stock icon kept (signature-sensitive)")
    if undo:
        subprocess.run(["rm", "-rf", str(LAUNCHERS)], check=False)
    else:
        for target, name in {**MAC_SYSTEM, **MAC_LAUNCH_ONLY}.items():
            if Path(target).exists():
                print(f"  🚀 {mac_launcher(target, mac_png(name)).name}")
    refresh_dock()


def mac_dock(undo=False):
    """Swap Dock tiles of Apple apps for their Bauhaus launchers (backup first; --undo restores it)."""
    if undo:
        subprocess.run(["defaults", "import", "com.apple.dock", str(DOCK_BACKUP)], check=True)
    else:
        raw = subprocess.run(["defaults", "export", "com.apple.dock", "-"], capture_output=True, check=True).stdout
        if not DOCK_BACKUP.exists():
            DOCK_BACKUP.write_bytes(raw)
        dock = plistlib.loads(raw)
        for tile in dock.get("persistent-apps", []):
            data = tile.get("tile-data", {})
            path = unquote(data.get("file-data", {}).get("_CFURLString", "")).removeprefix("file://").rstrip("/")
            launcher = LAUNCHERS / f"{Path(path).stem} Bauhaus.app"
            if (path in MAC_SYSTEM or path in MAC_LAUNCH_ONLY) and launcher.exists():
                data["file-data"] = {"_CFURLString": launcher.as_uri() + "/", "_CFURLStringType": 15}
                data["file-label"] = Path(path).stem
                data["bundle-identifier"] = plistlib.load((launcher / "Contents/Info.plist").open("rb"))["CFBundleIdentifier"]
                data.pop("book", None)
                print(f"  🔁 {Path(path).stem}")
        subprocess.run(["defaults", "import", "com.apple.dock", "-"], input=plistlib.dumps(dock), check=True)
    refresh_dock()


def mac_heal():
    """Re-set icons that an app update wiped (cached PNGs, no render). Run by the --mac-watch agent."""
    healed = [app for app, name in MAC_APPS.items()
              if Path(f"/Applications/{app}.app").exists() and not Path(f"/Applications/{app}.app/Icon\r").exists()
              and (MAC_OUT / f"{name}.png").exists()
              and mac_set_icon(MAC_OUT / f"{name}.png", f"/Applications/{app}.app")]
    if healed:
        print("healed:", ", ".join(healed))
        refresh_dock()


WATCH_AGENT = HOME / "Library/LaunchAgents/dev.garassino.bauhaus-heal.plist"


def mac_watch(undo=False):
    """LaunchAgent: run --mac-heal whenever /Applications changes (app updates) and hourly."""
    subprocess.run(["launchctl", "unload", str(WATCH_AGENT)], capture_output=True)
    if undo:
        WATCH_AGENT.unlink(missing_ok=True)
        return
    WATCH_AGENT.parent.mkdir(parents=True, exist_ok=True)
    plistlib.dump({"Label": WATCH_AGENT.stem, "ProgramArguments": ["/usr/bin/python3", str(Path(__file__).resolve()), "--mac-heal"],
                   "WatchPaths": ["/Applications"], "StartInterval": 3600, "RunAtLoad": True, "ThrottleInterval": 30,
                   "StandardOutPath": str(MAC_OUT / "heal.log"), "StandardErrorPath": str(MAC_OUT / "heal.log")},
                  WATCH_AGENT.open("wb"))
    subprocess.run(["launchctl", "load", str(WATCH_AGENT)], check=True)
    print(f"  👀 {WATCH_AGENT.name} loaded")


if __name__ == "__main__":
    if "--mac-heal" in sys.argv:
        mac_heal()
    elif "--mac-watch" in sys.argv:
        mac_watch(undo="--undo" in sys.argv)
    elif "--mac-dock" in sys.argv:
        mac_dock(undo="--undo" in sys.argv)
    elif "--mac" in sys.argv:
        mac(undo="--undo" in sys.argv)
    elif "--undo" in sys.argv:
        undo()
    elif "--preview" in sys.argv:
        i = sys.argv.index("--preview")
        preview(sys.argv[i + 1] if len(sys.argv) > i + 1 else "/tmp/bauhaus-icons.png")
    else:
        apply(LABEL_DIR if "--labels" in sys.argv else ICON_DIR)
