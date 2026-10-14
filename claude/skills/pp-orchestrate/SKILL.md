---
name: pp-orchestrate
description: Drives the PromptPlot supervisor-worker loop from Claude Code — plan regions, generate per region, validate, score, retry weak regions, stream to plotter. Use when the user asks to "draw something dense", "make a 10k drawing", "orchestrate a large drawing", "draw this region by region", or any request for a high-density pen-plot composition that exceeds a single LLM call's output cap.
---

# pp-orchestrate

You are the **Claude Code controller** for PromptPlot. The Python package
`promptplot.orchestrate` exposes a pure-function API — you drive the loop;
the package owns the primitives.

## When to use

Trigger phrases:
- "draw something dense"
- "make a 10k drawing"
- "orchestrate a large drawing"
- "draw this region by region"
- "supervisor-worker drawing"

If the user just wants a normal one-shot drawing, do NOT use this skill —
use `pp-validate` + `pp-stream` or the regular `promptplot draw` flow.

## The loop

```python
from promptplot.orchestrate import (
    plan_regions, generate_region, validate_chunk,
    score_chunk, merge_chunks, stream_chunk,
)
from promptplot.engine import PenState
from promptplot.config import get_config
from promptplot.llm import get_llm_provider
from promptplot.plotter import SerialPlotter, SimulatedPlotter
from promptplot.checkpoint import CheckpointManager

config = get_config()
llm = get_llm_provider(config.llm)
plotter = SerialPlotter(port=PORT) if not simulate else SimulatedPlotter()
ckpt = CheckpointManager()

regions = plan_regions(
    (0, 0, config.paper.width, config.paper.height),
    strategy="grid_2x2",   # or "grid_3x3", "radial", "composition_plan"
)

pen = PenState()
all_chunks = []
async with plotter:
    for i, region in enumerate(regions):
        # 1. generate (one worker LLM call)
        chunk = await generate_region(prompt, region, llm, config)
        # 2. validate + clamp + thread pen state
        chunk, warns, pen = validate_chunk(chunk, pen, config.paper)
        # 3. score
        metrics = score_chunk(chunk, region)
        # 4. retry once if weak
        if metrics.coverage < 0.25 or metrics.segment_count < 10:
            chunk = await generate_region(prompt, region, llm, config)
            chunk, warns, pen = validate_chunk(chunk, pen, config.paper)
        # 5. stream
        await stream_chunk(chunk, plotter)
        all_chunks.append(chunk)
        # 6. checkpoint
        ckpt.save({
            "prompt": prompt,
            "region_index": i + 1,
            "completed_regions": [r.model_dump() for r in regions[: i + 1]],
            "pen_position": [0.0, 0.0],
        })

# Final merge to disk
program = merge_chunks(all_chunks, config)
```

## API reference (`promptplot.orchestrate`)

- `plan_regions(bounds, strategy, composition_plan=None) -> List[Region]`
  Strategies: `"grid_2x2"`, `"grid_3x3"`, `"quadrant"`, `"radial"`, `"composition_plan"`.
- `generate_region(prompt, region, llm, config, plan_context=None) -> List[GCodeCommand]`
  One worker LLM call. Output is already clamped to region bounds.
- `validate_chunk(commands, prior_pen_state, paper) -> (commands, warnings, pen_state)`
  Bounds + pen safety. Threads `PenState` across the loop.
- `score_chunk(commands, region) -> ChunkMetrics`
  Fields: `coverage`, `segment_count`, `angle_variance`, `primitive_ratio`, `command_count`.
- `merge_chunks(chunks, config) -> GCodeProgram`
  Concat with pen-up separators + full postprocess pipeline.
- `stream_chunk(commands, plotter, on_pause=None) -> (success, errors)`
  Streams to the plotter; optional `on_pause` callback after the chunk.
- `load_and_continue(prior_gcode_path, new_commands, config) -> GCodeProgram`
  Resume an existing .gcode file by appending new commands with safe travel.

## From the CLI

There is **no `scripts/orchestrate.py`** — an earlier version of this skill invented
one. The loop is reachable from the CLI:

```
python -m promptplot draw "a dense ocean of waves" --orchestrate --regions 8 \
    --paper a5 --orientation landscape --simulate
```

Drop `--simulate` and add `--port /dev/cu.usbserial-14120` for hardware — but trace
the frame first (below).

## Before any of this reaches paper

`stream_chunk` puts ink down. Two things this skill predates:

**1. Trace the frame first.** Non-negotiable:

```
python -m promptplot plot frame --paper a5:landscape --margin 15
```

**2. Colour layers.** If the drawing has more than one pen, do NOT stream region by
region — you would swap pens once per region. Merge first, then stream by pen:

```python
from promptplot.orchestrate import merge_chunks, stream_pen_layers
program = merge_chunks(all_chunks, config)
await stream_pen_layers(program, plotter, config)   # parks + pauses per swap
```

Stream per region only for a single-pen drawing.

`split_color_layers` keeps each layer's pen-up approach travel attached, and
`stream_chunk(enforce_pen_state=True)` injects the missing `M5`/`M3`. Never hand-roll
around either. **`G0` = travel (pen up), `G1` = draw (pen down).**

## Decision rules

- **Density target**: 8+ regions when the prompt asks for "dense" or "10k".
- **Strategy**: `grid_2x2` for 4 regions, `grid_3x3` for 9, `radial` for
  subject-vs-frame compositions, `composition_plan` when an LLM plan exists.
- **Retry budget**: one retry per weak region. Never recurse.
- **Checkpoint cadence**: after every region completes streaming.
- **Pen state**: always thread the returned `PenState` into the next
  `validate_chunk` call. Do not reset between regions.
