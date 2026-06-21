#!/usr/bin/env python3
"""
pp-simulate: GCode simulator and toolpath visualizer for pen plotter.
Renders toolpath as SVG and produces stats without connecting to hardware.
"""

import argparse
import math
import re
import sys
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class Move:
    x: float
    y: float
    z: float
    feed: float
    is_draw: bool  # True = pen down, False = travel


def parse_gcode(filepath: str, z_threshold: float = 2.0) -> list[Move]:
    moves = []
    cx, cy, cz, cf = 0.0, 0.0, 10.0, 1000.0

    with open(filepath) as f:
        for line in f:
            line = line.split(";")[0].strip().upper()
            if not line:
                continue

            def get(axis):
                m = re.search(rf"{axis}(-?\d+\.?\d*)", line)
                return float(m.group(1)) if m else None

            if re.match(r"G[01]", line):
                x = get("X") or cx
                y = get("Y") or cy
                z = get("Z") or cz
                f_val = get("F") or cf

                if x != cx or y != cy:
                    moves.append(Move(x, y, z, f_val, is_draw=(z <= z_threshold)))

                cx, cy, cz, cf = x, y, z, f_val
            elif "Z" in line:
                z = get("Z")
                if z is not None:
                    cz = z

    return moves


def compute_stats(moves: list[Move]) -> dict:
    draw_dist = travel_dist = 0.0
    pen_lifts = 0
    prev_draw = None

    for i, m in enumerate(moves):
        if i == 0:
            prev_draw = m
            continue
        prev = moves[i - 1]
        d = math.sqrt((m.x - prev.x) ** 2 + (m.y - prev.y) ** 2)
        if m.is_draw:
            draw_dist += d
        else:
            travel_dist += d
        if m.is_draw and not prev.is_draw:
            pen_lifts += 1
        prev_draw = m

    total_dist = draw_dist + travel_dist
    efficiency = (draw_dist / total_dist * 100) if total_dist > 0 else 0

    avg_feed = sum(m.feed for m in moves if m.is_draw) / max(1, sum(1 for m in moves if m.is_draw))
    est_seconds = (total_dist / avg_feed * 60) if avg_feed > 0 else 0

    return {
        "total_moves": len(moves),
        "draw_moves": sum(1 for m in moves if m.is_draw),
        "travel_moves": sum(1 for m in moves if not m.is_draw),
        "pen_lifts": pen_lifts,
        "draw_dist": draw_dist,
        "travel_dist": travel_dist,
        "efficiency": efficiency,
        "est_seconds": est_seconds,
    }


def render_svg(moves: list[Move], output_path: str, margin: int = 20):
    if not moves:
        print("No moves to render")
        return

    xs = [m.x for m in moves]
    ys = [m.y for m in moves]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)
    w = max_x - min_x or 1
    h = max_y - min_y or 1

    scale = min(800 / w, 600 / h)
    svg_w = int(w * scale + margin * 2)
    svg_h = int(h * scale + margin * 2)

    def tx(x): return (x - min_x) * scale + margin
    def ty(y): return svg_h - ((y - min_y) * scale + margin)

    lines = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{svg_w}" height="{svg_h}" style="background:#fff">']
    lines.append(f'<rect width="100%" height="100%" fill="#fafafa"/>')

    prev = moves[0]
    for m in moves[1:]:
        x1, y1 = tx(prev.x), ty(prev.y)
        x2, y2 = tx(m.x), ty(m.y)
        if m.is_draw:
            lines.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#1a1aff" stroke-width="1" opacity="0.8"/>')
        else:
            lines.append(f'<line x1="{x1:.1f}" y1="{y1:.1f}" x2="{x2:.1f}" y2="{y2:.1f}" stroke="#ff4444" stroke-width="0.5" stroke-dasharray="3,3" opacity="0.5"/>')
        prev = m

    # Start/end markers
    sx, sy = tx(moves[0].x), ty(moves[0].y)
    ex, ey = tx(moves[-1].x), ty(moves[-1].y)
    lines.append(f'<circle cx="{sx}" cy="{sy}" r="5" fill="#00cc44" opacity="0.9"/>')
    lines.append(f'<circle cx="{ex}" cy="{ey}" r="5" fill="#ff4444" opacity="0.9"/>')
    lines.append("</svg>")

    with open(output_path, "w") as f:
        f.write("\n".join(lines))
    print(f"✅ SVG saved to: {output_path}")


def terminal_preview(moves: list[Move], cols: int = 80, rows: int = 40):
    if not moves:
        return
    xs = [m.x for m in moves]
    ys = [m.y for m in moves]
    min_x, max_x = min(xs), max(xs)
    min_y, max_y = min(ys), max(ys)

    grid = [[" "] * cols for _ in range(rows)]

    for m in moves:
        if m.is_draw:
            col = int((m.x - min_x) / (max_x - min_x + 0.001) * (cols - 1))
            row = rows - 1 - int((m.y - min_y) / (max_y - min_y + 0.001) * (rows - 1))
            grid[row][col] = "█"

    print("┌" + "─" * cols + "┐")
    for row in grid:
        print("│" + "".join(row) + "│")
    print("└" + "─" * cols + "┘")


def print_stats(filepath: str, stats: dict):
    s = stats
    mins = int(s["est_seconds"] // 60)
    secs = int(s["est_seconds"] % 60)
    efficiency = s["efficiency"]
    rec = ("✅ Good" if efficiency > 85
           else "⚠️  Acceptable" if efficiency > 60
           else "❌ Run pp-optimize before plotting")

    print(f"\npp-simulate — Toolpath Analysis")
    print("━" * 40)
    print(f"File:              {filepath}")
    print(f"Total moves:       {s['total_moves']}")
    print(f"Draw moves:        {s['draw_moves']}  (pen down)")
    print(f"Travel moves:      {s['travel_moves']}  (pen up)")
    print(f"Pen lifts:         {s['pen_lifts']}")
    print(f"Draw distance:     {s['draw_dist']:.0f} mm")
    print(f"Travel distance:   {s['travel_dist']:.0f} mm")
    print(f"Est. duration:     {mins}m {secs}s")
    print(f"Efficiency:        {efficiency:.0f}%  — {rec}")
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Simulate and preview GCode toolpath")
    parser.add_argument("file", help="GCode file")
    parser.add_argument("--output", help="Output SVG path", default=None)
    parser.add_argument("--terminal", action="store_true")
    parser.add_argument("--stats-only", action="store_true")
    parser.add_argument("--z-threshold", type=float, default=2.0)
    args = parser.parse_args()

    moves = parse_gcode(args.file, args.z_threshold)
    stats = compute_stats(moves)
    print_stats(args.file, stats)

    if not args.stats_only:
        if args.terminal:
            terminal_preview(moves)
        elif args.output:
            render_svg(moves, args.output)
        else:
            out = args.file.replace(".gcode", "_preview.svg").replace(".nc", "_preview.svg")
            render_svg(moves, out)
