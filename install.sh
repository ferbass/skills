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
#
# Personal config: your `skills.config` (gitignored; copy from
# skills.config.example) is linked to ~/.config/skills/config so the skills can
# find your paths regardless of where this repo lives.

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sanity check: the skills source folder must exist and hold at least one skill.
if [ ! -d "$SKILLS_DIR" ]; then
  echo "error: skills dir not found: $SKILLS_DIR" >&2
  exit 1
fi

# Personal config: ensure skills.config exists, then link it to a fixed location
# (~/.config/skills/config) that the skills read at runtime.
CONFIG_SRC="$SKILLS_DIR/skills.config"
CONFIG_EXAMPLE="$SKILLS_DIR/skills.config.example"
CONFIG_LINK="$HOME/.config/skills/config"
if [ ! -f "$CONFIG_SRC" ]; then
  if [ -f "$CONFIG_EXAMPLE" ]; then
    cp "$CONFIG_EXAMPLE" "$CONFIG_SRC"
    echo "created $CONFIG_SRC from example — edit it to fill in your paths."
  else
    echo "warning: no skills.config or skills.config.example found." >&2
  fi
fi
if [ -f "$CONFIG_SRC" ]; then
  mkdir -p "$(dirname "$CONFIG_LINK")"
  ln -sfn "$CONFIG_SRC" "$CONFIG_LINK"
  echo "config  $CONFIG_LINK -> $CONFIG_SRC"
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

  # Gemini CLI: generate the TOML command wrapper, if present. We generate (not
  # symlink) so the __SKILL_MD__ placeholder resolves to this machine's absolute
  # path — that keeps the committed toml portable across clones. Write via a temp
  # file + mv so we never redirect through a stale symlink into the source file.
  if [ "$HAVE_GEMINI" -eq 1 ] && [ -f "$skill/gemini-command.toml" ]; then
    mkdir -p "$HOME/.gemini/commands"
    dest="$HOME/.gemini/commands/$name.toml"
    tmp="$(mktemp "${dest}.XXXXXX")"
    sed "s#__SKILL_MD__#$skill/SKILL.md#g" "$skill/gemini-command.toml" > "$tmp"
    mv -f "$tmp" "$dest"
    echo "gemini  $dest (from $skill/gemini-command.toml)"
    linked=$((linked + 1))
  fi
done

echo "Done. $linked link(s) created/updated. Restart your agents to pick up new skills."
