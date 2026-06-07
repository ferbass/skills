#!/usr/bin/env bash
#
# Symlink every skill in this folder into all the coding agents on this machine,
# so they share one source of truth. Re-run any time you add a skill.
#
#   - Claude (`claude`)           -> ~/.claude/skills/<name>
#   - Claude (`claude-personal`)  -> ~/.claude-personal/skills/<name>
#   - Gemini CLI                  -> ~/.gemini/commands/<name>.toml
#                                    (only for skills that ship a gemini-command.toml)
#
# A "skill" is any subfolder here that contains a SKILL.md.

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Claude config homes (each gets a skills/<name> symlink to the skill folder).
CLAUDE_HOMES=("$HOME/.claude" "$HOME/.claude-personal")

linked=0
for skill in "$SKILLS_DIR"/*/; do
  [ -f "${skill}SKILL.md" ] || continue
  name="$(basename "$skill")"
  skill="${skill%/}"

  # Claude agents: symlink the whole skill folder.
  for home in "${CLAUDE_HOMES[@]}"; do
    [ -d "$home" ] || continue
    mkdir -p "$home/skills"
    ln -sfn "$skill" "$home/skills/$name"
    echo "claude  $home/skills/$name -> $skill"
    linked=$((linked + 1))
  done

  # Gemini CLI: symlink the TOML command wrapper, if present.
  if [ -f "$skill/gemini-command.toml" ]; then
    mkdir -p "$HOME/.gemini/commands"
    ln -sfn "$skill/gemini-command.toml" "$HOME/.gemini/commands/$name.toml"
    echo "gemini  $HOME/.gemini/commands/$name.toml -> $skill/gemini-command.toml"
    linked=$((linked + 1))
  fi
done

echo "Done. $linked link(s) created/updated. Restart your agents to pick up new skills."
