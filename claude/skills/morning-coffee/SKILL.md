---
name: morning-coffee
description: >
  Generate a one-shot morning briefing — today's calendar, open loops from
  yesterday (emails awaiting reply + Gemini meeting notes from Google Meet),
  the week ahead, today's weather, and one rotating news topic. Spawns 5
  subagents in parallel; targets <30s wall-clock. Trigger:
  "/morning-coffee", "morning coffee", "morning briefing", "what's on today",
  "give me my morning", "start my day". Optional args: --location <city>,
  --news <topic>, --skip <a,b>, --format plain, --save. MCPs: Google
  Calendar, Gmail, Google Drive (Drive is used to read Meet's Gemini-generated
  meeting notes Docs). Falls back gracefully when MCPs aren't authenticated.
  Local AI-news agent at
  /Users/juan-garassino/Code/002-engenious/fetch_learning_resources.
---

# morning-coffee — daily briefing in one shot

Fans out to five parallel subagents and synthesizes one tight briefing. Designed
for the 30 seconds while coffee brews.

---

## Step 1 — Compute the shared context (orchestrator does this ONCE)

Subagents start fresh and don't know today's date or the user's preferences.
Compute these values yourself, then embed them in each subagent prompt as
literal strings (don't pass `<TODAY>` placeholders).

| Variable | How to compute |
|---|---|
| `TODAY_ISO` | Today's date in local TZ, e.g. `2026-05-08`. Run `date +%Y-%m-%d` in Bash if unsure. |
| `YESTERDAY_ISO` | TODAY_ISO − 1 day |
| `WEEK_END_ISO` | TODAY_ISO + 7 days |
| `WEEKDAY` | 0=Mon … 6=Sun |
| `LOCATION` | From `--location`, else preferences, else `""` (let wttr.in geoip) |
| `NEWS_TOPIC` | From `--news`, else preferences, else `WEEKDAY_NEWS_ROTATION[WEEKDAY]` |
| `SKIP` | Set from `--skip a,b`, else preferences, else empty |
| `FORMAT` | From `--format`, else preferences, else `emoji` |
| `NAME` | From preferences, else `""` |

```
WEEKDAY_NEWS_ROTATION = {
  0: "engineering", 1: "backend", 2: "marketing",
  3: "devops",      4: "ai-foundations",
  5: "ai-foundations", 6: "ai-foundations",   # weekends: stay light
}
```

---

## Step 2 — Read preferences (one Read call, ignore if missing)

Try to read `~/.claude/skills/morning-coffee/preferences.md`. If it exists,
parse simple `key: value` lines:

```
name: Juan
location: Berlin
news_topic: marketing
skip: news, week
format: plain
weekend: skip            # 'skip' = no briefing on Sat/Sun
```

CLI args override preferences. If the file doesn't exist, use defaults from
Step 1 — don't error.

---

## Step 3 — Spawn FIVE subagents in ONE message (parallel)

All `subagent_type=general-purpose`. Skip a subagent if its section name is in
SKIP. Use the prompts below verbatim — substitute `{TODAY_ISO}`,
`{YESTERDAY_ISO}`, `{WEEK_END_ISO}`, `{LOCATION}`, `{NEWS_TOPIC}` with the
real computed values before sending.

### `calendar-today`
> Use the Google Calendar MCP. Discover the right tools via ToolSearch with
> query `"google calendar events list"`. List events on the user's primary
> calendar between {TODAY_ISO} 00:00 and {TODAY_ISO} 23:59 local time.
> One line per event: `HH:MM  TITLE · N attendees · location-or-link`.
> Sort chronologically. If the MCP needs auth, return the auth URL once and
> stop. Hard cap: 200 words. Hard cap: 25s wall-clock.

### `open-loops`
> Three parallel queries — Gemini meeting notes first, then email replies, then uncovered meetings:
>
> (a) **Gemini meeting notes — Drive (preferred).** Load via ToolSearch:
> `"select:mcp__claude_ai_Google_Drive__search_files,mcp__claude_ai_Google_Drive__read_file_content"`.
> Search Drive for Meet's Gemini-generated notes Docs created since
> {YESTERDAY_ISO}. Try queries: `name contains "Notes by Gemini"`,
> `name contains "Meeting notes"`, `fullText contains "Notes by Gemini"`,
> mimeType `application/vnd.google-apps.document`. For up to 3 matches, read
> content and extract: meeting title, attendees, top 3 action items
> (especially mine), explicit decisions. These are the canonical record of
> yesterday's meetings — Gemini listened, you don't have to remember.
>
> **EXCLUSION (security):** SKIP any Doc whose name (case-insensitive) contains
> any of: `credential`, `credentials`, `password`, `secret`, `secrets`,
> `token`, `api key`, `apikey`, `private key`, `.env`, `vault`. These are
> likely to contain plaintext secrets and must not be ingested into the
> briefing. If you encounter one in the search results, do NOT call
> `read_file_content` on it; instead, just note `(skipped: <filename> —
> looks like a credentials doc; consider rotating + moving to a secrets
> manager)` once at the end of the open-loops section.
>
> (a-fallback) **Gemini meeting notes — Gmail.** If Drive search returns
> nothing, ToolSearch `"select:mcp__claude_ai_Gmail__search_threads"` and
> search: `after:{YESTERDAY_ISO} (from:meet-recordings-noreply@google.com OR
> subject:"Notes by Gemini")`. Same extraction.
>
> (b) **Gmail — replies owed.** ToolSearch
> `"select:mcp__claude_ai_Gmail__search_threads,mcp__claude_ai_Gmail__get_thread"`.
> Search threads after:{YESTERDAY_ISO} where the LAST message is from someone
> other than me. Inspect the most recent ~15, surface real asks/questions
> awaiting a reply. Exclude newsletters and notifications.
>
> (c) **Calendar — uncovered meetings.** ToolSearch
> `"select:mcp__claude_ai_Google_Calendar__list_events"`. list_events for
> {YESTERDAY_ISO} on the primary calendar. Filter to events with ≥1 external
> attendee NOT already covered by (a)/(a-fallback). Surface commitments from
> descriptions/notes if any.
>
> Merge into max 10 bullets, urgency-ordered, format:
> `• [gemini|gmail|cal] what's owed → who/by when (if known)`
>
> If a Gemini notes Doc is long, distill to 2-3 lines. Don't paste raw bullets.
>
> Hard cap: 320 words. Hard cap: 25s wall-clock.

### `meetings-upcoming`
> Use Google Calendar MCP. List events from {TODAY_ISO} + 1 day through
> {WEEK_END_ISO} on the user's primary calendar. Surface only the noteworthy:
>
> - meetings with new external attendees
> - meetings >60 min
> - meetings with empty agenda/description
> - back-to-back stacks of >3 meetings
>
> Skip routine recurring blocks (standups, focus time, lunch). Max 6 bullets:
> `• Day HH:MM  TITLE — flag`. Hard cap: 200 words. Hard cap: 25s.

### `weather-today`
> WebFetch `https://wttr.in/{LOCATION}?format=j1` (URL-encode the location; if
> LOCATION is empty, fetch `https://wttr.in/?format=j1` to use geoip).
> Return: condition, high/low °C, precipitation %, wind km/h, one-line
> outlook. If the JSON endpoint fails, fall back to
> `https://wttr.in/{LOCATION}?format=3` (single-line text). If that also
> fails, return `"Weather unavailable"`. Hard cap: 60 words. Hard cap: 10s.

### `news-today`
> Run the user's local AI-news agent for the `{NEWS_TOPIC}` topic via Bash:
>
> ```
> cd /Users/juan-garassino/Code/002-engenious/fetch_learning_resources && \
> .venv/bin/python -m fetch_learning_resources \
>   --topic {NEWS_TOPIC} --target-count 3 --score-threshold 7 \
>   --max-iterations 5 --dry-run -v 2>&1 | tail -40
> ```
>
> Parse the `[{NEWS_TOPIC}]` lines (each item: score, title, then `→` reason
> + URL on next lines).
>
> Fallback chain if the project path doesn't exist OR the agent errors (e.g.
> no `OPENAI_API_KEY` in its `.env`):
>   1. WebFetch `https://hnrss.org/frontpage`, pick 3 items whose titles
>      match `{NEWS_TOPIC}` keywords, return those.
>   2. If that fails too: return `"News unavailable"`.
>
> Output 3 bullets: `• TITLE — one-line take — <url>`. Hard cap: 200 words.
> Hard cap: 30s.

---

## Step 4 — Synthesize

When all five return (or after 30s wall-clock, whichever is first), produce
ONE briefing using the layout below. Hard rules:

- Each section ≤ 6 lines.
- No line > 100 chars.
- Drop attendee counts on routine 1:1s.
- If a subagent failed or timed out: keep the header, write `(unavailable: <reason>)`.
- If the user has `name` in preferences, prepend `Good morning, {name}.` once.

**Default format (`emoji`):**

```
☕ Morning briefing — {weekday}, {Month D, YYYY}

🌤  Weather
{weather one-liner}

📅  Today
{calendar bullets, chronological}

🪞  Open loops & meeting takeaways
{merged email-replies + AI-meeting-summaries + uncovered-meeting-followups, urgency-ordered}

🔭  Week ahead
{upcoming highlights}

📰  AI today ({NEWS_TOPIC})
{3 news bullets}
```

**Plain format (`format: plain`):** drop the emojis; use `==` and `--` underlines
for the headers; same layout otherwise.

---

## Step 5 — Memory write-back (light touch)

After synthesizing, if you observed something durable about the user (e.g.
they have repeatedly run with `--skip news`, or said "too long" last time),
append a one-line note to `~/.claude/skills/morning-coffee/preferences.md`
under a `# learned` header. Never overwrite their explicit preferences.

If `--save` was passed with this run, persist the relevant args
(`--location`, `--news`, `--skip`, `--format`) to preferences.md.

---

## Args reference

| Arg | Effect |
|---|---|
| `--location <city>` | Override LOCATION for this run (e.g. `--location Berlin`, `--location "New York"`) |
| `--news <topic>` | Override NEWS_TOPIC. One of: `ai-foundations`, `hr`, `marketing`, `engineering`, `backend`, `frontend`, `devops` |
| `--skip <a,b,c>` | Skip sections — any of: `weather`, `today`, `open-loops`, `week`, `news` |
| `--format <emoji\|plain>` | Output styling |
| `--save` | Persist provided args as preferences |
| `--refresh <section>` | Only re-run one section (use after a normal briefing to update one part) |

Examples:
- `/morning-coffee` — full briefing with rotation
- `/morning-coffee --location Berlin --news engineering`
- `/morning-coffee --skip news,week`
- `/morning-coffee --location Berlin --save` (sets it forever)
- `/morning-coffee --refresh weather` (just refreshes weather)

---

## When NOT to invoke

- User is mid-task on something else and only mentions "morning" or "weather"
  in passing — don't take over.
- A briefing already ran in this session — offer `--refresh <section>`
  instead of re-running everything.
- It's Sat/Sun AND `weekend: skip` is in preferences — say one line and stop.

---

## Daily auto-run

Set this up once, then it runs every weekday morning:

```
/schedule "0 8 * * 1-5" /morning-coffee
```

For one-off polling instead: `/loop 24h /morning-coffee`. The `schedule` skill
is more durable (doesn't need a live CLI session); `loop` is fine for testing.

---

## Failure-mode matrix

| Symptom | Action |
|---|---|
| One subagent times out at 25s | Proceed with partial briefing; mark that section `(unavailable: timeout)` |
| Google MCP needs OAuth | Surface the auth URL once at top of briefing; show whatever else worked |
| News agent project missing or no `OPENAI_API_KEY` | Fall back to HN RSS as instructed |
| `wttr.in` is down or no location resolved | Show `Weather unavailable`, continue |
| All 5 subagents fail | Single line: `Briefing unavailable — check MCPs and project setup.` Don't fabricate. |
| `--skip news` set | Don't spawn news-today at all (saves ~25s) |

---

## Performance budget

- Bounded by `news-today` (~25s — the AI-news agent runs an LLM loop)
- Calendar / Gmail / Weather subagents: ~2–5s each
- Synthesis: ~3s
- **Wall-clock target: <30s** (parallel; sequential would be ~50s)
- If repeatedly exceeding, suggest the user add `skip: news` to preferences
  and surface news on demand instead.
