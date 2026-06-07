---
name: write-log
description: Create a Jekyll engineering log post for the user's work log (directory from config: ENG_LOG_DIR). Use when they say things like "write a log about X", "log what we did", "create a post for this work", "document this migration", "write up what happened", or "summarize this for the log". Derives content from the current conversation — no topic needed upfront.
---

# Write an engineering log post

This skill maintains a private Jekyll engineering log. These posts serve two purposes at once: **documentation** (what happened, why, what we found) and **runbook** (how to do it again or avoid the same pitfalls). They are thorough and technical — not a journal, not a blog post, not a PR description.

## Configuration

The log's `_posts` directory comes from your config. Read `~/.config/skills/config` and use **`ENG_LOG_DIR`**. If that file is missing or `ENG_LOG_DIR` is empty, ask the user for the path (and suggest they add it to `skills.config`). Use `$ENG_LOG_DIR` wherever a log path is referenced below.

## Step 1 — Read the existing posts for tone calibration

Before writing, read 1–2 recent posts from `$ENG_LOG_DIR` to calibrate structure and tone. The posts are technical, dense, and command-heavy. They explain root causes, not just symptoms.

## Step 2 — Derive content from the conversation

Do **not** ask the user to re-explain what was done — extract it from the current conversation context. Look for:

- **What was the goal?** The task or ticket being worked on.
- **Working context:** git branch, Terraform roots, config files, AWS accounts/profiles, regions, relevant file paths.
- **Steps taken:** ordered sequence of what was executed.
- **Blockers and fixes:** every error encountered, its root cause, and the exact fix. This is the most valuable part. If there was a workaround, note whether it's temporary.
- **Verification:** how success was confirmed (curl output, health checks, terraform plan, etc.).
- **Observations:** anything non-obvious that would help someone doing this again — timing notes, AWS service quirks, Terraform behavior, dependency traps.
- **Pending cleanup:** anything deliberately left undone, with why.

If critical context is genuinely missing (e.g., the conversation only shows the end of a session), ask one concise question rather than guessing — but don't make the user re-explain what's already in context.

## Step 3 — Write the post

**File path:**
```
$ENG_LOG_DIR/YYYY-MM-DD-slug.md
```

Use today's date. `slug` is kebab-case from the title. Check that a file with that name doesn't already exist before writing.

**Front matter:**
```yaml
---
layout: post
title: "Descriptive Title — Subtitle with Specifics"
date: YYYY-MM-DD
tags: [lowercase, specific, 4-to-8-tags]
---
```

Tags should reflect the actual tech stack: `terraform`, `aws`, `dns`, `route53`, `aurora`, `ecs`, `migration`, `qa`, `runbook`, `networking`, etc.

**Opening paragraph:** One or two sentences of plain context — what was being done and why. Then a quick-reference block for the key coordinates:

```
**Working directory:** `path/` on branch `branch-name`
**Terraform root:** `path/to/root`
**AWS profiles:** `profile-name` (account-id, purpose)
```

Omit lines that aren't relevant to the work.

**Section structure — use what applies, omit what doesn't:**

```
## Background / Why This Was Needed
## [Topic-specific context sections] (e.g. "Domain Map", "Architecture", "What We Found")
## Steps
### Step N — Name
## Blockers and Fixes
### N. Error Name (affected resource or domain)
## Verification
## Observations / What We Learned
## Pending Cleanup
```

**Blockers and fixes** get the most depth. For each one:
- **Symptom:** what the error message or behavior was
- **Root cause:** the actual underlying reason (not "it failed", but *why*)
- **Fix:** the exact commands or config changes, with code blocks

**Verification** ends with a results table:
```markdown
| Endpoint / Check | Result | Notes |
|---|---|---|
| `https://...` | **200 ✅** | ... |
```

**Pending cleanup** is a checklist:
```markdown
- [ ] Item with brief explanation
```

## Step 4 — Style

- **Technical and dense.** These are for engineers revisiting the work later. Every command, every ARN, every zone ID that matters — include it.
- **Explain root causes.** "The cert validation deadlocked because Terraform treats the module as a unit" is more useful than "cert validation timed out".
- **Commands in fenced code blocks** with the actual flags used, not a generic example.
- **Tables** for structured comparisons (old vs new, domain maps, before/after).
- **No padding.** If a section doesn't add information, omit it.
- **No AI disclosure line** — this is an internal engineering log, not a published blog post.

## Step 5 — After writing

Tell the user the file path and a one-line summary of what sections were included. Do **not** `git add`/commit/push unless they explicitly ask. If they ask, follow the repo's commit conventions.
