# Personal skills

Shared "skills" (reusable agent playbooks) for the coding agents on this
machine. Each skill is a folder with a `SKILL.md`. They're symlinked into every
agent's config so there's a single source of truth — edit the file here and all
agents see the change.

## Skills

| Skill | What it does |
|-------|--------------|
| [`jira`](jira/SKILL.md) | Work with Jira issues from the conversation — describe, create, update, comment, and transition (e.g. move to In Progress / Done). Uses a local Jira MCP, falling back to the REST API with configured credentials. |
| [`terraform`](terraform/SKILL.md) | Gated Terraform workflow — plan first, explain changes, flag destructive actions, and confirm before every apply. |
| [`write-log`](write-log/SKILL.md) | Draft a Jekyll engineering-log post from the current conversation (documentation + runbook). Writes to `ENG_LOG_DIR`. |
| [`write-post`](write-post/SKILL.md) | Draft a post for your personal Jekyll blog in your voice, following the blog's conventions. Writes to `BLOG_DIR`. |

## Layout

```
skills/
├── install.sh              # links every skill into all agents
├── skills.config.example   # template for your personal paths (committed)
├── skills.config           # your filled-in copy (gitignored)
├── <skill-name>/
│   ├── SKILL.md            # the skill (Claude reads this)
│   └── gemini-command.toml # optional: Gemini CLI /command wrapper
```

## Configuration (shareable, no hardcoded paths)

Skills that need personal locations (e.g. your blog or engineering-log dir) read
them from a small config file instead of hardcoding paths, so the repo works for
anyone who clones it:

```sh
cp skills.config.example skills.config   # then edit in your paths
```

`install.sh` links your `skills.config` to `~/.config/skills/config`, a fixed
location every skill reads at runtime (it falls back to asking you if a value is
missing). `skills.config` is gitignored; only the `.example` is committed.

Keys: `CLAUDE_HOMES` (install.sh — which Claude home(s) to link into; defaults to
`~/.claude`), `AUTHOR_NAME`, `ENG_LOG_DIR` (write-log), `BLOG_DIR` / `BLOG_NAME`
(write-post). The `jira` skill reads Jira credentials from environment variables
(`JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`) — keep secrets in your shell, not
in the config file.

Out of the box the installer targets just `~/.claude`. To mirror skills into more
than one home (e.g. a separate `~/.claude-personal`), set `CLAUDE_HOMES` (a bash
array) in your `skills.config` — that personal layout stays in your gitignored
config, not in the shared repo.

> `skills.config` is bash syntax. `install.sh` (a bash script) sources it, and
> the skills *read* it as text — nothing sources it from your interactive shell,
> so it works regardless of whether you use bash, zsh, or fish.

## Install / update

```sh
./install.sh
```

This links each skill into:

| Agent | Location | How |
|-------|----------|-----|
| Claude | `<home>/skills/<name>` for each `CLAUDE_HOMES` entry (default `~/.claude`) | symlink |
| Gemini CLI | `~/.gemini/commands/<name>.toml` | generated (if the skill has `gemini-command.toml`) |

The Gemini wrapper is **generated**, not symlinked: `install.sh` substitutes the
`__SKILL_MD__` placeholder with this machine's absolute `SKILL.md` path. That's
why the committed `gemini-command.toml` stays portable across clones — re-run
`./install.sh` after editing one.

Restart each agent afterward so it discovers new skills.

## Adding a skill

1. Make a folder `skills/<name>/` with a `SKILL.md` (YAML front matter: `name`,
   `description`, then the instructions).
2. Optional: add `gemini-command.toml` to expose it as `/<name>` in Gemini CLI.
   Use `@{__SKILL_MD__}` to inject the shared instructions (install.sh resolves
   the absolute path) and `{{args}}` for the user's input.
3. For any user-specific paths, add a key to `skills.config.example` and have the
   skill read it from `~/.config/skills/config` (fall back to asking). Don't
   hardcode personal paths in `SKILL.md`.
4. Run `./install.sh`.
