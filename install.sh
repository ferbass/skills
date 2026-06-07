#!/usr/bin/env bash
#
# Manage this repo's skills across the coding agents on this machine.
#
#   - Claude     -> <home>/skills/<name>   for each configured Claude home
#                   (defaults to ~/.claude; override via CLAUDE_HOMES in config)
#   - Gemini CLI -> ~/.gemini/commands/<name>.toml
#                   (only for skills that ship a gemini-command.toml)
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

# ---- gemini availability --------------------------------------------------
if command -v gemini >/dev/null 2>&1; then HAVE_GEMINI=1; else HAVE_GEMINI=0; fi

if [ "${#CLAUDE_HOMES[@]}" -eq 0 ] && [ "$HAVE_GEMINI" -eq 0 ]; then
  echo "error: no Claude homes and no Gemini CLI found; nothing to do." >&2
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
# A skill counts as installed if it's linked in any Claude home or has a
# generated Gemini command. The ${arr[@]+...} idiom is empty-array safe.
is_installed() {
  local name="$1" home
  for home in ${CLAUDE_HOMES[@]+"${CLAUDE_HOMES[@]}"}; do
    [ -e "$home/skills/$name" ] && return 0
  done
  [ -f "$HOME/.gemini/commands/$name.toml" ] && return 0
  return 1
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
  dest="$HOME/.gemini/commands/$name.toml"
  if [ -f "$dest" ]; then
    rm -f "$dest"
    echo "  removed $dest"
    removed=1
  fi
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
    sed -n '3,18p' "$0"
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
