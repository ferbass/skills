# Personal skills

Shared "skills" (reusable agent playbooks) for the coding agents on this
machine. Each skill is a folder with a `SKILL.md`. They're symlinked into every
agent's config so there's a single source of truth — edit the file here and all
agents see the change.

## Skills

| Skill | What it does |
|-------|--------------|
| [`handoff`](handoff/SKILL.md) | Capture in-flight work into a project-local handoff doc (`.agents/handoffs/`) so another agent or a later session can pick it up — or resume from an existing handoff and continue. Derives state from the current conversation. |
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
│   ├── SKILL.md            # the skill (Claude, opencode and pi read this)
│   ├── bin/                # optional: helper scripts the skill calls
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
`~/.claude`), `AGENTS_SKILLS_DIR` / `OPENCODE_COMMANDS_DIR` (install.sh — the
opencode+pi targets; sensible defaults, rarely set), `AUTHOR_NAME`, `ENG_LOG_DIR`
(write-log), `BLOG_DIR` / `BLOG_NAME` (write-post). The `jira` skill reads Jira
credentials from environment variables (`JIRA_URL`, `JIRA_USERNAME`,
`JIRA_API_TOKEN`), or from an MCP `env`/`environment` block in your agent's own
config (Claude, opencode, Gemini, pi) — keep secrets in your shell or those
configs, not in `skills.config`.

Out of the box the installer targets just `~/.claude`. To mirror skills into more
than one home (e.g. a separate `~/.claude-personal`), set `CLAUDE_HOMES` (a bash
array) in your `skills.config` — that personal layout stays in your gitignored
config, not in the shared repo.

> `skills.config` is bash syntax. `install.sh` (a bash script) sources it, and
> the skills *read* it as text — nothing sources it from your interactive shell,
> so it works regardless of whether you use bash, zsh, or fish.

## Install / update

Run with no arguments for an interactive menu that lists each skill (with its
install status) and lets you install or remove them:

```sh
./install.sh
```

Or non-interactively:

```sh
./install.sh --list              # show skills and whether each is installed
./install.sh --all               # install every skill
./install.sh <name> [<name>...]  # install specific skill(s)
./install.sh --remove <name>...  # remove specific skill(s)
```

(With no TTY — e.g. piped — it falls back to installing everything.) Installing
links each skill into:

| Agent | Location | How |
|-------|----------|-----|
| Claude | `<home>/skills/<name>` for each `CLAUDE_HOMES` entry (default `~/.claude`) | symlink |
| opencode + pi | `~/.agents/skills/<name>` | symlink |
| opencode | `~/.config/opencode/command/<name>.md` | generated `/<name>` wrapper |
| Gemini CLI | `~/.gemini/commands/<name>.toml` | generated (if the skill has `gemini-command.toml`) |

**opencode and pi share one directory.** Both auto-discover
`~/.agents/skills/<name>/SKILL.md` with no config at all, so a single symlink
covers both. In pi each skill also becomes a `/skill:<name>` command; in opencode
the agent loads it through the `skill` tool, plus the generated `/<name>`
command. Verify what each one sees with `opencode debug skill` and, for pi,
`printf '{"type":"get_commands"}\n' | pi --mode rpc --no-session`.

opencode *also* auto-loads `~/.claude/skills/`, so with the default
`CLAUDE_HOMES` it finds each skill twice (both symlinks resolve to the same file,
so it just logs a duplicate-name warning). Set
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` if you'd rather it only read the shared
directory.

The Gemini and opencode wrappers are **generated**, not symlinked: `install.sh`
substitutes this machine's absolute `SKILL.md` path (Gemini via the
`__SKILL_MD__` placeholder in the committed `gemini-command.toml`; opencode from
the skill's front-matter description). That's what keeps the repo portable across
clones — re-run `./install.sh` after editing a skill's description or its
`gemini-command.toml`.

**Codex CLI** is *detected* (`HAS_CODEX`: `codex` on `PATH` or a `~/.codex`
directory), so a Codex-only machine is a valid install target. Generating the
Codex prompt files (`~/.codex/prompts/<name>.md`) is not wired up yet — detection
is the first step.

Restart each agent afterward so it discovers new skills.

## Adding a skill

1. Make a folder `skills/<name>/` with a `SKILL.md` (YAML front matter: `name`,
   `description`, then the instructions). `name` must be lowercase
   `a-z0-9-`, match the folder, and the front matter must be **strict YAML** —
   opencode and pi parse it strictly and silently skip a skill they can't read.
   In particular an unquoted `description` may not contain `": "` (quote the
   value or reword); Claude Code is lenient about this and will hide the bug.
2. Optional: add `gemini-command.toml` to expose it as `/<name>` in Gemini CLI.
   Use `@{__SKILL_MD__}` to inject the shared instructions (install.sh resolves
   the absolute path) and `{{args}}` for the user's input. The opencode `/<name>`
   command is generated automatically — no per-skill file needed.
3. Keep the instructions harness-neutral: no `~/.claude/...` paths, no
   Claude-only tool names. Reference bundled helpers by their path *relative to
   the skill directory* (`bin/foo.sh`) — every harness tells the agent where the
   skill was loaded from.
4. For any user-specific paths, add a key to `skills.config.example` and have the
   skill read it from `~/.config/skills/config` (fall back to asking). Don't
   hardcode personal paths in `SKILL.md`.
5. Run `./install.sh`.
