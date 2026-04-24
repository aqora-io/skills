#!/usr/bin/env bash
# Describe a single published aqora workspace in enough detail for an agent to
# decide whether to use it, and how to call it.
#
# Emits JSON with metadata plus the editor URL. For API-level introspection
# (which @app.function cells the workspace exports and their signatures), have
# the agent run a short probe from inside its own workspace:
#
#   import aqora_cli as aq
#   ws = await aq.notebook("owner/slug")
#   help(ws)
#
# Getting that information server-side would require parsing readme.py, which
# can drift as workspaces iterate. Doing it via help() at call time stays
# truthful.
#
# Usage:
#   describe-workspace.sh OWNER/SLUG
#   describe-workspace.sh owner slug
#
# Auth resolution order:
#   1. --token TOKEN flag (avoid; visible in ps)
#   2. AQORA_TOKEN env var (preferred for CI)
#   3. access_token from the aqora CLI credentials file

set -euo pipefail

aqora_api="${AQORA_API_URL:-https://aqora.io}"
token="${AQORA_TOKEN:-}"
owner=""
slug=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --token) token="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,23p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$owner" ]]; then
        if [[ "$1" == *"/"* ]]; then
          owner="${1%%/*}"
          slug="${1#*/}"
        else
          owner="$1"
        fi
      elif [[ -z "$slug" ]]; then
        slug="$1"
      else
        echo "Unexpected argument: $1" >&2
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$owner" || -z "$slug" ]]; then
  echo "Usage: describe-workspace.sh OWNER/SLUG" >&2
  exit 1
fi

# Try `aqora auth token` first (refresh-aware path; see search-workspaces.sh
# for context). Falls through to the credential-file read below on older
# CLIs.
if [[ -z "$token" ]] && command -v aqora >/dev/null 2>&1; then
  token="$(aqora auth token --url "$aqora_api" 2>/dev/null || true)"
fi

# Fall back to reading the credentials file directly
if [[ -z "$token" ]]; then
  if [[ -n "${AQORA_CONFIG_HOME:-}" ]]; then
    config_home="$AQORA_CONFIG_HOME"
  else
    case "$(uname -s)" in
      Darwin) config_home="$HOME/Library/Application Support/aqora" ;;
      *)      config_home="${XDG_DATA_HOME:-$HOME/.local/share}/aqora" ;;
    esac
  fi
  creds_file="$config_home/credentials.json"

  if [[ -f "$creds_file" ]]; then
    url_key="${aqora_api%/}/"
    token=$(jq -r --arg url "$url_key" '.credentials[$url].access_token // empty' "$creds_file" 2>/dev/null || true)
  fi
fi

if [[ -z "$token" ]]; then
  echo "Error: no aqora token. Run 'aqora login' or set AQORA_TOKEN." >&2
  exit 1
fi

# GraphQL query. Shellcheck flags $var inside single quotes (SC2016); those
# are GraphQL variable placeholders, not bash vars. Intentional.
# shellcheck disable=SC2016
query='query DescribeWorkspace($owner: String!, $slug: String!) {
  workspaceBySlug(owner: $owner, slug: $slug) {
    id
    slug
    name
    shortDescription
    createdAt
    voterCount
    private
    owner { ... on Entity { username displayName } }
    defaultNotebook
    editor { url command }
    viewer { url command }
  }
}'

payload=$(jq -n --arg q "$query" --arg owner "$owner" --arg slug "$slug" \
  '{query: $q, variables: {owner: $owner, slug: $slug}}')

response=$(curl -fsS -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  "${aqora_api%/}/graphql")

if echo "$response" | jq -e '.errors | length > 0' >/dev/null 2>&1; then
  echo "Error from aqora GraphQL:" >&2
  echo "$response" | jq '.errors' >&2
  if echo "$response" | jq -e '.errors[] | select(.extensions.code == "INVALID_AUTHORIZATION")' >/dev/null 2>&1; then
    echo "Hint: the stored access token may be expired. Run 'aqora login' to refresh." >&2
  fi
  exit 1
fi

node=$(echo "$response" | jq '.data.workspaceBySlug')
if [[ "$node" == "null" ]]; then
  echo "Workspace '${owner}/${slug}' not found or not accessible." >&2
  exit 1
fi

echo "$node" | jq '{
  id,
  slug,
  name,
  shortDescription,
  createdAt,
  voterCount,
  private,
  owner: (.owner.username // null),
  ownerDisplayName: (.owner.displayName // null),
  defaultNotebook,
  editor_url: (.editor.url // null),
  editor_command: (.editor.command // null),
  viewer_url: (.viewer.url // null),
  viewer_command: (.viewer.command // null)
}'
