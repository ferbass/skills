---
name: write-post
description: Help Fernando write a post for his personal blog (ferbass.xyz, a Jekyll site). Use when he says things like "start a post about X", "write a post on Y", "draft a blog post", or "let's blog about Z". Gathers any missing context first, then drafts in his voice following the blog's conventions.
---

# Write a blog post for ferbass.xyz

This is Fernando's personal Jekyll blog. When he asks to start/write a post,
your job is to gather just enough context, then draft a complete post in his
voice that follows the conventions below. Default to saving a **draft for his
review** — never publish or push without being told.

## Step 1 — Gather context (ask only what's missing)

Fernando usually opens with the topic ("start a post about my new tmux setup").
If he's given enough to work with, just start. If key things are unclear, ask
them in ONE short round of questions (don't interrogate) — use whatever question
UI your tool offers, or just ask in plain text. The things worth knowing, in
priority order:

1. **Angle / takeaway** — what's the one thing a reader should leave with? What
   made him want to write it?
2. **Key points & specifics** — commands, config, code, links, numbers, or a
   concrete example/story he wants included. Ask if he has notes to paste.
3. **Depth / length** — quick note, standard post, or deep dive.
4. **Publish plan** — draft only (default), or schedule it? If scheduling, what
   date? He typically targets a **Friday** and future-dates it (see below).
5. **Images** — any screenshots/diagrams to include?

Skip questions he already answered. When in doubt about facts (versions, exact
commands, file paths), check the repo or ask rather than inventing.

## Step 2 — Draft it

**File location**

The blog repo lives at `/Users/ferbass/Workspace/personal/ferbass.xyz`. Write
the post under that path, in either `_drafts` or `_posts`:
- Draft (default): `/Users/ferbass/Workspace/personal/ferbass.xyz/_drafts/YYYY-MM-DD-slug.md`
- Scheduled/publish: `/Users/ferbass/Workspace/personal/ferbass.xyz/_posts/YYYY-MM-DD-slug.md`

`slug` is kebab-case from the title. The date prefix and the `date:` field must
match.

**Front matter** (match existing posts exactly):
```yaml
---
layout: post
title: "Title in Title Case"
date: YYYY-MM-DD
categories: [lowercase, one-or-two]
tags: [lowercase, hyphenated-ok, 4-to-6]
---
```
- `categories`: 1-2 broad buckets. `tags`: 4-6 specific terms. Both lowercase,
  bracketed list style.
- Do **not** add an `audio:` field (that's the podcast pipeline's job, and it's
  currently disabled).

**Scheduling**: posts go live via a daily midnight-UTC CI build, so a
future-dated post simply appears on its date — no extra step. To schedule for a
date, set both the filename prefix and `date:` to that date and put it in
`_posts/`. Future-dated posts won't show in a normal build (need `--future`).

**Images**: store under `img/posts/<slug>/`. Reference with markdown
`![alt text](/img/posts/<slug>/file.png)`, or an `<img ... width=...>` tag when
you need to control size. Always write real alt text.

**Ending**: close with a short takeaway paragraph, then a horizontal rule and
the AI disclosure line, exactly:
```
---

_This post was written with the help of AI (Claude by Anthropic)._
```

## Step 3 — Voice & style

Write like Fernando, not like a tech-docs site:

- **First person, conversational, honest.** Open with a hook or personal framing
  ("I do have Pixelmator on my Mac, but...", "If you run a Plex server, you know
  the struggle..."). He's direct and willing to be opinionated.
- **Practical and concrete.** Real commands in fenced code blocks, real numbers,
  a worked example. Show, don't just tell. Explain the *why*, not only the *how*.
- **Warm, with light humor** — never corporate filler, never padding. If a
  section isn't earning its place, cut it.
- **Accessible but technical.** Define jargon briefly the first time; respect
  that the reader is smart.
- **Structure** with `##` section headings. Short paragraphs. Prose over bullet
  walls, but bullets/tables where they genuinely help.
- Match the length to the topic. A 7-min read is a deep dive; many of his posts
  are tighter. Don't inflate.

Read 1-2 recent posts in `_posts/` first if you need to recalibrate the voice.

## Step 4 — After drafting

- Tell him where you saved it and give a quick summary of structure/length.
- If you want to verify it builds, do a **throwaway build to a temp dir** —
  `bundle exec jekyll build [--drafts] [--future] -d /tmp/_site_check` — and
  never run a dev server or touch `_site` (he keeps a server running).
- Iterate on his feedback. **Do not `git add`/commit/push until he explicitly
  asks.** When he does, follow the repo's commit conventions.
