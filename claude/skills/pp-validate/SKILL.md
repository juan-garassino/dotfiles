---
name: pp-validate
description: >
  Validates GCode before sending it to the pen plotter. Checks for syntax errors,
  out-of-bounds moves, missing pen lifts, dangerous feed rates, and structural issues.
  Use before every streaming job and after every GCode generation. Triggers include
  "validate this gcode", "check the gcode before sending", "is this safe to run",
  "validate before plotting", "check bounds". Runs the bundled validator script directly.
---

# pp-validate — GCode Validator

Pre-flight validation before anything touches the plotter. Catches issues that would
cause failed drawings, machine crashes, or wasted paper.

Run this automatically before every `pp-stream` job.

---

## Usage

```bash
python scripts/validate.py <gcode_file> \
  --x-max 300 \
  --y-max 420 \
  --z-safe 5 \
  --max-feed 5000
```

Default bounds (A3 canvas): X=297mm, Y=420mm. Override with your machine's actual limits.

---

## What Gets Checked

| Check | What it catches |
|-------|----------------|
| Syntax | Malformed G/M codes, missing coordinates |
| Bounds | Any move outside X/Y canvas limits |
| Z safety | Moves without pen lift between strokes |
| Feed rate | Dangerously high F values |
| Start/end | Missing G28 home or G0 Z5 pen-up at end |
| Empty file | Zero moves — nothing to draw |
| Units | G20/G21 mismatch (inches vs mm) |

---

## Output

```
pp-validate — GCode Validation Report
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
File:     drawing.gcode
Lines:    1204
Moves:    847

✅ Syntax:       OK
✅ Bounds:       OK  (X: 0-284mm, Y: 0-398mm — within 297x420)
⚠️  Z safety:    2 missing pen lifts at lines 342, 891
✅ Feed rates:   OK  (max: 3000 mm/min)
✅ Start/end:    OK
✅ Units:        mm (G21)

Result: ⚠️  WARNINGS — safe to run but review flagged lines
```

Exit codes: `0` = clean, `1` = warnings, `2` = errors (do not run)
