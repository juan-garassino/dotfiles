---
name: docs-current-protocol
description: Every plan must keep CLAUDE.md, DOCS.md, README.md current. Loaded at SessionStart — always active.
---

# Docs-current protocol

When you create a plan that touches code, scripts, configs, or skills, the plan MUST include a final "Docs to update" step that lists exactly which of CLAUDE.md / DOCS.md / README.md need a surgical edit, and what the edit is.

## Rules

1. **Every implementation plan ends with a Docs-to-update section.** If the answer is "none", say so explicitly with one sentence why (e.g. "no doc impact — internal refactor of a single private helper").

2. **Be surgical.** Name the file + the section heading + a one-line description of the edit. Do not rewrite wholesale.

3. **Add new things, update drifted things, prune wrong things.** Do not add speculative or forward-looking content.

4. **Touch CLAUDE.md when**: new scripts/commands, new conventions, new file paths, renamed/moved/deleted artifacts, changed env vars, new skills.

5. **Touch README.md when**: install/setup/run instructions change, public CLI changes, project-level "what is this" changes.

6. **Touch DOCS.md when**: it exists and any internal/architectural reference it carries has drifted. If no DOCS.md exists, do not create one speculatively.

7. **Execute doc edits as part of the implementation, not after.** Doc edits go in the same PR/commit as the code change — not as a follow-up.

## When this rule does NOT apply

- Questions/exploration tasks with no code change.
- Pure debugging investigations that end in no code change.
- Trivial fixes the user explicitly scopes as "no docs needed".
