#!/usr/bin/env python3
"""
pp-stream: Serial streaming script for pen plotter.
Streams GCode line by line, waits for 'ok' before next command.
"""

import argparse
import sys
import time

try:
    import serial
    import serial.tools.list_ports
except ImportError:
    print("ERROR: pyserial not installed. Run: pip install pyserial")
    sys.exit(1)


def stream_gcode(port: str, baud: int, filepath: str, dry_run: bool = False):
    with open(filepath, "r") as f:
        lines = [l.strip() for l in f.readlines() if l.strip() and not l.startswith(";")]

    total = len(lines)
    print(f"📄 Loaded {total} GCode lines from {filepath}")

    if dry_run:
        print("🔵 DRY RUN — not connecting to serial port")
        for i, line in enumerate(lines):
            print(f"[{i+1:5d} / {total}]  {line}  →  (simulated ok)")
            time.sleep(0.001)
        print("✅ Dry run complete")
        return

    print(f"🔌 Connecting to {port} at {baud} baud...")
    try:
        ser = serial.Serial(port, baud, timeout=5)
    except serial.SerialException as e:
        print(f"ERROR: Could not open port {port}: {e}")
        sys.exit(1)

    time.sleep(2)  # wait for firmware to boot
    ser.flushInput()
    print(f"✅ Connected\n")

    errors = 0
    start_time = time.time()

    try:
        for i, line in enumerate(lines):
            ser.write((line + "\n").encode())
            response = ""
            timeout_count = 0

            while "ok" not in response.lower() and "error" not in response.lower():
                raw = ser.readline().decode("utf-8", errors="replace").strip()
                if raw:
                    response = raw
                else:
                    timeout_count += 1
                    if timeout_count > 10:
                        print(f"\n⚠️  Timeout on line {i+1}: {line}")
                        print("Retrying once...")
                        ser.write((line + "\n").encode())
                        timeout_count = 0

            status = "✅ ok" if "ok" in response.lower() else f"❌ {response}"
            print(f"[{i+1:5d} / {total}]  {line:<40}  →  {status}")

            if "error" in response.lower() or "alarm" in response.lower():
                errors += 1
                print(f"\n🚨 Firmware error: {response}")
                if "alarm" in response.lower():
                    print("ALARM state — sending reset and aborting")
                    ser.write(b"\x18")  # Ctrl-X reset
                    break
                choice = input("Skip this line and continue? [y/N]: ")
                if choice.lower() != "y":
                    print("Aborting job.")
                    break

    except KeyboardInterrupt:
        print("\n⛔ Interrupted by user")

    finally:
        # Safe shutdown
        ser.write(b"M5\n")   # spindle/laser off
        time.sleep(0.1)
        ser.write(b"G0 Z5\n")  # pen up
        time.sleep(0.3)
        ser.close()
        elapsed = time.time() - start_time
        print(f"\n{'✅ Job complete' if errors == 0 else '⚠️  Job finished with errors'}")
        print(f"   Lines sent:  {i+1} / {total}")
        print(f"   Duration:    {elapsed/60:.1f}m {elapsed%60:.0f}s")
        print(f"   Errors:      {errors}")


def go_home(port: str, baud: int):
    print(f"🏠 Homing via {port}...")
    ser = serial.Serial(port, baud, timeout=5)
    time.sleep(2)
    ser.write(b"G28\n")
    time.sleep(0.5)
    ser.write(b"G0 X0 Y0\n")
    time.sleep(1)
    ser.close()
    print("✅ Homed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Stream GCode to pen plotter")
    parser.add_argument("--port", required=False, help="Serial port")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--file", required=False, help="GCode file path")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--home", action="store_true", help="Send machine home")
    args = parser.parse_args()

    if args.home:
        go_home(args.port, args.baud)
    elif args.file:
        stream_gcode(args.port, args.baud, args.file, args.dry_run)
    else:
        parser.print_help()
