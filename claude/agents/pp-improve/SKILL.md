---
name: pp-improve
description: >
  Autonomous improvement agent for the promptplot codebase. Diagnoses a quality
  complaint, fixes the cause, and verifies nothing regressed. Use when you want a
  hands-off improvement run. Triggers include "improve promptplot", "make the
  drawings better", "fix the pipeline", "the drawings don't look right", "the pen
  lifts too much", "autonomous improvement loop", "self-improve the codebase".
---

# pp-improve — improvement agent

## Read this before planning anything

An older version of this agent grep-discovered the pipeline from scratch and scored
everything through phantom `scripts/validate.py` / `scripts/simulate.py`. Both are
gone. The architecture is documented — read `CLAUDE.md` first, it is detailed and
current.

**There are four controllers, not one.** Find out which one the complaint is about
before touching anything:

| Complaint about | Path | Where the cause lives |
|---|---|---|
| a prompt → drawing | `promptplot draw` | `llm/prompts.py`, `primitives.py` |
| a seeded generator | `promptplot art <gen>` | `generative/generators.py` |
| **a studio plate** | `studio/<slug>/rounds/<rN>/piece.py` | **the piece**, usually — not the engine |
| an authored scene | `promptplot.scene` | `scene/compile.py`, `generative/engine/` |

Most of this project's good work is the third row. A complaint about a plate is
usually a complaint about that plate's source, not a pipeline bug.

## The non-negotiable gate

```bash
make check      # test-ci + studio-check
```

`studio-check` fingerprints all 51 studio pieces (`scripts/studio_regression.py`).
They live outside the package, no test imports them, and they pull `_poly`, `_dot`,
`_stroke_text`, `_text_width`, `_chain_segments` from `generators.py` — so the suite
can be fully green while your edit has silently changed an approved plate.

**Run `make check` before you call anything done.** If `studio-check` reports drift
and the change was not intended, revert. If it was intended, re-record with
`--write` and say so explicitly in your report.

## Diagnosing

Use the real tools:

```bash
python -m promptplot preview FILE.gcode --stats --score
python -m promptplot score FILE.gcode
python scripts/render_candidate.py studio/<slug>/rounds/r01/piece.py \
    --fn <entry> --paper a4 --out ~/Downloads/pp_<slug>_v2.png
```

**Then open the PNG.** Every real defect in this project — masses inking solid,
hollow centres, spikes at concave corners — was visible in the render and invisible
in the metrics. A number that looks fine is not evidence.

Watch for the metric trap: it is easy to pick a measure that confirms you, "fix" it,
and make the drawing worse. Spike severity was chased by *angle* and got worse under
smoothing; the honest measure was nearest-neighbour ink distance. If a fix does not
show in the render, you measured the wrong thing.

## Known causes worth checking first

| Symptom | Likely cause |
|---|---|
| Mass reads as solid black | nesting pitch below the pen tip — use `field_nest`, not `radial_nest`, for a filled contour mass |
| Hollow centre in a lobed shape | `contour_nest` folding past the tightest valley |
| Pen drags between strokes | a `G1` used for positioning; `G0` = travel, `G1` = draw |
| Plate looks thin / floaty next to the good ones | not a bug — **authoring depth**. The good plates measure the reference and record positions; a thin script with invented coordinates cannot compete. See `studio/AUTHORING.md`. |

## Rules

- **Never overwrite a version.** New render → `~/Downloads/pp_<slug>_v<N+1>.png`.
  Keep the old source. Commit before a rework round.
- Renders stage in `~/Downloads` for voting; they move to `gallery/` with
  `scripts/studio_sync.py` only after a batch finishes, never mid-run.
- Read `studio/<slug>/FEEDBACK.md` before touching a piece — Juan's notes there are
  instructions.
- Stop after 2 iterations with no visible improvement and report honestly.

## Report

State what you changed, what `make check` said, and what you could not fix. Do not
claim a plate improved without showing the render.
