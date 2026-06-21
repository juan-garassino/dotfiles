---
name: hello-claude
description: Session bookend — saves state at end of day, resumes context at start of next day. Per-conversation: each save writes `~/.claude/projects/<slug>/standing/<ts>-<topic>.md`, with `--topic <slug>` to disambiguate parallel conversations on the same project. Root `STANDING.md` is preserved as a pointer with the latest content inlined so the SessionStart hook still works. SAVE mode (end of day): analyzes the current session, surgically updates the project's CLAUDE.md, writes memory entries, drops a per-conversation standing file with summary + outstanding + next-steps, prepares the user to run `/clear`. RESUME mode (start of day): picks the most recent standing (or `--topic <slug>` to scope it) and outputs a "here's where we left off" briefing. Single skill, mode auto-detected by standing freshness and the user's wording. Triggers — RESUME: "hello claude", "good morning", "im back", "I'm back", "where did we leave off", "/hello-claude" with no args. SAVE: "wrap up", "save state", "see you tomorrow", "good night", "/hello-claude save", "/hello-claude --save", "end of day", "shut down". LIST: "/hello-claude --list" enumerates available topics. When in doubt and a standing is fresh (<36h) → resume; otherwise → ask the user to confirm save.
---

# hello-claude — session bookend

A two-mode skill that captures and restores cross-session context.

---

## Flags

- `--save` — SAVE mode (see triggers below for natural-language equivalents).
- `--resume` — RESUME mode (default when no flag and STANDING is fresh).
- `--topic <slug>` — applies to both modes: SAVE writes `standing/<ts>-<slug>.md`; RESUME picks the most recent `standing/*-<slug>.md`. Slug should be 3-8 chars, lowercase, hyphenated (e.g. `classifier`, `consensus`, `tfidf`).
- `--list` — print every standing in this project's `standing/` directory (timestamp, topic, one-line summary). Don't summarize content; the user then re-invokes with `--topic`.

## Mode detection (in order)

1. **Explicit flag** in the user's invocation → use that mode
   - `--save`, "save state", "wrap up", "see you tomorrow", "good night", "end of day", "shut down" → SAVE mode
   - `--resume`, "resume", "where did we leave off", "what was I doing", "/hello-claude" alone → RESUME mode
   - `--list` → LIST mode (RESUME variant; doesn't pick or read content, just enumerates)
2. **Standing freshness** otherwise:
   - If the most recent file in `~/.claude/projects/<project-slug>/standing/` exists AND was modified < 36 hours ago → RESUME (auto-pick most recent unless `--topic` narrows it).
   - Else if legacy `~/.claude/projects/<project-slug>/STANDING.md` exists AND was modified < 36 hours ago → RESUME (legacy path — first save migrates).
   - Otherwise → use the `AskUserQuestion` tool to ask the user which mode they want. **Don't surprise-save**, and **don't fall back to a plain-text `[Y/n]`** — explicit options carry better than yes/no. The question should offer at least three choices:

     - **Save** (recommended): "Inventory this session, surgically update CLAUDE.md, write durable memories, drop STANDING.md so next session resumes cleanly. Then you `/clear` when ready."
     - **Resume / brief me**: "Skip save — print a short recap of what happened this session and what's outstanding. No file writes."
     - **Cancel**: "Do nothing. The session continues as-is."

     Same when invoked with **no args AND no STANDING.md exists** — prefer the three-option question over a yes/no, because the user might not know what `/hello-claude` does by default in a fresh project.

   - **Do not enter plan mode** for this skill. `AskUserQuestion` works fine outside plan mode; the skill should write files (CLAUDE.md edits, memories, STANDING.md) directly after the user picks Save. Plan mode is for engineering work, not session bookends.

## Path conventions

Run from the project root. Compute:

```bash
project_root=$(pwd)
slug=$(echo "$project_root" | sed 's:/:-:g')      # e.g. -Users-juan-garassino-Code-...
project_mem_dir="$HOME/.claude/projects/$slug"

# Per-conversation standing files live in standing/, root STANDING.md is a pointer.
standing_dir="$project_mem_dir/standing"
standing_pointer="$project_mem_dir/STANDING.md"   # legacy path; now a pointer + inlined latest
```

Falling back to git toplevel:
```bash
project_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
```

If `project_mem_dir` doesn't exist yet, create it. Skill is project-aware via cwd, not via skill location.

### Per-conversation layout (current)

```
~/.claude/projects/<slug>/
  standing/
    legacy-<YYYY-MM-DD>.md           # one-time snapshot of the old root STANDING.md
    20260522T173436-classifier.md    # new per-conversation files
    20260524T140000-consensus.md
  STANDING.md                        # pointer with inlined latest content
                                     # (preserved at this path so the SessionStart hook still works)
```

Filename scheme: `<UTC timestamp>-<topic-slug>.md`.

- `<topic-slug>` comes from `--topic <slug>` if the user passed it, otherwise a short auto-generated slug (4-char hash of a session identifier, or `default` if no identifier is available).
- Timestamp prefix makes default "most recent" resolution a trivial `ls -1 | sort | tail -1`.
- Same slug used twice on different days is fine — most recent wins on resume; user can `--list` to pick older.

---

## SAVE mode (end of session)

Goal: by the time the user runs `/clear`, all durable knowledge from this session is captured in CLAUDE.md (surgical updates) + project memory (new/updated entries) + STANDING.md (transient handoff doc).

### Step 1 — Inventory the session

Scan recent activity (use these signals — none individually is canonical):

- Recent files created/modified: `git status --short` and `git log --since='24 hours ago' --name-only --pretty=oneline` from the project root
- Files under `data/reports/` and `research/` modified today (`find data research -mmin -1440 -type f 2>/dev/null | head -20`)
- New scripts under `scripts/` (or wherever the project keeps them)
- Recent tool invocations / commands in this conversation
- The user's stated goals across the session (re-read your own conversation summary if available)

You're building a mental model of: what was the user trying to do, what did we accomplish, what's outstanding, what changed in the repo.

### Step 2 — Optimize CLAUDE.md (surgical)

Read `<project_root>/CLAUDE.md` if it exists.

Rules — **be conservative**:

- **Add** sections / bullet points for new scripts, paths, conventions, or skills introduced in this session that aren't documented yet.
- **Update** sections that drifted (e.g. a file path moved, a script renamed, a new flag).
- **Prune** lines that are now factually wrong (e.g. "this folder is gitignored" when it isn't anymore).
- **Don't rewrite** wholesale. Don't restructure prose unless it's clearly broken.
- **Don't add** speculative / forward-looking content. CLAUDE.md is "what is", not "what we want."

Use Edit (surgical replacements) rather than Write (full rewrite) whenever possible. If a major restructure feels needed, defer it and note the suggestion in STANDING.md instead.

### Step 3 — Write memories

For each durable observation worth keeping across sessions, write or update a memory entry. Candidates:

- User preferences expressed this session ("I prefer X over Y because Z")
- Decisions made (technical choices, architectural commitments)
- Domain facts that took non-trivial work to establish
- Patterns / failure modes documented

Memory format follows the user-level memory rules (see `/Users/juan-garassino/.claude/CLAUDE.md` if you need a refresher). One entry per file under `$project_mem_dir/memory/`, with frontmatter (`name`, `description`, `type`). Update `$project_mem_dir/memory/MEMORY.md` (one-line index per entry).

Don't write redundant memories — check existing entries first and update rather than duplicate.

### Step 4 — Write the per-conversation standing file

Resolve topic and timestamp:

```bash
ts=$(date -u +"%Y%m%dT%H%M%S")
topic="${USER_TOPIC:-default}"     # from --topic <slug> if provided
new_standing="$standing_dir/${ts}-${topic}.md"
mkdir -p "$standing_dir"
```

If the user did not pass `--topic`, prefer a meaningful slug derived from the session's dominant theme (3-8 chars, lowercase, hyphenated — e.g. `classifier`, `consensus`, `tfidf`) over the literal string `default`. Fall back to `default` only when no theme is obvious.

Write the new file with the same body as before:

```markdown
---
topic: <topic-slug>
timestamp: <YYYY-MM-DDTHH:MM:SSZ>
project: <project_name>
---

# STANDING — <project_name> — <topic> — <YYYY-MM-DD HH:MM>

## Last session — what we did
- bullet 1 (most consequential first)
- bullet 2
- bullet 3
- bullet 4
- bullet 5

## Outstanding
- bullet — what's started but not finished, blockers, things in flight
- bullet
- bullet

## Suggested next steps
- bullet — concrete first action for next session
- bullet
- bullet

## Open questions / decisions to make
- bullet — anything where you'd want the user's input before proceeding
- bullet

## Touched files
- path/to/file — what changed (one line each)
- path/to/file
```

Keep each bullet under 100 chars. Hard cap on total length: ~80 lines.

### Step 4b — Lazy migration of legacy STANDING.md (one-time, idempotent)

If the root `$standing_pointer` exists AND no `$standing_dir/legacy-*.md` exists yet, this is the first save under the new layout in this project. Migrate in place:

```bash
if [ -f "$standing_pointer" ] && ! ls "$standing_dir"/legacy-*.md >/dev/null 2>&1; then
  legacy_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$standing_pointer" 2>/dev/null || date +%Y-%m-%d)
  cp "$standing_pointer" "$standing_dir/legacy-${legacy_date}.md"
fi
```

Properties:
- Idempotent (skipped if `standing/legacy-*` already present).
- Reversible (`cp standing/legacy-<date>.md STANDING.md` restores).
- Preserves every previously-saved STANDING.md verbatim — nothing is deleted.

### Step 4c — Refresh the root STANDING.md pointer

The root path `$standing_pointer` is preserved so that the SessionStart hook in `~/.claude/settings.json` still finds something useful to inline. Rewrite it to a pointer + inlined latest content:

```markdown
<!-- This file is a pointer maintained by the hello-claude skill.
     Per-conversation standing files live in ~/.claude/projects/<slug>/standing/.
     The latest is inlined below so the SessionStart `cat` hook still works. -->

# Latest standing — <topic> — <YYYY-MM-DD HH:MM>

Most recent file: `standing/<ts>-<topic>.md`

All standings (newest first):
- standing/<ts>-<topic>.md — <one-line summary>
- standing/<older-ts>-<topic>.md — <one-line summary>
- ...
- standing/legacy-<date>.md — pre-migration snapshot

---

<inline the full body of the new standing file here>
```

The trailing inline copy of the new standing file is what existing automation (the SessionStart `cat` hook, scripts grepping `STANDING.md`) actually reads. Without it, those tools would surface only the pointer.

### Step 5 — Print the handoff and instruct the user

End the SAVE-mode response with:

```
✓ CLAUDE.md updated (or: no changes needed)
✓ Memory written: N entries (or: 0 new)
✓ Standing saved to ~/.claude/projects/<slug>/standing/<ts>-<topic>.md
  (root STANDING.md pointer refreshed; SessionStart hook still works)

Ready to /clear. Next time you invoke /hello-claude --topic <topic>, you'll see this session's briefing.
Default resume picks the most recent standing for this project across all topics.

(Optional one-time setup: SessionStart hook for auto-resume — see end of SKILL.md.)
```

Do NOT run `/clear` yourself — that's a user-only command. Just signal readiness.

---

## RESUME mode (start of session)

Goal: in one short message, restore context so the user can dive back in without re-reading reports.

### Step 1 — Resolve which standing to read

Resolution order:

1. **`--topic <slug>` given** → pick the most recent `$standing_dir/*-<slug>.md`.
2. **`--list` given** → enumerate every file in `$standing_dir/` with timestamp, topic, and the first non-empty H2 / first 80 chars of body. Don't read or summarize any of them. The user then re-invokes with `--topic`.
3. **No flag** → pick the most recent file in `$standing_dir/` (sort by `<ts>` prefix in filename, take the last).
4. **`$standing_dir/` doesn't exist OR is empty** → fall back to legacy `$standing_pointer` (root STANDING.md). This is the unmigrated path and continues to work exactly as before.
5. **Neither exists OR is > 7 days old** → say so and skip to step 3.

Whichever standing file is selected, read it and proceed to Step 2 with its content.

### Step 2 — Output the briefing

Format:

```
☀️  Picking up <topic> from <relative time, e.g. "Friday evening">

## Last session
<3-5 lines from the selected standing's "what we did">

## Outstanding
<3-5 lines>

## Suggested next
<2-3 lines, plus optional question: "Start with X?">

(Full notes: ~/.claude/projects/<slug>/standing/<ts>-<topic>.md
 Other open topics: --list to see them all)
```

When falling back to the legacy root STANDING.md (unmigrated project), drop the "topic" word from the header and point at the root file:

```
☀️  Picking up from <relative time>
...
(Full notes: ~/.claude/projects/<slug>/STANDING.md — pre-migration layout)
```

### Step 3 — Read CLAUDE.md (silent — don't dump it)

Claude Code already auto-loads CLAUDE.md at session start, so you don't need to re-read it. But verify the file exists and matches what STANDING.md references.

### Step 4 — Offer a starting move

End with a question, not a statement. Examples:
- "Want to start on `<top-suggested-next>`?"
- "Anything change over the weekend, or should we pick up where we left off?"

Don't auto-execute the next step. The user decides.

---

## Optional — auto-load via SessionStart hook

If the user wants the briefing to appear automatically every new session (no need to type `/hello-claude`), they can add a hook to `~/.claude/settings.json` via the `update-config` skill:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "test -f ~/.claude/projects/$(pwd | sed 's:/:-:g')/STANDING.md && cat ~/.claude/projects/$(pwd | sed 's:/:-:g')/STANDING.md"
          }
        ]
      }
    ]
  }
}
```

This dumps STANDING.md's contents into the session's system context on every start, so Claude sees the briefing without the user typing anything. Suggest this setup once the first SAVE→/clear→RESUME cycle has succeeded — don't push it before the user has tried the manual flow.

---

## What this skill does NOT do

- **Run /clear itself** — that's a user-only command. The skill prepares for clear; the user triggers it.
- **Commit anything to git** — file writes stay local. The user controls when/whether to commit.
- **Auto-create memories without verification** — only writes memories for genuinely durable patterns, not session-specific noise.
- **Touch CLAUDE.md if the user's current session was very short / exploratory** — drift-only updates, don't add bloat.

---

## Common pitfalls

- **Don't dump the standing file verbatim in RESUME mode.** Summarize. The full file is one click away if the user wants detail.
- **Don't pre-summarize for `--list`.** That mode just enumerates available topics; the user picks one and then re-invokes with `--topic` to get the briefing.
- **Don't delete legacy STANDING.md.** The lazy migration copies it to `standing/legacy-<date>.md`; the root file then becomes a pointer with the latest content inlined. Two copies of the legacy content briefly co-exist, by design.
- **Don't write memories for ephemeral things.** "We worked on benchmarks today" is not a memory. "User prefers narrow-scope experiments" is.
- **Don't optimize CLAUDE.md every run.** If nothing changed in the session, leave it alone. Optimization isn't a virtue.
- **In RESUME mode, don't take action.** Just brief and ask. The user might want to do something completely different today.
