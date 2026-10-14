---
name: pp-simulate
description: >
  Renders a GCode file to a PNG preview with per-pen colour layers and plot stats
  (draw/travel length, commands, pen count) without touching the plotter. Use before
  committing a drawing, or to judge a generated plate. Triggers include "simulate
  this gcode", "preview the drawing", "show me what this will draw", "how long will
  this take", "dry run", "render the path".
---

# pp-simulate — preview without the machine

**There is no `scripts/simulate.py`** — an older version of this skill invented one.
The renderer is `promptplot.visualizer`.

## CLI

```bash
python -m promptplot preview FILE.gcode -o ~/Downloads/preview.png --stats --score
```

Renders each colour layer in its palette colour with a legend, and prints draw mm,
travel mm, command count and pen count.

Add `--frames N` to also write N cumulative build-up PNGs (`<preview>_frames/frame_001.png`…)
— useful to see stroke order and where travel goes. API: `GCodeVisualizer(config).preview_frames(program, out_dir, frames=N)`.

## API — when you need physical pen widths

A 4 mm brush underpainting previewed as a hairline is unjudgeable. Pass the widths:

```python
from promptplot.visualizer import GCodeVisualizer
GCodeVisualizer(config).preview(program, out_path,
                                pen_widths={p["pen"]: p["width_mm"] for p in pen_plan})
```

`compile_scene` / `compose_plate` both return that `pen_plan`.

## Reading the numbers

Travel percentage is **not** a quality signal for these plates. A dense studio plate
legitimately runs 40–60% travel because each contour ring is its own stroke; chasing
it down reorders strokes across pens and breaks colour layering. Judge instead:

| Signal | Reading |
|---|---|
| **Draw length** | The honest cost. Leo does roughly 1 m/min. >20 m is a long sit. |
| **Draw length vs. what you expected** | The best tell. 43 m where you expected 15 m means something is nesting too tight and will ink solid — look at the render, not the number. |
| Pen count | Each one is a manual swap. |
| Commands | >100k is slow to stream but not unsafe. |

**Look at the PNG.** Every real defect found in this project — solid-black masses,
hollow centres, spikes at concave corners — was visible in the render and invisible in
the stats. Open it.

## Where previews go

`~/Downloads` is staging for voting. The repo `gallery/` is the archive; things move
there with `scripts/studio_sync.py` after a batch is finished, never mid-run.
