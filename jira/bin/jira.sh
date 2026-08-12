#!/usr/bin/env bash
# Minimal Jira Cloud CLI.
#
# Credentials are resolved in this order:
#   1. JIRA_URL / JIRA_USERNAME / JIRA_API_TOKEN environment variables
#   2. the first JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN trio found anywhere in an
#      agent config file (MCP `env` / `environment` blocks, whatever the nesting),
#      searching in order:
#         $JIRA_MCP_CONFIG, ~/.claude/.mcp.json, ~/.claude.json,
#         ~/.config/opencode/opencode.json, ~/.gemini/settings.json,
#         ~/.pi/agent/settings.json, ./.mcp.json, ./.opencode/opencode.json,
#         ./.pi/settings.json
#      `{env:VAR}` placeholders (opencode style) are resolved from the environment.
#
# The token is never printed, never passed on the command line, and never
# appears in output — it is handed to curl through a file descriptor. Agents
# driving this script therefore never see it.
#
# Uses /rest/api/2 so descriptions and comments are plain strings (wiki markup)
# rather than the ADF JSON that /rest/api/3 requires.

set -euo pipefail

die() { printf '%s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null || die "curl not found"
command -v python3 >/dev/null || die "python3 not found"

# ---------------------------------------------------------------- credentials

load_creds() {
  if [[ -n "${JIRA_URL:-}" && -n "${JIRA_USERNAME:-}" && -n "${JIRA_API_TOKEN:-}" ]]; then
    return 0
  fi

  local candidates=()
  [[ -n "${JIRA_MCP_CONFIG:-}" ]] && candidates+=("$JIRA_MCP_CONFIG")
  candidates+=(
    "$HOME/.claude/.mcp.json" "$HOME/.claude.json"
    "$HOME/.config/opencode/opencode.json" "$HOME/.gemini/settings.json"
    "$HOME/.pi/agent/settings.json"
    "./.mcp.json" "./.opencode/opencode.json" "./.pi/settings.json"
  )

  # Emitted as three base64 lines so no value can be split on whitespace or
  # mangled by the shell, whatever it contains.
  local found
  found="$(python3 - "${candidates[@]}" <<'PY'
import base64, json, os, re, sys

KEYS = ("JIRA_URL", "JIRA_USERNAME", "JIRA_API_TOKEN")
PLACEHOLDER = re.compile(r"^\{env:([A-Za-z_][A-Za-z0-9_]*)\}$")


def resolve(value):
    """Config values may be `{env:VAR}` placeholders (opencode style)."""
    if not isinstance(value, str):
        return None
    m = PLACEHOLDER.match(value.strip())
    return os.environ.get(m.group(1)) if m else value


def find(node):
    """First dict anywhere in the config carrying all three Jira keys.

    Each harness nests them differently (`mcpServers[].env` for Claude and
    Gemini, `mcp[].environment` for opencode), so search rather than assume.
    """
    if isinstance(node, dict):
        vals = [resolve(node.get(k)) for k in KEYS]
        if all(vals):
            return vals
        for child in node.values():
            hit = find(child)
            if hit:
                return hit
    elif isinstance(node, list):
        for child in node:
            hit = find(child)
            if hit:
                return hit
    return None


for path in sys.argv[1:]:
    path = os.path.expanduser(path)
    try:
        with open(path) as fh:
            data = json.load(fh)
    except Exception:
        continue

    hit = find(data)
    if hit:
        for v in hit:
            print(base64.b64encode(v.encode()).decode())
        sys.exit(0)

sys.exit(1)
PY
)" || die "No Jira credentials found. Set JIRA_URL/JIRA_USERNAME/JIRA_API_TOKEN, or put them in an MCP server env block in one of: ~/.claude/.mcp.json, ~/.config/opencode/opencode.json, ~/.gemini/settings.json, ~/.pi/agent/settings.json"

  local b_url b_user b_token
  { read -r b_url; read -r b_user; read -r b_token; } <<<"$found"
  JIRA_URL="$(printf '%s' "$b_url" | base64 -d)"
  JIRA_USERNAME="$(printf '%s' "$b_user" | base64 -d)"
  JIRA_API_TOKEN="$(printf '%s' "$b_token" | base64 -d)"

  [[ -n "${JIRA_URL:-}" && -n "${JIRA_USERNAME:-}" && -n "${JIRA_API_TOKEN:-}" ]] \
    || die "Jira credentials incomplete"
}

# Pass credentials to curl via a file descriptor so the token never lands in
# argv (visible in `ps`) or in any log.
jcurl() {
  local path="$1"; shift
  curl -sS --fail-with-body \
    --config <(printf 'user = "%s:%s"\n' "$JIRA_USERNAME" "$JIRA_API_TOKEN") \
    -H "Accept: application/json" \
    "$@" "${JIRA_URL%/}/rest/api/2$path"
}

jpost() {
  local path="$1" body="$2"; shift 2
  jcurl "$path" -H "Content-Type: application/json" --data-binary "$body" "$@"
}

# JSON-encode a shell string safely.
jstr() { python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.argv[1]))' "$1"; }

usage() {
  cat <<'EOF'
Usage: jira.sh <command> [args]

  whoami                        Verify credentials; print the authenticated account
  get <KEY>                     Issue summary, status, type, assignee, description
  raw <KEY>                     Full issue JSON
  search <JQL> [max]            Search issues (default max 20)
  comments <KEY>                List comments
  comment <KEY> <text>          Add a comment
  create <PROJ> <type> <summary> [description]
                                Create an issue; prints the new key
  update <KEY> <fields-json>    Update fields, e.g. '{"summary":"new"}'
  transitions <KEY>             List available transitions (id + name)
  transition <KEY> <id|name>    Move the issue

Credentials: JIRA_* env vars, else an MCP server env block in a Claude,
opencode, Gemini, or pi config (see header). Point at a specific file with
JIRA_MCP_CONFIG.
EOF
}

cmd="${1:-}"; shift || true

# Help needs no credentials.
case "$cmd" in
  ""|-h|--help|help) usage; exit 0 ;;
esac

load_creds

case "$cmd" in
  whoami)
    jcurl "/myself" | python3 -c "$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
print(d.get("displayName"), "<%s>" % d.get("emailAddress"))
print("Site:", d.get("self", "").split("/rest/")[0])
PY
)"
    ;;

  get)
    [[ $# -ge 1 ]] || die "usage: jira.sh get <KEY>"
    jcurl "/issue/$1" | python3 -c '
import json, sys
f = json.load(sys.stdin)["fields"]
def name(x): return (x or {}).get("displayName") or (x or {}).get("name") or "-"
print("Summary:    ", f.get("summary"))
print("Type:       ", name(f.get("issuetype")))
print("Status:     ", name(f.get("status")))
print("Assignee:   ", name(f.get("assignee")))
print("Reporter:   ", name(f.get("reporter")))
print("Priority:   ", name(f.get("priority")))
labels = f.get("labels") or []
print("Labels:     ", ", ".join(labels) if labels else "-")
comps = [c.get("name") for c in (f.get("components") or [])]
print("Components: ", ", ".join(comps) if comps else "-")
print()
print(f.get("description") or "(no description)")
'
    ;;

  raw)
    [[ $# -ge 1 ]] || die "usage: jira.sh raw <KEY>"
    jcurl "/issue/$1"
    ;;

  search)
    [[ $# -ge 1 ]] || die "usage: jira.sh search <JQL> [max]"
    jpost "/search" "$(python3 -c '
import json,sys
print(json.dumps({"jql": sys.argv[1], "maxResults": int(sys.argv[2]),
                  "fields": ["summary","status","issuetype","assignee"]}))' "$1" "${2:-20}")" \
      | python3 -c "$(cat <<'PY'
import json, sys
d = json.load(sys.stdin)
issues = d.get("issues", [])
if not issues:
    print("No issues matched.")
for i in issues:
    f = i["fields"]
    st = (f.get("status") or {}).get("name", "-")
    print("%-14s %-16s %s" % (i["key"], st, f.get("summary", "")))
print("\n%d of %d" % (len(issues), d.get("total", 0)))
PY
)"
    ;;

  comments)
    [[ $# -ge 1 ]] || die "usage: jira.sh comments <KEY>"
    jcurl "/issue/$1/comment" | python3 -c "$(cat <<'PY'
import json, sys
for c in json.load(sys.stdin).get("comments", []):
    who = (c.get("author") or {}).get("displayName", "?")
    print("--- %s @ %s" % (who, (c.get("created") or "")[:19]))
    print(c.get("body", ""))
    print()
PY
)"
    ;;

  comment)
    [[ $# -ge 2 ]] || die "usage: jira.sh comment <KEY> <text>"
    key="$1"; shift
    jpost "/issue/$key/comment" "{\"body\": $(jstr "$*")}" >/dev/null
    echo "Comment added to $key"
    ;;

  create)
    [[ $# -ge 3 ]] || die "usage: jira.sh create <PROJ> <type> <summary> [description]"
    jpost "/issue" "$(python3 -c '
import json,sys
fields = {"project": {"key": sys.argv[1]}, "issuetype": {"name": sys.argv[2]},
          "summary": sys.argv[3]}
if len(sys.argv) > 4 and sys.argv[4]:
    fields["description"] = sys.argv[4]
print(json.dumps({"fields": fields}))' "$1" "$2" "$3" "${4:-}")" \
      | python3 -c 'import json,sys; print("Created", json.load(sys.stdin)["key"])'
    ;;

  update)
    [[ $# -ge 2 ]] || die "usage: jira.sh update <KEY> <fields-json>"
    jcurl "/issue/$1" -X PUT -H "Content-Type: application/json" \
      --data-binary "{\"fields\": $2}" >/dev/null
    echo "Updated $1"
    ;;

  transitions)
    [[ $# -ge 1 ]] || die "usage: jira.sh transitions <KEY>"
    jcurl "/issue/$1/transitions" | python3 -c "$(cat <<'PY'
import json, sys
for t in json.load(sys.stdin).get("transitions", []):
    print("%-6s %s  ->  %s" % (t["id"], t["name"], (t.get("to") or {}).get("name", "?")))
PY
)"
    ;;

  transition)
    [[ $# -ge 2 ]] || die "usage: jira.sh transition <KEY> <id|name>"
    key="$1"; want="$2"
    tid="$(jcurl "/issue/$key/transitions" | python3 -c '
import json, sys
want = sys.argv[1].strip().lower()
for t in json.load(sys.stdin).get("transitions", []):
    if t["id"] == sys.argv[1] or t["name"].strip().lower() == want:
        print(t["id"]); break
' "$want")"
    [[ -n "$tid" ]] || die "No transition matching '$want' on $key. Run: jira.sh transitions $key"
    jpost "/issue/$key/transitions" "{\"transition\": {\"id\": \"$tid\"}}" >/dev/null
    echo "Transitioned $key"
    ;;

  ""|-h|--help|help) usage ;;
  *) die "Unknown command: $cmd (try --help)" ;;
esac
