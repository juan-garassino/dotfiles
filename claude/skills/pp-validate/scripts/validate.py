#!/usr/bin/env python3
"""
pp-validate: GCode validator for pen plotter.
Checks syntax, bounds, Z safety, feed rates, and structure.
"""

import argparse
import re
import sys
from dataclasses import dataclass, field
from typing import Optional


@dataclass
class ValidationResult:
    warnings: list = field(default_factory=list)
    errors: list = field(default_factory=list)
    info: dict = field(default_factory=dict)

    @property
    def ok(self):
        return len(self.errors) == 0

    @property
    def clean(self):
        return len(self.errors) == 0 and len(self.warnings) == 0


def parse_coord(line: str, axis: str) -> Optional[float]:
    m = re.search(rf"{axis}(-?\d+\.?\d*)", line, re.IGNORECASE)
    return float(m.group(1)) if m else None


def validate(filepath: str, x_max=297, y_max=420, z_safe=5, max_feed=8000) -> ValidationResult:
    result = ValidationResult()

    with open(filepath, "r") as f:
        raw_lines = f.readlines()

    lines = [l.strip() for l in raw_lines]
    code_lines = [l for l in lines if l and not l.startswith(";")]

    result.info["total_lines"] = len(lines)
    result.info["code_lines"] = len(code_lines)

    if not code_lines:
        result.errors.append("File is empty — no GCode commands found")
        return result

    # Track state
    current_z = None
    pen_down = False
    move_count = 0
    x_vals, y_vals = [], []
    units = "mm"  # default
    has_home = False
    has_end_lift = False

    for i, line in enumerate(lines, 1):
        line_upper = line.upper().split(";")[0].strip()  # strip inline comments
        if not line_upper:
            continue

        # Units
        if "G20" in line_upper:
            units = "inches"
        if "G21" in line_upper:
            units = "mm"

        # Home detection
        if "G28" in line_upper or "G0 X0 Y0" in line_upper:
            has_home = True

        # Z moves
        z = parse_coord(line_upper, "Z")
        if z is not None:
            current_z = z
            pen_down = z < z_safe
            if z >= z_safe:
                has_end_lift = True

        # XY moves
        if re.match(r"G[01]", line_upper):
            move_count += 1
            x = parse_coord(line_upper, "X")
            y = parse_coord(line_upper, "Y")

            if x is not None:
                x_vals.append(x)
                if x < 0 or x > x_max:
                    result.errors.append(
                        f"Line {i}: X{x} out of bounds (0-{x_max}mm): {line}"
                    )

            if y is not None:
                y_vals.append(y)
                if y < 0 or y > y_max:
                    result.errors.append(
                        f"Line {i}: Y{y} out of bounds (0-{y_max}mm): {line}"
                    )

        # Feed rate check
        f_val = parse_coord(line_upper, "F")
        if f_val is not None and f_val > max_feed:
            result.warnings.append(
                f"Line {i}: Feed rate F{f_val} exceeds max {max_feed}: {line}"
            )

        # Syntax: G/M code format
        if line_upper and not re.match(r"^[GMTSFXYZIJKPQREHNOabcdefghijklmnopqrstuvwxyz%;(]", line_upper):
            result.warnings.append(f"Line {i}: Possibly malformed command: {line}")

    result.info["move_count"] = move_count
    result.info["x_range"] = (min(x_vals), max(x_vals)) if x_vals else (0, 0)
    result.info["y_range"] = (min(y_vals), max(y_vals)) if y_vals else (0, 0)
    result.info["units"] = units
    result.info["has_home"] = has_home
    result.info["has_end_lift"] = has_end_lift

    if not has_end_lift:
        result.warnings.append("No pen lift (Z raise) found at end of file — plotter may drag pen home")

    if units == "inches":
        result.warnings.append("File uses inches (G20) — confirm your machine is configured for inches")

    return result


def print_report(filepath: str, result: ValidationResult):
    info = result.info
    print(f"\npp-validate — GCode Validation Report")
    print("━" * 45)
    print(f"File:     {filepath}")
    print(f"Lines:    {info.get('total_lines', '?')}")
    print(f"Moves:    {info.get('move_count', '?')}")
    print(f"Units:    {info.get('units', '?')}")
    x_r = info.get('x_range', (0, 0))
    y_r = info.get('y_range', (0, 0))
    print(f"X range:  {x_r[0]:.1f} – {x_r[1]:.1f} mm")
    print(f"Y range:  {y_r[0]:.1f} – {y_r[1]:.1f} mm")
    print()

    def status(items, label):
        icon = "✅" if not items else ("❌" if any("error" in str(e).lower() for e in items) else "⚠️ ")
        print(f"{icon}  {label}")
        for item in items:
            print(f"     → {item}")

    print(f"{'✅' if not result.errors else '❌'}  Bounds / Syntax")
    for e in result.errors:
        print(f"     → {e}")
    print(f"{'✅' if not result.warnings else '⚠️ '}  Warnings")
    for w in result.warnings:
        print(f"     → {w}")

    print()
    if result.errors:
        print("Result: ❌ ERRORS — do not run until fixed")
    elif result.warnings:
        print("Result: ⚠️  WARNINGS — review before running")
    else:
        print("Result: ✅ CLEAN — safe to stream")
    print()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate GCode for pen plotter")
    parser.add_argument("file", help="GCode file to validate")
    parser.add_argument("--x-max", type=float, default=297)
    parser.add_argument("--y-max", type=float, default=420)
    parser.add_argument("--z-safe", type=float, default=5)
    parser.add_argument("--max-feed", type=float, default=8000)
    args = parser.parse_args()

    result = validate(args.file, args.x_max, args.y_max, args.z_safe, args.max_feed)
    print_report(args.file, result)

    if result.errors:
        sys.exit(2)
    elif result.warnings:
        sys.exit(1)
    else:
        sys.exit(0)
