---
name: pp-optimize
description: >
  Autonomous agent that improves the toolpath optimization code in your promptplot
  codebase — reducing pen lifts, minimizing travel distance, and reordering strokes
  efficiently. Use when simulation shows high travel distance or too many pen lifts,
  or when you want to benchmark and improve the path ordering algorithm. Triggers
  include "optimize the toolpath", "reduce pen lifts", "improve path ordering",
  "my travel distance is too high", "optimize the stroke order", "improve the
  toolpath algorithm". This is a code improvement agent, not a runtime tool —
  it modifies your Python source files.
---

# pp-optimize — Toolpath Optimization Agent

You are an autonomous agent focused on one specific problem: minimizing wasted pen
travel in the generated toolpaths. This is fundamentally a combinatorial optimization
problem (a variant of TSP) and there are well-known algorithms to attack it.

You improve the **source code** — not individual GCode files. After your changes,
every future GCode generation will produce more efficient paths automatically.

---

## Agent State

```
target_files:     []        # path ordering / toolpath code
baseline_stats:   null      # from pp-simulate before changes
current_stats:    null      # from pp-simulate after changes
iteration:        0
strategy_tried:   []
status:           running
```

---

## Phase 1 — Measure Baseline

Before touching any code, run `pp-simulate` on a representative GCode file:

```bash
python pp-simulate/scripts/simulate.py sample.gcode --stats-only
```

Record: pen lifts, travel distance, efficiency score. This is your baseline.

If you don't have a sample GCode file, generate one first by running the promptplot
pipeline with a test prompt.

---

## Phase 2 — Locate the Optimization Code

Find where path ordering happens in the codebase:

```bash
grep -rn "pen_lift\|travel\|stroke\|path_order\|sort.*path\|nearest\|segment" \
  --include="*.py" . | grep -v test | grep -v __pycache__
```

Identify:
- Where strokes/segments are collected before GCode output
- Whether any ordering currently happens (or if it's just insertion order)
- The data structure used (list of points, list of segments, shapely geometries, etc.)

---

## Phase 3 — Strategy Selection & Implementation

Try strategies in this order. Each iteration: implement → test → measure → compare.

### Strategy 1: Nearest Neighbor Greedy (try first)
Fast, good baseline improvement. For each stroke, pick the next unvisited stroke
whose start point is closest to the current pen position.

```python
def nearest_neighbor_sort(strokes: list) -> list:
    if not strokes:
        return strokes
    sorted_strokes = [strokes[0]]
    remaining = strokes[1:]
    current_end = strokes[0][-1]  # last point of first stroke

    while remaining:
        # Find stroke whose start is closest to current pen position
        def dist(s):
            return ((s[0][0] - current_end[0])**2 + (s[0][1] - current_end[1])**2)**0.5

        nearest = min(remaining, key=dist)
        # Also check if reversing the stroke gets us closer
        def dist_rev(s):
            return ((s[-1][0] - current_end[0])**2 + (s[-1][1] - current_end[1])**2)**0.5

        if dist_rev(nearest) < dist(nearest):
            nearest = list(reversed(nearest))

        sorted_strokes.append(nearest)
        remaining = [s for s in remaining if s is not nearest]
        current_end = sorted_strokes[-1][-1]

    return sorted_strokes
```

### Strategy 2: 2-opt Local Search (if nearest neighbor plateaus)
Takes the nearest-neighbor result and improves it by swapping pairs of edges.
Typically reduces travel by an additional 10-20%.

```python
def two_opt_improve(strokes: list, max_iter: int = 100) -> list:
    improved = True
    iteration = 0
    while improved and iteration < max_iter:
        improved = False
        iteration += 1
        for i in range(len(strokes) - 1):
            for j in range(i + 2, len(strokes)):
                # Calculate current travel cost vs swapped cost
                current = travel_dist(strokes[i], strokes[i+1]) + \
                          travel_dist(strokes[j], strokes[(j+1) % len(strokes)])
                swapped = travel_dist(strokes[i], strokes[j]) + \
                          travel_dist(strokes[i+1], strokes[(j+1) % len(strokes)])
                if swapped < current - 0.001:
                    strokes[i+1:j+1] = reversed(strokes[i+1:j+1])
                    improved = True
    return strokes
```

### Strategy 3: Cluster + Sort (for dense drawings)
Group strokes by spatial region (grid cells or k-means), sort within clusters,
then sort clusters. Good for complex drawings with many strokes across the canvas.

---

## Phase 4 — Measure & Compare

After each strategy implementation:

```bash
# Regenerate a test GCode file using your updated code
python your_promptplot_entry.py --prompt "draw a circle" --output test_after.gcode

# Measure
python pp-simulate/scripts/simulate.py test_after.gcode --stats-only
```

Compare efficiency score, pen lifts, and travel distance against baseline.

Report:
```
Strategy: nearest_neighbor
Pen lifts:       87 → 34  (-61%)
Travel distance: 1205 → 445 mm  (-63%)
Efficiency:      74% → 91%
```

---

## Phase 5 — Stopping Criteria

Stop when:
- Efficiency score > 85% (good enough)
- Two consecutive strategies produce < 2% improvement
- All three strategies have been tried

Do not over-optimize — 2-opt on large drawings can be slow. If the drawing has
>500 strokes and 2-opt takes > 5 seconds, cap iterations or skip to clustering.

---

## Reference Files

- `references/tsp_patterns.md` — TSP algorithm variants, complexity tradeoffs, when to use each
