---
name: pp-stream
description: >
  Sends GCode to the physical pen plotter — traces the paper frame pen-up first,
  then streams one colour layer at a time with the package's streaming guardrails.
  Use when the user wants to plot something for real. Triggers include "send this
  gcode to the plotter", "start drawing", "plot this", "run this on the plotter",
  "connect to the plotter".
---

# pp-stream — driving the machine

**There is no `scripts/serial_stream.py` or `scripts/detect_ports.py`** — an older
version of this skill invented both, and also told you to stream the whole file in one
go with no frame trace. Do not do that.

## The rule that is not optional

**Trace the frame, pen up, before any ink touches paper.** It is how you find out the
sheet is the wrong size, mounted crooked, or that the machine is not where it thinks it
is — while the pen is still in the air.

```bash
python -m promptplot plot frame --paper a5:landscape --margin 15
```

It walks the paper edge (3 s hold after the first edge so you can stop it) then the
margin rectangle, and returns home. Only then stream.

## Then: one colour layer at a time

```bash
python -m promptplot plot layer FILE.gcode --list          # what layers exist
python -m promptplot plot layer FILE.gcode 0 --dry-run     # what layer 0 would do
python -m promptplot plot layer FILE.gcode 0               # stream it
python -m promptplot plot layer FILE.gcode 0 --strokes 0:400   # or in batches
```

Between layers the head parks at exactly `(0,0)`; swap the pen and run the next index.
`--strokes S:E` splits a long layer so you can stop cleanly at a known point.

**Do not use `plot file`** for real work — it is the legacy whole-file path and skips
the per-layer guardrails.

## Leo

| | |
|---|---|
| Paper | **A5 landscape** — re-render at the target paper, never scale GCode |
| Port | `/dev/cu.usbserial-14120` |
| Heartbeat | **off** while streaming — two coroutines reading one serial port is how acks get stolen |
| Feeds | Leo drags ink on lifts: draw `F600`, travels slowed to `G1 F2000`, `G4 P1.0` dwells around pen moves |
| Drift | Leo loses position on long plots. Break long layers into `--strokes` batches and re-check (0,0) between them. |

## The guardrails you must not hand-roll around

In `promptplot/orchestrate.py`, all regression-tested:

- `split_color_layers` keeps each layer's pen-up positioning travel attached, so
  streaming one layer alone cannot drop the pen at home and drag to the first stroke.
- `stream_pen_layers` lifts and rapids to the layer's first drawn point first.
- `stream_chunk(enforce_pen_state=True)` injects the missing `M5`/`M3` so a `G0` travel
  is never inked and a `G1` draw never floats.

**`G0` = travel (pen up). `G1` = draw (pen down).** Never emit `G1` for positioning.

## From the gallery viewer instead

The plate on screen can be sent straight from the browser:

```bash
python scripts/gallery_serve.py --allow-plot --paper a5:landscape \
    --serial-port /dev/cu.usbserial-14120
```

The Plot panel lists the layers and streams them. The server enforces the same rule —
it refuses an ink job until a frame has been traced **in that process**.

## When it goes wrong

| Response | What it means | Do |
|---|---|---|
| `ok` | ready for the next line | continue |
| `error:X` | bad command — pp-validate would have caught it | stop, report the line |
| `ALARM:X` | it hit a limit — emergency stop | **stop**. Do not re-home blind; tell the user, the sheet is probably ruined |
| timeout | ack lost (60 s window) | stop and report; do not blindly resend — a resent motion double-inks |

On any abort: `M5` (pen up), then park. Never leave the pen down.

## Before you stream

Run **pp-validate** first. If it warns, do not stream.
