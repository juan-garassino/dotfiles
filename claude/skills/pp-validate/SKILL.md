---
name: pp-validate
description: >
  Checks a GCode file is safe to plot — bounds against the real paper, pen-state
  sanity (G0 must be pen-up, G1 pen-down), colour-layer structure and per-layer
  stroke counts. Use before every streaming job and after every generation.
  Triggers include "validate this gcode", "check the gcode before sending",
  "is this safe to run", "check bounds", "what layers does this have".
---

# pp-validate — pre-flight check

Everything here uses the installed package. **There is no `scripts/validate.py`** —
an older version of this skill invented one.

## Fast path — the CLI

```bash
python -m promptplot preview FILE.gcode --stats --score   # bounds, stats, grade
python -m promptplot plot layer FILE.gcode --list         # colour layers + strokes
```

`plot layer --list` is the one that matters before a real plot: it tells you how many
pens the file needs and how many strokes each will take.

## Exact bounds check — the API

`preview` reports the extent; this refuses:

```python
from promptplot.config import PaperConfig, get_config
from promptplot.engine import PenState
from promptplot.orchestrate import split_color_layers, validate_chunk
from promptplot.pipeline import FilePipeline

config = get_config()
config.paper = PaperConfig.from_size("a5", orientation="landscape")  # Leo
program = FilePipeline(config).load_gcode_file("FILE.gcode")

pen = PenState()
for color, cmds in split_color_layers(program):
    cmds, warnings, pen = validate_chunk(cmds, pen, config.paper)
    if warnings:
        print(f"layer {color}: {warnings[:3]}")
```

`validate_chunk` clamps to the drawable area and threads `PenState` across layers —
always pass the returned state into the next call, never a fresh one.

## What actually matters

| Check | Why |
|---|---|
| **Paper matches the machine** | Leo is **A5 landscape**. A file rendered for A3 will run off the sheet. Re-render at the target paper — never scale GCode. |
| Bounds | `validate_chunk` warnings. Any warning = do not stream. |
| Pen convention | **`G0` = travel (pen up), `G1` = draw (pen down).** A `G1` used for positioning inks a line across the sheet. |
| Layer count | Each colour is a physical pen swap. 30 layers means 30 interruptions. |
| Ink density | Lines closer than the pen tip ink solid. See `limit_ink_density` / `enforce_line_spacing` in `generative/engine/policies.py`. |

## Then

If it passes and the user wants it plotted, hand to **pp-stream** — which traces the
frame first. Do not stream from this skill.
