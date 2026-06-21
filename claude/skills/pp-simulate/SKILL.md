---
name: pp-simulate
description: >
  Simulates a GCode file without connecting to the plotter. Renders the toolpath as
  an SVG or terminal preview, estimates duration, counts pen lifts, and identifies
  inefficiencies. Use before every drawing job or when evaluating generated GCode
  quality. Triggers include "simulate this gcode", "preview the drawing", "show me
  the toolpath", "how long will this take", "dry run", "render the path". Runs
  bundled simulate.py — no plotter connection needed.
---

# pp-simulate — GCode Simulator & Previewer

Simulate and visualize GCode without touching the plotter. Use this to:
- Preview what will actually be drawn before committing
- Estimate job duration
- Count pen lifts (a proxy for toolpath efficiency)
- Catch issues the validator missed (wrong shapes, missing strokes)

---

## Usage

```bash
# SVG preview (recommended)
python scripts/simulate.py <gcode_file> --output preview.svg

# Terminal ASCII preview (quick)
python scripts/simulate.py <gcode_file> --terminal

# Stats only (no render)
python scripts/simulate.py <gcode_file> --stats-only
```

---

## Output

**SVG preview** — opens in browser, shows:
- Blue lines = pen down (drawing)
- Red dashed lines = pen up (travel moves)
- Green dot = start, Red dot = end

**Stats report:**
```
pp-simulate — Toolpath Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
GCode file:      drawing.gcode
Total moves:     847
Draw moves:      612  (pen down)
Travel moves:    235  (pen up)
Pen lifts:       87
Draw distance:   4821 mm
Travel distance: 1205 mm  (20% waste)
Est. duration:   6m 14s  @ 3000 mm/min avg

Efficiency score: 74%  (travel / total distance)
Recommendation: Run pp-optimize to reduce travel by ~30%
```

---

## Interpretation

| Efficiency | Meaning |
|-----------|---------|
| > 85% | Good — minimal wasted travel |
| 60-85% | Acceptable |
| < 60% | Run `pp-optimize` before plotting |

High pen lift count (> total_moves * 0.15) is a strong signal to optimize.
