---
name: handoff
description: Capture the state of ongoing work into a handoff document so another agent (or a later session) can pick it up, or resume from an existing handoff. Use when the user says things like "hand this off", "write a handoff", "pause and save context for later", "I'm out of context — checkpoint this", "create a handoff doc", or "resume the handoff", "continue from the handoff", "pick up where we left off". Derives content from the current conversation — no summary needed upfront.
---

# Hand off ongoing work

This skill bridges two agents (or two sessions) working on the same task. It has **two modes**:

- **Create** — distill the current, in-flight work into a handoff document a *cold* agent can act on without re-reading the whole conversation.
- **Resume** — find an existing handoff, load it, and continue the work from where it left off.

Pick the mode from the user's phrasing. "Hand this off / checkpoint this / save for later" → **Create**. "Resume / continue / pick up the handoff" → **Resume**. If genuinely ambiguous, ask which.

A handoff is a **runbook for the next agent**, not a status report for a human. Write it for someone who has the repo but none of the conversation. Be concrete: real paths, real commands, real branch names — never "the file we changed" or "run the tests".

## Where handoffs live

Project-local, in the current repo:

```
.claude/handoffs/YYYY-MM-DD-slug.md
```

`slug` is kebab-case from the task. Using `.claude/handoffs/` keeps the handoff next to the code it describes, so another agent working in the same repo discovers it naturally. Create the directory if it doesn't exist.

---

## Mode: Create

### Step 1 — Derive state from the conversation

Do **not** ask the user to re-explain. Extract from the current context:

- **Goal** — the task/ticket and its definition of done. What does "finished" look like?
- **Status** — what is *done*, what is *in progress* (and how far), what is *not started*. Be honest about half-finished work.
- **Next steps** — an ordered, concrete to-do list. Each item actionable on its own: the file to edit, the command to run, the thing to verify.
- **Working context** — git branch, key file paths (with line numbers where it matters), commands already run, env vars / profiles / services in play, any running background processes.
- **Decisions & rationale** — choices already made and *why*, so the next agent doesn't relitigate them or undo them by accident.
- **Blockers & open questions** — what's stuck, what's unknown, what's waiting on the user or an external system.
- **How to verify** — the exact command(s) that confirm the work is correct (test command, curl, build), and current pass/fail state.
- **Do NOT touch** — anything deliberately left as-is, with why.

If the conversation only shows the tail end of a session and critical context is missing, ask **one** concise question rather than guessing.

### Step 2 — Confirm uncommitted state

Run `git status --short` and `git branch --show-current` so the handoff records the real working-tree state (staged, unstaged, untracked) and branch. A handoff that omits uncommitted changes strands the next agent.

### Step 3 — Write the handoff

Path: `.claude/handoffs/YYYY-MM-DD-slug.md` (today's date; check the name is free first).

Front matter:
```yaml
---
task: "One-line description of the work"
date: YYYY-MM-DD
branch: branch-name
status: in-progress | blocked | ready-for-review
---
```

Body — use what applies, omit empty sections:

```
# Handoff: <task>

## Goal
What we're trying to achieve and what "done" means.

## Current status
What's done / in progress / not started. One honest paragraph or a checklist.

## Working context
- **Branch:** `branch-name`
- **Key files:** `path/to/file.ext:line` — what it is / what changed
- **Uncommitted changes:** output of `git status --short`, or "none"
- **Commands run:** the ones that matter
- **Environment:** profiles, env vars, services, background processes

## Next steps
1. Concrete, ordered, actionable. File + command + expected result.
2. ...

## Decisions made
- **Chose X over Y** because … (so the next agent doesn't undo it)

## Blockers & open questions
- What's stuck or unknown; what's waiting on the user/external system.

## How to verify
Exact command(s) to confirm correctness, and current state (passing/failing).

## Do not touch
- Things intentionally left alone, and why.
```

### Step 4 — After writing

Tell the user the file path and a one-line summary of what's captured. Mention they can resume in another session/agent with "resume the handoff". Do **not** `git add`/commit unless asked — but note the handoff itself is now an untracked file.

---

## Mode: Resume

### Step 1 — Locate the handoff

If the user named one, use it. Otherwise list `.claude/handoffs/` and pick the most recent (by date in filename / mtime). If several look plausible, show the candidates and ask. If the directory is empty or missing, say so — there's nothing to resume.

### Step 2 — Load and re-establish context

Read the handoff in full. Then **reconcile it with reality** before acting — a handoff reflects the moment it was written:

- `git branch --show-current` and `git status --short` — are you on the expected branch? Does the working tree match what the handoff described?
- Spot-check the **key files** it lists still exist and look as described (line numbers drift).
- Note anything that diverged (commits landed, files moved, branch changed) — surface it instead of trusting the doc blindly.

### Step 3 — Orient, then continue

Give the user a short orientation: the goal, what's done, and the **next step** you're about to take from the handoff's list. Then proceed with that next step. Don't re-do completed work; don't reverse the recorded decisions without flagging it.

### Step 4 — Keep the handoff current (optional)

If the resumed session makes meaningful progress and the user wants to hand off again, update the same file (or write a new dated one) rather than leaving a stale doc behind.
