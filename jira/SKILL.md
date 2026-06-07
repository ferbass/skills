---
name: jira
description: Work with Jira issues from the conversation — describe (read), create, update, comment, and transition (e.g. move to In Progress / Done). Uses the connected local Jira MCP, or falls back to the Jira REST API with configured credentials; only writes a markdown file if the user explicitly asks. Use when the user says things like "create a jira for this", "show me PROJ-123", "update that ticket", "comment on PROJ-123", "move it to in progress", or "mark it done".
---

# Work with Jira

This skill handles the common Jira operations driven from the current
conversation. Every operation runs through one of two **backends** (see
"Backend selection" below): the **Jira MCP** if connected, otherwise the **Jira
REST API** using configured credentials. The per-operation steps (D/C/U/M/T)
describe *what* to do; the backend section describes *how* to execute it.

## Step 0 — Figure out the operation

From what the user asked, pick one:

| Intent | Examples | Section |
|---|---|---|
| **describe** | "show me PROJ-123", "what's in that ticket" | Step D |
| **create** | "create a jira for this", "file a ticket" | Step C |
| **update** | "update PROJ-123", "change the description / fields" | Step U |
| **comment** | "comment on PROJ-123 with…", "add a note" | Step M |
| **transition** | "move it to in progress", "mark it done" | Step T |

If the intent is ambiguous, ask one short question. For any operation on an
existing issue, you need the **issue key** (e.g. `PROJ-123`); if it's not given
and can't be inferred from context, ask for it (search via the active backend if
needed).

For any **outward-facing change** (create, update, comment, transition), show
the user a short preview and get their confirmation before calling the backend.
Reading (describe) needs no confirmation.

---

## Backend selection

Pick the backend in this order:

1. **Jira MCP (preferred).** Check your tools for a Jira MCP — `mcp-atlassian`,
   typically registered as `jira`, exposing tools like `jira_get_issue`,
   `jira_create_issue`, `jira_update_issue`, `jira_add_comment`,
   `jira_get_transitions`, `jira_transition_issue` (often namespaced as
   `mcp__jira__jira_create_issue`). If present, use it.
2. **Jira REST API (fallback).** If no MCP, use the REST API with configured
   credentials from the environment:
   - `JIRA_URL` — site base, e.g. `https://your-site.atlassian.net`
   - `JIRA_USERNAME` — account email (Jira Cloud)
   - `JIRA_API_TOKEN` — API token
   Authenticate with HTTP Basic (`-u "$JIRA_USERNAME:$JIRA_API_TOKEN"`). Run calls
   with `curl` via Bash. Confirm the vars are set first (`printenv JIRA_URL` etc.)
   — never echo the token. If they're missing, tell the user which to set and stop.
3. **Markdown — only if explicitly asked.** Never write a file as an automatic
   fallback; only when the user says so (e.g. "just make a markdown file"). See the
   markdown note in Step C.

If neither MCP nor REST credentials are available, say so plainly and stop.

### REST API recipes (Cloud)

Use the `/rest/api/2` endpoints — `description`/comment bodies are plain strings
(wiki markup), which avoids the ADF JSON that `/rest/api/3` requires. Pipe JSON
responses through `jq` to extract fields.

```bash
BASE="$JIRA_URL/rest/api/2"
AUTH=(-u "$JIRA_USERNAME:$JIRA_API_TOKEN" -H "Content-Type: application/json")

# Describe
curl -s "${AUTH[@]}" "$BASE/issue/PROJ-123"

# Create  (body via a heredoc/file to keep multiline description intact)
curl -s "${AUTH[@]}" -X POST "$BASE/issue" -d '{
  "fields": {
    "project": {"key": "PROJ"},
    "issuetype": {"name": "Task"},
    "summary": "…",
    "description": "…",
    "labels": ["…"],
    "priority": {"name": "High"}
  }
}'

# Update
curl -s "${AUTH[@]}" -X PUT "$BASE/issue/PROJ-123" -d '{"fields": {"summary": "…"}}'

# Comment
curl -s "${AUTH[@]}" -X POST "$BASE/issue/PROJ-123/comment" -d '{"body": "…"}'

# Transitions: list, then apply by id
curl -s "${AUTH[@]}" "$BASE/issue/PROJ-123/transitions"
curl -s "${AUTH[@]}" -X POST "$BASE/issue/PROJ-123/transitions" -d '{"transition": {"id": "31"}}'

# Search (find an issue key)
curl -s "${AUTH[@]}" --get "$BASE/search" --data-urlencode 'jql=…' --data-urlencode 'maxResults=10'
```

The issue URL to report back is `$JIRA_URL/browse/<KEY>`.

---

## Step D — Describe (read) an issue

Get the issue via the active backend and summarize: **key, summary, type, status,
assignee, priority**, then the description and most recent comments. Surface
linked issues and current available transitions if useful. Keep it tight — lead
with status and summary, expand only what's relevant to why they're looking.

---

## Step C — Create an issue

This is the most involved operation. Craft a genuinely good ticket, don't just
dump the conversation.

### C1 — Derive content from context

Extract from the conversation (don't make the user re-explain):

- **The problem / trigger** — what's broken, missing, or requested. Lead with
  user-visible or business impact, not internals.
- **Investigation findings** — root cause, affected components, file paths, error
  messages, logs, repro steps.
- **Scope** — what's in and, explicitly, what's out.
- **Goals / desired outcome** — what "done" looks like, concretely.
- **Constraints & dependencies** — blockers, related tickets, required access.

Ask a question only if something essential is missing (e.g. you can't tell the
type, or there's no inferable acceptance criteria).

### C2 — Decide the shape

Infer the **issue type**: **Bug** (broken behavior), **Task** (discrete work),
**Story** (user-facing capability), **Spike** (time-boxed research). Infer a
**priority** (Low / Medium / High / Critical) from impact; note in one line why
if High+.

### C3 — Body structure

Use what applies, omit what doesn't:

```markdown
# <Summary — imperative, specific, fits on one line>

## Problem
Plain-language statement of what's wrong or needed and who it affects. Lead with impact.

## Context / Investigation
What we already know. Root cause if found, affected components, file paths, error
output, repro steps. Code blocks for logs/commands; tables for comparisons.

## Goals
What success looks like — concrete and testable.

## Acceptance Criteria
- [ ] Specific, verifiable condition
- [ ] Another condition

## Out of Scope
- Things deliberately excluded so the ticket doesn't sprawl.

## Dependencies / Notes
Blockers, related tickets, required access, links.
```

For a **Bug**, include **Steps to Reproduce**, **Expected**, **Actual**. For a
**Spike**, replace Acceptance Criteria with **Questions to Answer** + a time-box.

### C4 — Output (via the active backend)

Create the issue through the MCP or REST API (see Backend selection):

1. **Determine the project key.** If not obvious from context, ask (or list
   projects via the backend). Don't guess a project key.
2. Map fields: `summary` ← the summary line; `issuetype` ← inferred type (fall
   back to `Task` if the project lacks it); `description` ← the body above. Add
   `labels`, `priority`, `components` if accepted and relevant; skip rejected
   fields rather than failing. (MCP: `mcp-atlassian` converts the markdown body;
   REST `/rest/api/2`: pass the body as a plain wiki-markup string.)
3. **Confirm** project key, type, summary, and a short preview with the user, then
   create.
4. Report the created **issue key and URL**. If the call fails, report the error
   and let the user decide how to proceed — do **not** silently write markdown.

**Markdown — only on explicit request.** If the user asks for a file instead of a
real ticket, write `./jira-<slug>.md` (kebab-case slug from the summary; use a
folder they name; don't overwrite an existing file) with reference front matter:

```yaml
---
type: Bug | Task | Story | Spike
priority: Low | Medium | High | Critical
labels: [lowercase, relevant, labels]
components: [affected-area]
---
```

Then report the file path and note it's ready to paste into Jira.

---

## Step U — Update an issue

1. Get the issue first (Step D) so you're editing real current values.
2. Determine which fields change — summary, description, labels, priority,
   components, assignee, etc. When rewriting the description, preserve the
   existing structure (C3) rather than flattening it.
3. **Confirm the diff** (field: old → new) with the user, then update via the
   active backend. Skip fields the project rejects.
4. Report what changed and the issue URL.

---

## Step M — Comment on an issue

1. Draft the comment from context — concise and self-contained (someone reading
   only the comment should understand it). Use code blocks for logs/commands.
2. **Show the comment text** and confirm, then add it via the active backend.
3. Report success and the issue URL.

---

## Step T — Transition status (e.g. In Progress / Done)

Status names are project-specific, so resolve them dynamically:

1. Get the **available transitions** and their IDs for the issue from its current
   status via the active backend.
2. Match the user's intent to a transition by name (case-insensitive, fuzzy):
   "in progress" → e.g. *In Progress / Start Progress*; "done" → e.g.
   *Done / Resolve / Close*. If several plausibly match, ask which.
3. **Confirm** the chosen transition, then apply it via the active backend using
   that transition ID. If the target requires fields (e.g. a resolution on Done),
   provide or ask for them.
4. Report the new status and the issue URL.

---

## Style (applies to create / update / comment)

- **Summaries are real Jira summaries:** imperative and specific ("Fix N+1 query
  on dashboard load", not "Dashboard slow").
- **Concrete over vague.** Reference actual files, functions, endpoints, and
  error messages from the investigation.
- **Acceptance criteria are testable** — checkable as done/not done, no "improve".
- **No padding.** Omit any section that adds nothing.
- **Self-contained.** Understandable without the originating conversation.

## After any operation

Report the outcome with the **issue key + URL** (or file path, if the user
explicitly asked for markdown) and a one-line summary. Do **not** `git add`/commit
unless asked.
