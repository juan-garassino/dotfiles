---
name: rx-simplify
description: >
  Analyzes and simplifies an entire project folder or codebase — not just a single file.
  Use this skill when the user wants to refactor, clean up, or reduce complexity across a full
  repository, multi-file project, package, or directory tree. Triggers include "simplify my project",
  "clean up my codebase", "refactor the whole repo", "simplify everything in this folder",
  "reduce complexity across my pipeline", "my code is too messy fix it", "simplify this ML project",
  or any request where the scope of simplification is the entire project rather than one file.
  Also use when the user wants a complexity audit report, dead code removal across multiple files,
  or wants to flatten over-engineered abstractions across a codebase.
---

# Project Simplify

Simplify an entire project folder — reducing complexity, removing dead code, flattening over-engineered abstractions, and improving readability across all files — while preserving full functionality.

This is the project-scale version of `/simplify`. The key challenge here is that changes to one file often ripple through others: you must reason about the whole codebase as a system, not file-by-file in isolation.

---

## Phase 1: Reconnaissance

Before touching any code, understand the full shape of the project.

```bash
# Map the tree (ignore common noise dirs)
find . -type f \( -name "*.py" -o -name "*.ts" -o -name "*.js" -o -name "*.go" \) \
  | grep -v -E "(node_modules|__pycache__|\.git|\.venv|dist|build)" \
  | sort
```

Build a mental model:
- **Entry points**: what runs first? (`main.py`, `app.py`, `index.ts`, etc.)
- **Core modules**: what does the bulk of the work?
- **Glue/boilerplate**: what exists mainly to wire things together?
- **Dead weight**: imports, functions, classes, configs that are never referenced

Count rough lines of code per file so you know where the complexity lives.

---

## Phase 2: Complexity Audit

Produce a structured audit **before** making any edits. This is not optional — it anchors the simplification strategy and gives the user a chance to redirect before you start rewriting.

### Audit Report Format

```
## Project Simplify Audit
**Project**: <name>  
**Files scanned**: <N>  
**Total LOC**: <N>

### High-Complexity Hotspots
| File | LOC | Issue | Severity |
|------|-----|-------|----------|
| src/pipeline.py | 412 | God class with 23 methods, 6 responsibilities | 🔴 High |
| utils/helpers.py | 180 | 70% dead code, 12 unused imports | 🟡 Medium |

### Cross-File Issues
- Duplicated logic: <describe what's duplicated and where>
- Circular imports: <if any>
- Leaky abstractions: <where internals bleed across module boundaries>
- Over-engineered patterns: <factories-of-factories, unnecessary metaclasses, etc.>

### Simplification Plan
1. [File/change] → [Why it simplifies things]
2. ...

### What will NOT change
- <Preserve public API contracts>
- <Preserve CLI interfaces>
- <Preserve test fixtures>
```

Share the audit with the user and confirm the plan before proceeding. If the project is large, ask which hotspots to prioritize.

---

## Phase 3: Simplification

Work in dependency order — start from utilities/helpers (leaf modules), then move toward entry points. This avoids breaking things mid-way.

### Core Simplification Moves

**Dead code removal**  
Delete functions, classes, imports, and config keys that are never referenced. Use grep/ast-grep to verify nothing uses them before deleting. When in doubt, comment out with `# REMOVED: <reason>` and let the user decide.

**Flatten unnecessary abstractions**  
If a class exists only to hold one method, convert it to a function. If a module just re-exports from another, inline the import at the call sites. If a factory creates only one type of object, replace with a direct constructor call.

**Merge duplicated logic**  
When the same pattern appears in 2+ files, extract to a shared utility. Name it clearly — shared code should have the most descriptive names in the project.

**Simplify control flow**  
Replace nested if/else chains with early returns. Replace flag variables with direct boolean expressions. Flatten deeply nested callbacks or promise chains. Replace one-off class hierarchies with dataclasses/TypedDicts where state + behavior are not coupled.

**Reduce config surface area**  
If 80% of config values are never overridden, fold them into defaults. If a config class has fields only used in one place, inline them.

**Naming**  
Rename anything that requires a comment to understand. The code should be the comment.

### Preserving Correctness

After each file edit:
1. Check for import errors: `python -c "import <module>"` or equivalent
2. Run existing tests if present: `pytest`, `npm test`, etc.
3. Grep for all usages of what you removed/renamed to catch broken references

If tests are absent, note that in the summary and don't make aggressive changes.

---

## Phase 4: Summary Report

After all edits, produce a concise summary:

```
## Simplification Complete

### Changes Made
| File | Before LOC | After LOC | Changes |
|------|------------|-----------|---------|
| src/pipeline.py | 412 | 187 | Extracted 3 utility fns, removed dead config handlers |
| utils/helpers.py | 180 | 44 | Deleted 8 unused functions, collapsed 3 trivial wrappers |
| ...

### Complexity Removed
- **Dead code deleted**: N functions, N classes, N imports
- **Duplicated logic merged**: N instances → 1 shared utility
- **Abstractions flattened**: N classes → functions, N factories → direct calls

### What Was Preserved
- All public interfaces / exported symbols
- All test fixtures
- CLI argument signatures

### Recommended Next Steps (not done here)
- Add type annotations to <file> — currently untyped
- Write tests for <module> before further refactoring
- Consider splitting <large-file> into <suggested-structure>
```

---

## Decision Rules

**When to be conservative (make smaller changes):**
- No tests in the project
- Public API or library with external consumers
- ML training code where subtle order-of-ops matters
- User explicitly says "don't change behavior, only cleanup"

**When to be more aggressive:**
- User says "go for it", "clean slate", "I trust you"
- Project is a personal script, research prototype, or internal tool
- There are comprehensive tests

**Things to never do without explicit user approval:**
- Change function signatures or public APIs
- Merge files (only inline code within files)
- Delete anything that could be a test fixture or saved model artifact
- Rename CLI flags or environment variables

---

## ML/AI Projects: Special Considerations

Juan's projects tend to be ML pipelines, agentic systems, and data science work. Extra rules apply:

- **Don't simplify away explicitness in tensor shapes** — `einsum` with comments explaining dimensions is not "over-engineered"
- **Preserve training checkpointing logic** even if it looks verbose
- **Don't collapse config into hardcoded values** if the config is used in experiments
- **Agent tool definitions** (especially tool schemas) should stay explicit even if they look repetitive
- **Keep reward functions, observation vectors, and action spaces verbatim** — subtle changes break RL environments
