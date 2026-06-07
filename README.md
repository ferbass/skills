# Personal skills

Shared "skills" (reusable agent playbooks) for the coding agents on this
machine. Each skill is a folder with a `SKILL.md`. They're symlinked into every
agent's config so there's a single source of truth — edit the file here and all
agents see the change.

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

Keys: `AUTHOR_NAME`, `ENG_LOG_DIR` (write-log), `BLOG_DIR` / `BLOG_NAME`
(write-post). The `jira` skill reads Jira credentials from environment variables
(`JIRA_URL`, `JIRA_USERNAME`, `JIRA_API_TOKEN`) — keep secrets in your shell, not
in the config file.

## Install / update

```sh
./install.sh
```

This links each skill into:

| Agent | Location | How |
|-------|----------|-----|
| `claude` | `~/.claude/skills/<name>` | symlink |
| `claude-personal` | `~/.claude-personal/skills/<name>` | symlink |
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
