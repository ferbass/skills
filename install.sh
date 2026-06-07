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

# Sanity check: the skills source folder must exist and hold at least one skill.
if [ ! -d "$SKILLS_DIR" ]; then
  echo "error: skills dir not found: $SKILLS_DIR" >&2
  exit 1
fi

# Claude config homes (each gets a skills/<name> symlink to the skill folder).
# Keep only the homes that actually exist on this machine; note the ones skipped.
CLAUDE_HOMES=()
for home in "$HOME/.claude" "$HOME/.claude-personal"; do
  if [ -d "$home" ]; then
    CLAUDE_HOMES+=("$home")
  else
    echo "claude home not found; skipping: $home"
  fi
done

# Only wire up Gemini if its CLI is actually installed.
if command -v gemini >/dev/null 2>&1; then
  HAVE_GEMINI=1
else
  HAVE_GEMINI=0
  echo "gemini CLI not found; skipping Gemini command links."
fi

# Nothing to link into? Stop before walking the skills.
if [ "${#CLAUDE_HOMES[@]}" -eq 0 ] && [ "$HAVE_GEMINI" -eq 0 ]; then
  echo "error: no Claude homes and no Gemini CLI found; nothing to do." >&2
  exit 1
fi

linked=0
for skill in "$SKILLS_DIR"/*/; do
  [ -f "${skill}SKILL.md" ] || continue
  name="$(basename "$skill")"
  skill="${skill%/}"

  # Claude agents: symlink the whole skill folder (homes already verified above).
  if [ "${#CLAUDE_HOMES[@]}" -gt 0 ]; then
    for home in "${CLAUDE_HOMES[@]}"; do
      mkdir -p "$home/skills"
      ln -sfn "$skill" "$home/skills/$name"
      echo "claude  $home/skills/$name -> $skill"
      linked=$((linked + 1))
    done
  fi

  # Gemini CLI: symlink the TOML command wrapper, if present.
  if [ "$HAVE_GEMINI" -eq 1 ] && [ -f "$skill/gemini-command.toml" ]; then
    mkdir -p "$HOME/.gemini/commands"
    ln -sfn "$skill/gemini-command.toml" "$HOME/.gemini/commands/$name.toml"
    echo "gemini  $HOME/.gemini/commands/$name.toml -> $skill/gemini-command.toml"
    linked=$((linked + 1))
  fi
done

echo "Done. $linked link(s) created/updated. Restart your agents to pick up new skills."
