---
name: pp-optimize
description: >
  Improves toolpath ordering in promptplot — reducing pen lifts and travel distance
  without breaking colour layering. Use when travel is genuinely excessive for the
  drawing. Triggers include "optimize the toolpath", "reduce pen lifts", "improve
  path ordering", "my travel distance is too high", "optimize the stroke order".
  Modifies source, not individual GCode files.
---

# pp-optimize — toolpath ordering

**There is no `scripts/simulate.py`.** Measure with `python -m promptplot preview
FILE.gcode --stats`.

## Read this first — most travel here is not waste

A dense studio plate legitimately runs 40–60% travel: each contour ring is its own
closed stroke with a lift between. That is the drawing, not an inefficiency. Before
optimising anything, establish that the travel is **avoidable** — compare against a
plate of similar structure, not against an abstract percentage.

The one case that is clearly worth fixing: **within-pass travel on painterly plates**,
where thousands of short strokes in one colour are emitted in generation order rather
than spatial order. The acrylic reconstruction runs ~96 m travel against 68 m draw.

## Where the code is

| | |
|---|---|
| `postprocess.optimize_stroke_order` | the nearest-neighbour reorder |
| `postprocess.reorder_by_color` | groups by pen, optimises **within** each colour |
| `postprocess.run_pipeline` | the 6-stage order — do not reorder the stages |

## The constraint that breaks drawings

**Never reorder strokes across a colour boundary.** Colour order is a physical pen-swap
sequence; reordering across it means the plotter asks for pen 2, then pen 0, then pen 2
again. `reorder_by_color` exists precisely to optimise inside a bucket only — improve
it there, do not route around it.

Equally: a stroke's `color` and the `G0`/`G1` pen convention must survive any reorder.
`split_color_layers` relies on each layer keeping its own pen-up approach travel.

## Loop

1. Measure: `python -m promptplot preview FILE.gcode --stats` — record draw and travel.
2. Change `optimize_stroke_order` (or the within-colour path).
3. Re-measure the **same** file. Travel down, draw unchanged → good. Draw changed at
   all → you altered the drawing; revert.
4. `make check` — `test-ci` plus `studio-check`. Reordering touches shared code; the
   51 studio pieces are fingerprinted by a hash of every coordinate, so a reorder that
   changes any plate shows up immediately.
5. Stop after 2 iterations with no gain.

## Worth trying, in order

- Spatial sort within a colour bucket before nearest-neighbour (cheap, big win on
  thousands of short strokes).
- Or-opt / 2-opt on the lift sequence only.
- Stroke **reversal** — a closed ring can start anywhere; letting the optimiser pick
  the entry point often beats reordering the rings.

Do not add a TSP solver dependency. This is a preprocessing step, not the product.
