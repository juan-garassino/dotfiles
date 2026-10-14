---
name: whats-the-goal
description: Use when the user wants the current session's work distilled into a ready-to-paste /goal directive — triggers "whats the goal", "/whats-the-goal", "make this a goal", "turn this into a goal", "goal prompt", "give me the goal command", or when re-locking a goal after /clear, after a pivot, or when the active goal has drifted from what the session is actually doing.
---

# whats-the-goal — session state → /goal prompt

The sibling of `where-were-we`: same cheap mid-session scan, but instead of a
recap it emits a **goal-target instruction** the user pastes into the `/goal`
slash command. `/goal <text>` arms a session-scoped Stop hook, so the text must
be a self-sufficient directive: objective, measurable state, next moves, rules.

## When this vs the siblings

| Scenario | Use |
|---|---|
| "What were we doing?" (recap only) | `where-were-we` |
| Fresh session / end-of-day save | `hello-claude` |
| "Lock the current work in as the goal" | `whats-the-goal` |

## Alignment gate — ask BEFORE emitting (default)

**Default is to ask, not to emit.** Unless the goal is *extremely* clear —
an armed `/goal` exists AND the session visibly continued it with no pivot —
you MUST first ask 1-3 questions with the `AskUserQuestion` tool to get 100%
on the same page. Only after the answers do you emit the block.

Ask about the slots you'd otherwise guess:

- **Objective/scope** — which of the candidate workstreams is THE goal
  (offer the 2-4 you see as options)?
- **Target** — which finish line / number counts as done?
- **Next ranking** — which item goes first?
- **Rules** — carry a rule you're unsure still applies? Ask, don't assume.

"Extremely clear" is a high bar: if you hesitated on ANY slot, ask. One
question round beats an armed Stop hook enforcing the wrong goal all session.
Fold the answers into the block verbatim-spirit; don't re-ask what the user
already stated this session.

## What to output

One header line, then a fenced code block (that's the paste payload), then one
usage line. Nothing else.

```
🎯  Goal prompt for this session — paste as `/goal <text>`:
```
```text
<resume-verb> the <objective> (see <memory/standing pointer if one exists>).
State: <the measurable position, with numbers — e.g. "board 97.0% priority /
90.4% all-11 on 70 SST cases, zero fabrications">.
Target: <the finish line, as a number or verifiable condition — never "improve">.
Next: (1) <concrete item>; (2) <concrete item>; (3) <concrete item>.
Rules: <the durable working rules the user has actually stated this session or
in the active goal — verbatim spirit, compressed>.
```
```
Paste the block above into /goal to arm it. (I won't run /goal myself.)
```

### Goal-text requirements

- **≤150 words.** The hook re-reads this every turn; bloat costs every stop.
- **State and Target carry numbers.** "97.0% → ~98%" survives a /clear;
  "keep improving" does not.
- **Next items are concrete and ranked** — the 2-4 things you'd actually do
  first, named by case/file/mechanism, not "continue the work".
- **Rules only from evidence.** Carry rules the user stated (in this session,
  the active goal text, or the goal memory): judging protocol, guard-battery
  discipline, generalize-never-per-case, commit/push policy. Never invent one.
- **No transient state.** No run numbers, task IDs, background-job handles, or
  "Docker is currently down" — the goal must still make sense tomorrow.

## Source signals (in order)

1. **The active `/goal` text** if one is armed — the new prompt is usually that
   text with State/Target/Next refreshed to now.
2. **The recent conversation** — user pivots and new directives override the
   old goal's wording.
3. **The goal/standing memory files** (`goal-*.md`, latest `standing/*.md`) —
   for the pointer line and the established rules.
4. **Metrics computed this session** — boards, test counts, scores.

If signals conflict, the conversation wins; note the divergence in one line
above the block ("note: this replaces the armed goal's item (2), which shipped").

## What this skill does NOT do

- **Never invokes `/goal` itself.** The user pastes it — arming a Stop hook is
  their call.
- **No file writes, no memory edits, no CLAUDE.md.** Snapshot only.
- **No recap prose.** That's `where-were-we`; this emits a directive.
- If the session has no discernible objective (exploration, Q&A), say so and
  point at `hello-claude`'s standing CONTINUATION PROMPT instead of inventing
  a goal.

## Common pitfalls

- **Guessing instead of asking.** Emitting a block straight from inference when
  the goal wasn't extremely clear skips the alignment gate. Ask first.
- **Vague target.** "Push accuracy higher" gives the Stop hook nothing to
  check. Always a number or a verifiable condition.
- **Inventing rules.** A rule the user never stated becomes a fake constraint
  the hook enforces forever. Evidence only.
- **Copying stale next-items.** If item (1) of the armed goal shipped an hour
  ago, the new block must not re-list it.
- **Over-budget.** If the block runs past ~150 words, cut Next items before
  cutting Rules — rules are what keep an autonomous loop safe.
