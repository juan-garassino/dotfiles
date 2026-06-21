#!/usr/bin/env python3
"""Detect available serial ports and suggest the most likely plotter port."""

try:
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    exit(1)

ports = list(serial.tools.list_ports.comports())

if not ports:
    print("No serial ports detected.")
    exit(0)

print("Available serial ports:\n")
likely = []
for p in ports:
    marker = ""
    desc = (p.description or "").lower()
    if any(x in desc for x in ["usb", "uart", "ch340", "cp210", "ftdi", "arduino", "grbl"]):
        marker = "  ← likely plotter"
        likely.append(p.device)
    print(f"  {p.device:<25} {p.description}{marker}")

if likely:
    print(f"\nSuggested port: {likely[0]}")
