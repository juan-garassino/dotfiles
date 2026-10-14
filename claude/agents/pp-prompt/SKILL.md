---
name: pp-prompt
description: >
  Improves the LLM prompts that turn a description into a drawing in promptplot.
  Use when `promptplot draw` produces wrong shapes, ignores bounds, or emits invalid
  output. Triggers include "improve the system prompt", "the llm is generating bad
  gcode", "fix the prompt", "the drawings don't match the description".
---

# pp-prompt — prompt engineering for the drawing DSL

## The thing an older version of this agent got wrong

**The LLM does not emit raw GCode for shapes.** It emits a `DrawProgram` — PRIMITIVE
and FREEFORM commands that `primitives.expand_primitives` expands deterministically.
Tuning the prompt to produce better raw `G1` lines is tuning the wrong layer.

## Where everything lives

| | |
|---|---|
| `llm/prompts.py` | every `build_*_prompt`, `classify_creative_mode`, presets, few-shot |
| `primitives.py` | the PRIMITIVE/FREEFORM registries and `expand_*` functions |
| `models.py` | `DrawProgram`, `DrawCommand`, `PrimitiveCommand`, `FreeformCommand` |

**Schemas are introspected from the `expand_*` function signatures** and injected into
the prompt (`get_all_primitive_schemas`, `format_schemas_for_prompt`). So:

> If the LLM cannot express something, the first fix is usually a **new primitive**,
> not more prompt text. Write the `expand_*` function, register it, and the prompt
> updates itself.

That is almost always better than another paragraph of instructions.

## Loop

1. Baseline: run several test prompts through `promptplot draw "..." --simulate`,
   keep the PNGs.
2. Change one thing in `llm/prompts.py`.
3. Re-run the same prompts with the **same seed** and compare renders side by side.
4. `make check`.
5. Stop after 2 iterations with no visible gain.

## Judge by the render

Scoring a toolpath summary to guess whether it "likely produces the requested shape"
is not evidence — an older version of this agent did that and it measures nothing.
Open the PNGs. `promptplot score FILE.gcode` gives an A–F grade on quality metrics;
it does not tell you whether the drawing looks like the prompt.

## Check these before rewriting anything

| Symptom | Usual cause |
|---|---|
| Drawing runs off the sheet | bounds not in the prompt — prompts are config-aware, confirm the paper reached them |
| Right shapes, wrong character | `classify_creative_mode` routed figurative/abstract/hybrid wrongly |
| Everything is straight segments | the model is avoiding primitives — check the schema block actually rendered into the prompt |
| Colours ignored | the palette block is only injected when `--colors N` is set |
