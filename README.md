# Personal skills

Shared "skills" (reusable agent playbooks) for the coding agents on this
machine. Each skill is a folder with a `SKILL.md`. They're symlinked into every
agent's config so there's a single source of truth — edit the file here and all
agents see the change.

## Layout

```
skills/
├── install.sh              # symlinks every skill into all agents
├── <skill-name>/
│   ├── SKILL.md            # the skill (Claude reads this)
│   └── gemini-command.toml # optional: Gemini CLI /command wrapper
```

## Install / update

```sh
./install.sh
```

This links each skill into:

| Agent | Location |
|-------|----------|
| `claude` | `~/.claude/skills/<name>` |
| `claude-personal` | `~/.claude-personal/skills/<name>` |
| Gemini CLI | `~/.gemini/commands/<name>.toml` (if the skill has `gemini-command.toml`) |

Restart each agent afterward so it discovers new skills.

## Adding a skill

1. Make a folder `skills/<name>/` with a `SKILL.md` (YAML front matter: `name`,
   `description`, then the instructions).
2. Optional: add `gemini-command.toml` to expose it as `/<name>` in Gemini CLI.
   Use `@{/abs/path/to/SKILL.md}` to inject the shared instructions and
   `{{args}}` for the user's input.
3. Run `./install.sh`.
