---
name: where-were-we
description: Mid-session context refresh. Quick recap of the past N user prompts + what Claude was doing, surfacing the last concrete pause-point and the most likely next move. No file writes, no /clear, no memory updates — this is the lightweight companion to hello-claude. Use after a meeting, a coffee break, an interruption, or any time the user wants to re-orient mid-session. Triggers: "where were we", "where were we again", "what were we doing", "remind me what we were doing", "what's the status", "summary so far", "context check", "I'm back" (mid-session — distinguish from hello-claude resume which is a fresh session).
---

# where-were-we — lightweight mid-session recap

This is the "I just came back from a meeting" skill. Cheap, fast, no side effects.

## When this vs hello-claude

| Scenario | Use |
|---|---|
| Fresh new session, returning after overnight/weekend | `hello-claude` (reads STANDING.md) |
| Same session, returning after a meeting/coffee break/interruption | `where-were-we` (just summarize recent context) |
| Want to save state before /clear | `hello-claude --save` |

If the user invokes this skill but the conversation has very few recent messages (< 3 user turns), gently suggest `hello-claude` instead — they may want the persistent-state version.

## What to output

A 5-bullet recap, max ~120 words total:

```
🧭  Where we were

• **Last user ask:** <one line summary of the user's most recent substantive request>
• **What I was doing:** <one line — current task, with file path if relevant>
• **Where we paused:** <one line — concrete state, e.g. "halfway through correcting page 2 of fb3a6ce5", "waiting for OCR background job bly57qsfu", "draft of llm_correct.py written, not yet syntax-checked">
• **Open thread:** <one line — anything outstanding that wasn't resolved>
• **Likely next step:** <one line — phrased as a question or suggestion>
```

Examples of "where we paused":
- "Background OCR job still running (~40 min in)"
- "Wrote `auw-correct/SKILL.md`; haven't tested invocation yet"
- "Mid-correction of file `fb3a6ce5/page01.txt`, page02 still pending"
- "Waiting for your decision on whether to include `claude_corrections` in the benchmark"

## Source signals

In order of reliability:

1. **The recent conversation itself** — look back at the last 5–10 user/assistant message pairs. The user's most recent substantive request is the strongest signal.
2. **Background tasks** — if any are running (you'll know from prior TaskCreate/Bash run_in_background calls), name them.
3. **Recently edited files** in the project (`find . -mmin -60 -type f 2>/dev/null | head`).
4. **The last tool call you made** — it indicates what you were partway through.

If signals 1 and 2 conflict (user asked for X but a background job is doing Y), surface both: "You asked about X; meanwhile background job is doing Y."

## What this skill does NOT do

- **No file writes.** No CLAUDE.md updates. No memory edits. No STANDING.md.
- **No /clear or hint about clearing.** Stay in the same session.
- **No deep history scan** — this is the past hour, not the past week.
- **No proactive action.** End with a question, not "I'll do X now."
- **No restating the entire conversation.** Compress aggressively. If the user wanted the whole history, they'd scroll up.

## Common pitfalls

- **Don't fabricate a "where we paused" if you genuinely don't know.** Say "I'd been doing X but I don't have a clear pause-point — what were you about to ask?"
- **Don't repeat what's already on screen.** If your last message was 30 seconds ago and the user just got back, your last message is still visible — don't paraphrase it.
- **Don't insert a TODO list.** That's `hello-claude` territory. This is a snapshot, not a plan.

## Length budget

Aim for the response to fit on one screen without scrolling. 5 bullets + a question = ~120 words. Anything longer means you're recapping when you should be just pointing.
