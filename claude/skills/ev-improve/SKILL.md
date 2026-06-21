---
name: ev-improve
description: >
  Autonomously improve code by running an evaluation framework, analyzing failures,
  applying targeted fixes, and iterating until quality improves or plateaus. Use this skill
  when the user wants to optimize code against a measurable eval — any eval type: pytest,
  custom scripts, LLM-as-judge scorers, or benchmark metric files. Triggers include
  "improve this code until the evals pass", "self-improve against my benchmark",
  "run the evals and fix what's failing", "optimize my agent until the score goes up",
  "iterate on this file until it passes", "eval-driven improvement", "close the loop on
  my evaluation", or any request combining code improvement with a runnable evaluation.
  Also triggers when the user has an existing eval harness and wants Claude Code to
  autonomously drive the fix-evaluate-fix loop. This skill is designed for Claude Code.
---

# Self-Improve

Autonomously close the eval-improve loop: run evaluations, diagnose failures, apply targeted
fixes, re-run, and iterate — until quality improves or you hit a plateau or budget.

This is a **coding agent loop**, not a one-shot fix. It requires:
- A runnable evaluation command or framework (pytest, custom script, LLM judge, metric file)
- One or more target source files to improve
- A stopping criterion (pass rate threshold, score target, or max iterations)

---

## Is this the right tool?

Use `self-improve` when:
- You have a **measurable eval** (not just "make it better")
- The fix requires **multiple iterations** (one-shot editing won't cut it)
- Failures require **diagnosis**, not just application of known changes

If you already know what to change, use `str_replace` directly. This skill is for when
you need to *discover* what to change by running evals.

---

## Phase 0: Setup

Before starting the loop, collect everything needed:

### Required Information

```
TARGET FILES:  Which file(s) to improve? (and their direct dependencies)
EVAL COMMAND:  What command runs the evaluation? (see Eval Types below)
SUCCESS GOAL:  What does "good enough" look like? (e.g., pass rate ≥ 0.90, score ≥ 8.0)
MAX ITERS:     How many improvement iterations before stopping? (default: 5)
WEB SEARCH:    Allow web search when the fix is unclear? (default: yes, autonomous)
```

If any of these are missing, ask the user before starting.

### Snapshot Before Starting

```bash
# Always create a baseline snapshot so we can diff and revert
cp -r <target_dir_or_files> /tmp/self-improve-baseline-$(date +%s)/
```

Log the baseline eval score before any changes. This is the anchor for all comparisons.

---

## Phase 1: Run Evals & Parse Results

Run the eval command and capture structured output. See `references/eval_parsers.md` for
format-specific parsing patterns.

### Eval Types

**pytest / unit tests**
```bash
pytest <test_path> -v --tb=short --json-report --json-report-file=/tmp/eval_results.json
# Parse: count passed/failed, extract failure messages and tracebacks
```

**Custom eval script**
```bash
python eval.py --output /tmp/eval_results.json
# Expect JSON with at least: {"score": float, "details": [...]}
# If the script doesn't output JSON, capture stdout and parse with LLM
```

**LLM-as-judge**
```bash
python judge.py --target <file> --output /tmp/judge_results.json
# Expect: {"scores": {"relevancy": 0.x, "faithfulness": 0.x, ...}, "failures": [...]}
```

**Benchmark / metric file**
```bash
python run_benchmark.py && cat metrics.json
# Expect: {"metric_name": value, ...} — compare against baseline
```

### Structured Eval Summary

After running, produce this summary internally before any diagnosis:

```
EVAL RUN #<N>
─────────────
Command:    <command>
Timestamp:  <time>
Duration:   <Xs>

Results:
  Pass rate:    X/Y (Z%)
  Score:        X.X / 10.0   [if score-based]
  Delta vs baseline: +/- X%

Failures (<N> total):
  1. [test_name / case_id] — <short error message>
  2. ...

Top failure categories:
  - <category>: <count> failures
  - <category>: <count> failures
```

---

## Phase 2: Diagnose Failures

This is the reasoning core — don't skip it. Understand WHY things are failing before
deciding what to change.

### Failure Analysis Protocol

For each cluster of failures, answer:

1. **Root cause**: Is this a logic error, an interface mismatch, an outdated API, a missing
   edge case, or a performance issue?
2. **Blast radius**: Does fixing this affect other passing tests? Check the target file's
   callers.
3. **Confidence**: How confident are you in the fix? (High / Medium / Low)
4. **Web search needed?** Is this failure pattern something where external knowledge would
   help? (see Web Search Decision below)

### Web Search Decision

Search the web when:
- The failure involves a library API that may have changed (e.g., `DeprecationWarning`, wrong kwargs)
- The failure pattern matches a known class of bugs (e.g., async context manager issues, CUDA memory errors)
- You've tried a fix in a previous iteration and it didn't work — look for alternative approaches
- The eval is testing against an external standard (OpenAI evals, HuggingFace benchmarks, etc.)

Don't search when:
- The failure is clearly a logic error in code you wrote
- The fix is obvious from the traceback alone
- You just searched for the same thing in the previous iteration

**How to search:** Use targeted queries — include the library name, version if visible,
and the specific error or pattern. Example: `langgraph ConditionalEdge return type error 0.2`
not `how to fix my agent`.

Read `references/web_search_patterns.md` for effective query templates by failure type.

---

## Phase 3: Generate & Apply Fix

### Fix Strategy Selection

Choose the minimal intervention that addresses the root cause:

| Root Cause | Strategy |
|-----------|----------|
| Logic error in function | Targeted `str_replace` on the function body |
| Wrong return type / interface | Fix signature + all call sites in target files |
| Missing edge case | Add guard clause + test coverage extension |
| Outdated API usage | Update call pattern across target file(s) |
| Architectural issue | Refactor — requires explicit plan shown to user first |
| Performance / token issue | Profile → optimize hot path only |

### Fix Application Rules

- **One hypothesis per iteration** — don't try to fix 5 things at once. Pick the highest-impact
  failure cluster, fix it cleanly, then re-eval. Shotgun changes make it impossible to know
  what worked.
- **Preserve passing tests** — before applying, identify which tests are currently passing.
  Your fix must not break them.
- **Show the diff** — after applying changes, always show a unified diff so the user can see
  what changed.
- **Scope: target files + direct dependencies** — you may edit the target file and any file
  it directly imports from *within the project*. Do not edit third-party packages or test
  fixtures unless explicitly told to.

```bash
# After applying changes, show the diff
git diff <target_files>
# If not a git repo:
diff -u /tmp/self-improve-baseline-*/target.py target.py
```

---

## Phase 4: Re-Evaluate & Compare

Run the same eval command again. Produce a comparison:

```
ITERATION <N> RESULTS
─────────────────────
Baseline:    X/Y passing (Z%)
Previous:    A/B passing (C%)
Now:         D/E passing (F%)

Delta this iteration:  +/- X%
Delta vs baseline:     +/- Y%

Newly passing:  [test names]
Newly failing:  [test names]  ← CRITICAL: investigate if any
Still failing:  [test names]
```

**If newly failing tests appeared**: the fix introduced a regression. Assess severity:
- Minor (1-2 unrelated tests flaking): proceed with a note
- Moderate (related tests broke): revert this change and try a different approach
- Severe (pass rate dropped): revert immediately, diagnose before continuing

---

## Phase 5: Stopping Criteria & Loop Control

Continue iterating if:
- Pass rate / score is still below the success goal
- The last iteration made meaningful progress (≥ 2% improvement)
- We haven't hit `max_iters`
- There are still actionable failures (not just flaky or infeasible tests)

Stop and report if:
- **Success**: goal met — report final state, total iterations, net improvement
- **Plateau**: last 2 iterations produced < 1% improvement despite valid fix attempts
- **Budget**: `max_iters` reached
- **Blocked**: all remaining failures require changes outside the allowed scope

### Plateau Recovery

Before declaring plateau, try one round of web search for the stuck failures even if you
were confident before. If still stuck, produce a **Remaining Failures Report** explaining
what each failure needs and why it's outside current scope.

---

## Final Report

Always end with:

```
SELF-IMPROVE SESSION COMPLETE
══════════════════════════════
Target:         <files>
Eval:           <command>
Iterations:     <N>
Duration:       <Xs total>

Results:
  Baseline:     X/Y (Z%)
  Final:        A/B (C%)
  Net gain:     +D%

Changes made:
  Iteration 1: [brief description of change] → +X%
  Iteration 2: [brief description of change] → +Y%
  ...

Remaining failures (<N>):
  - [test/case]: [why it's still failing and what would fix it]

Recommendation:
  [What to do next — refactor scope, add test coverage, address infeasible cases]
```

---

## Reference Files

Load on demand:
- `references/eval_parsers.md` — Format-specific parsing for pytest JSON, custom scripts, LLM judge output, benchmark files
- `references/web_search_patterns.md` — Effective search query templates by failure type (API changes, RL/ML bugs, async errors, eval regressions)
- `references/fix_patterns.md` — Common fix patterns by failure category with before/after examples

---

## Claude Code Agent Architecture Note

This skill is designed for **Claude Code** and works best when invoked as a subagent
from an orchestrator, or run as a standalone agent loop with `claude -p`. The natural
topology is:

```
User → Orchestrator (this skill) → [EvalRunner, Diagnoser, Fixer] subagents (optional)
                    ↑___________________________________|
                              (iterate)
```

For simple cases (single target file, < 5 iterations), run as a single agent.
For complex cases (multi-file refactor, many failing evals, web search needed),
consider spawning a subagent per iteration to keep context clean.
