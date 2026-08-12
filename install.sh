#!/usr/bin/env bash
#
# Manage this repo's skills across the coding agents on this machine.
#
#   - Claude       -> <home>/skills/<name>   for each configured Claude home
#                     (defaults to ~/.claude; override via CLAUDE_HOMES in config)
#   - Gemini CLI   -> ~/.gemini/commands/<name>.toml
#                     (only for skills that ship a gemini-command.toml)
#   - opencode/pi  -> ~/.agents/skills/<name>
#                     both harnesses auto-discover this shared directory
#   - opencode     -> ~/.config/opencode/command/<name>.md  (generated /<name>)
#
# A "skill" is any subfolder here that contains a SKILL.md.
#
# Usage:
#   ./install.sh                    interactive menu (install / remove / list)
#   ./install.sh --all              install every skill (non-interactive)
#   ./install.sh --list             list skills and whether they're installed
#   ./install.sh <name>...          install the named skill(s)
#   ./install.sh --remove <name>... remove the named skill(s)
#
# Personal config: your `skills.config` (gitignored; copy from
# skills.config.example) is linked to ~/.config/skills/config so the skills can
# find your paths regardless of where this repo lives.

set -euo pipefail

SKILLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -d "$SKILLS_DIR" ]; then
  echo "error: skills dir not found: $SKILLS_DIR" >&2
  exit 1
fi

# ---- personal config: seed, link to a fixed location, and source ----------
CONFIG_SRC="$SKILLS_DIR/skills.config"
CONFIG_EXAMPLE="$SKILLS_DIR/skills.config.example"
CONFIG_LINK="$HOME/.config/skills/config"
if [ ! -f "$CONFIG_SRC" ] && [ -f "$CONFIG_EXAMPLE" ]; then
  cp "$CONFIG_EXAMPLE" "$CONFIG_SRC"
  echo "created $CONFIG_SRC from example — edit it to fill in your paths."
fi
if [ -f "$CONFIG_SRC" ]; then
  mkdir -p "$(dirname "$CONFIG_LINK")"
  ln -sfn "$CONFIG_SRC" "$CONFIG_LINK"
  # Pull in config values we use here (e.g. CLAUDE_HOMES). It's your own file of
  # KEY="value" / array lines; sourcing keeps a single source of truth.
  # shellcheck disable=SC1090
  . "$CONFIG_SRC"
fi

# ---- resolve Claude homes (keep only the ones that exist) -----------------
# Default to ~/.claude; CLAUDE_HOMES (a bash array) in skills.config overrides.
_wanted_homes=("${CLAUDE_HOMES[@]:-$HOME/.claude}")
CLAUDE_HOMES=()
for home in "${_wanted_homes[@]}"; do
  if [ -d "$home" ]; then
    CLAUDE_HOMES+=("$home")
  else
    echo "claude home not found; skipping: $home"
  fi
done

# ---- other agent availability ---------------------------------------------
if command -v gemini >/dev/null 2>&1; then HAVE_GEMINI=1; else HAVE_GEMINI=0; fi
# Codex CLI: present if the binary is on PATH or its home dir exists.
if command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ]; then HAS_CODEX=1; else HAS_CODEX=0; fi
if command -v opencode >/dev/null 2>&1 || [ -d "$HOME/.config/opencode" ]; then
  HAVE_OPENCODE=1
else
  HAVE_OPENCODE=0
fi
if command -v pi >/dev/null 2>&1 || [ -d "$HOME/.pi" ]; then HAVE_PI=1; else HAVE_PI=0; fi

# opencode and pi both auto-discover ~/.agents/skills/<name>/SKILL.md, so one
# symlink there serves both. Override with AGENTS_SKILLS_DIR in skills.config.
AGENTS_SKILLS_DIR="${AGENTS_SKILLS_DIR:-$HOME/.agents/skills}"
OPENCODE_COMMANDS_DIR="${OPENCODE_COMMANDS_DIR:-$HOME/.config/opencode/command}"
if [ "$HAVE_OPENCODE" -eq 1 ] || [ "$HAVE_PI" -eq 1 ]; then
  HAVE_AGENTS_DIR=1
else
  HAVE_AGENTS_DIR=0
fi

if [ "${#CLAUDE_HOMES[@]}" -eq 0 ] && [ "$HAVE_GEMINI" -eq 0 ] && [ "$HAS_CODEX" -eq 0 ] \
   && [ "$HAVE_AGENTS_DIR" -eq 0 ]; then
  echo "error: no Claude homes and no Gemini/Codex/opencode/pi install found; nothing to do." >&2
  exit 1
fi

# ---- discover skills ------------------------------------------------------
ALL_SKILLS=()
for d in "$SKILLS_DIR"/*/; do
  [ -f "${d}SKILL.md" ] || continue
  ALL_SKILLS+=("$(basename "$d")")
done
if [ "${#ALL_SKILLS[@]}" -eq 0 ]; then
  echo "no skills found in $SKILLS_DIR" >&2
  exit 1
fi

# ---- helpers --------------------------------------------------------------
# A skill counts as installed if it's linked in any Claude home, shared with
# opencode/pi, or has a generated Gemini command. The ${arr[@]+...} idiom is
# empty-array safe.
is_installed() {
  local name="$1" home
  for home in ${CLAUDE_HOMES[@]+"${CLAUDE_HOMES[@]}"}; do
    [ -e "$home/skills/$name" ] && return 0
  done
  [ -e "$AGENTS_SKILLS_DIR/$name" ] && return 0
  [ -f "$HOME/.gemini/commands/$name.toml" ] && return 0
  return 1
}

# The `description:` value from a SKILL.md front matter, escaped for use as a
# YAML single-quoted scalar.
skill_description() {
  local desc q="'"
  desc="$(sed -n '2,20s/^description:[[:space:]]*//p' "$1" | head -1)"
  desc="${desc%\"}"; desc="${desc#\"}"
  # A single quote inside a YAML single-quoted scalar is written as two.
  printf '%s' "${desc//$q/$q$q}"
}

# opencode custom command: a thin /<name> wrapper that points the agent at the
# shared SKILL.md, so opencode and Claude read the same source of truth.
opencode_command() {
  local skill="$1"
  cat <<EOF
---
description: '$(skill_description "$skill/SKILL.md")'
---

Follow the skill instructions in \`$skill/SKILL.md\` exactly — read that file
first, then do what it says.

Its base directory is \`$skill\`; resolve any relative path it mentions (e.g.
\`bin/…\`, \`references/…\`) against that directory.

Request / context (may be empty — derive it from the conversation if so):
\$ARGUMENTS
EOF
}

install_one() {
  local name="$1" skill="$SKILLS_DIR/$1" home dest tmp
  if [ ! -f "$skill/SKILL.md" ]; then
    echo "  no such skill: $name" >&2
    return 1
  fi
  for home in ${CLAUDE_HOMES[@]+"${CLAUDE_HOMES[@]}"}; do
    mkdir -p "$home/skills"
    ln -sfn "$skill" "$home/skills/$name"
    echo "  claude  $home/skills/$name"
  done
  if [ "$HAVE_AGENTS_DIR" -eq 1 ]; then
    mkdir -p "$AGENTS_SKILLS_DIR"
    ln -sfn "$skill" "$AGENTS_SKILLS_DIR/$name"
    echo "  agents  $AGENTS_SKILLS_DIR/$name (opencode + pi)"
  fi
  if [ "$HAVE_OPENCODE" -eq 1 ]; then
    mkdir -p "$OPENCODE_COMMANDS_DIR"
    dest="$OPENCODE_COMMANDS_DIR/$name.md"
    tmp="$(mktemp "${dest}.XXXXXX")"
    opencode_command "$skill" > "$tmp"
    mv -f "$tmp" "$dest"
    echo "  opencode $dest"
  fi
  if [ "$HAVE_GEMINI" -eq 1 ] && [ -f "$skill/gemini-command.toml" ]; then
    mkdir -p "$HOME/.gemini/commands"
    dest="$HOME/.gemini/commands/$name.toml"
    tmp="$(mktemp "${dest}.XXXXXX")"
    sed "s#__SKILL_MD__#$skill/SKILL.md#g" "$skill/gemini-command.toml" > "$tmp"
    mv -f "$tmp" "$dest"
    echo "  gemini  $dest"
  fi
}

remove_one() {
  local name="$1" home dest removed=0
  for home in ${CLAUDE_HOMES[@]+"${CLAUDE_HOMES[@]}"}; do
    if [ -e "$home/skills/$name" ] || [ -L "$home/skills/$name" ]; then
      rm -rf "$home/skills/$name"
      echo "  removed $home/skills/$name"
      removed=1
    fi
  done
  if [ -e "$AGENTS_SKILLS_DIR/$name" ] || [ -L "$AGENTS_SKILLS_DIR/$name" ]; then
    rm -rf "$AGENTS_SKILLS_DIR/$name"
    echo "  removed $AGENTS_SKILLS_DIR/$name"
    removed=1
  fi
  for dest in "$OPENCODE_COMMANDS_DIR/$name.md" "$HOME/.gemini/commands/$name.toml"; do
    if [ -f "$dest" ]; then
      rm -f "$dest"
      echo "  removed $dest"
      removed=1
    fi
  done
  [ "$removed" -eq 1 ] || echo "  $name was not installed"
}

list_status() {
  echo "Skills in $SKILLS_DIR:"
  local i=1 name
  for name in "${ALL_SKILLS[@]}"; do
    if is_installed "$name"; then
      printf "  %2d) %-14s installed\n" "$i" "$name"
    else
      printf "  %2d) %-14s -\n" "$i" "$name"
    fi
    i=$((i + 1))
  done
}

# Map a selection token (number or name) to a skill name; empty if invalid.
resolve_skill() {
  local sel="$1" name idx
  if [[ "$sel" =~ ^[0-9]+$ ]]; then
    idx=$((sel - 1))
    if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#ALL_SKILLS[@]}" ]; then
      echo "${ALL_SKILLS[$idx]}"
    fi
  else
    for name in "${ALL_SKILLS[@]}"; do
      [ "$name" = "$sel" ] && { echo "$name"; return; }
    done
  fi
}

install_all() {
  local name
  for name in "${ALL_SKILLS[@]}"; do
    echo "installing $name"
    install_one "$name"
  done
}

# Apply an action (install/remove) to a selection that may be a name, number,
# or the word "all".
apply_to_selection() {
  local action="$1" sel="$2" name verb
  verb="installing"; [ "$action" = remove ] && verb="removing"
  if [ "$sel" = all ]; then
    for name in "${ALL_SKILLS[@]}"; do
      echo "$verb $name"
      "${action}_one" "$name"
    done
    return
  fi
  name="$(resolve_skill "$sel")"
  if [ -z "$name" ]; then
    echo "  no such skill: $sel"
    return
  fi
  echo "$verb $name"
  "${action}_one" "$name"
}

interactive() {
  local targets="${CLAUDE_HOMES[*]:-(no claude homes)}"
  [ "$HAVE_AGENTS_DIR" -eq 1 ] && targets="$targets + $AGENTS_SKILLS_DIR"
  [ "$HAVE_OPENCODE" -eq 1 ] && targets="$targets + opencode"
  [ "$HAVE_PI" -eq 1 ] && targets="$targets + pi"
  [ "$HAVE_GEMINI" -eq 1 ] && targets="$targets + gemini"
  echo "Targets: $targets"
  local action sel
  while true; do
    echo
    list_status
    echo
    echo "Action: [i]nstall  [r]emove  [A]ll (install all)  [q]uit"
    read -rp "> " action || break
    case "$action" in
      i|install)
        read -rp "  install which? (number, name, or 'all'): " sel || break
        apply_to_selection install "$sel"
        ;;
      r|remove)
        read -rp "  remove which? (number, name, or 'all'): " sel || break
        apply_to_selection remove "$sel"
        ;;
      A|all)
        install_all
        ;;
      q|quit|"")
        break
        ;;
      *)
        echo "  unknown action: $action"
        ;;
    esac
  done
  echo "Done. Restart your agents to pick up changes."
}

# ---- dispatch -------------------------------------------------------------
case "${1:-}" in
  --list|-l)
    list_status
    ;;
  --all|-a)
    install_all
    echo "Done. Restart your agents to pick up changes."
    ;;
  --remove|-r)
    shift
    [ "$#" -gt 0 ] || { echo "usage: ./install.sh --remove <name>..." >&2; exit 1; }
    for arg in "$@"; do remove_one "$arg"; done
    echo "Done."
    ;;
  --help|-h)
    sed -n '3,21p' "$0"
    ;;
  "")
    # Interactive when attached to a terminal; otherwise behave like --all so
    # piped/automated runs still work.
    if [ -t 0 ]; then interactive; else install_all; echo "Done."; fi
    ;;
  -*)
    echo "unknown option: $1 (try --help)" >&2
    exit 1
    ;;
  *)
    for arg in "$@"; do install_one "$arg"; done
    echo "Done. Restart your agents to pick up changes."
    ;;
esac
