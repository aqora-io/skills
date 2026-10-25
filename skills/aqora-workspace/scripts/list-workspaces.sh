#!/usr/bin/env bash
# List aqora workspaces the authenticated user owns.
# Calls the aqora GraphQL API and emits JSON on stdout.
#
# Output shape (one entry per workspace):
#   {
#     id, slug, name, shortDescription,
#     editor_url, editor_command,   # non-null when an editor runner is live
#     viewer_url, viewer_command    # non-null when a viewer runner is live
#   }
#
# Usage:
#   list-workspaces.sh                         # all workspaces, full detail
#   list-workspaces.sh --id ID|SLUG            # one workspace, full detail
#   list-workspaces.sh --id ID|SLUG --url-only # first live runner URL, for scripting
#
# --url-only picks editor_url if present, else viewer_url. An empty result
# means no runner is currently live for that workspace and the user needs to
# start it from the aqora UI.
#
# Auth resolution order:
#   1. --token TOKEN flag (avoid; visible in ps)
#   2. AQORA_TOKEN env var (preferred for CI)
#   3. access_token from the aqora CLI credentials file
#      (written by `aqora login`, located at <config_home>/credentials.json)
#
# Note: the stored access_token expires. If the API returns
# "Session Not Found", run `aqora login` to refresh, or set AQORA_TOKEN to a
# personal access token.
#
# Custom deployments: set AQORA_API_URL to override the default endpoint.
# Custom config home: set AQORA_CONFIG_HOME to override the default path.

set -euo pipefail

aqora_api="${AQORA_API_URL:-https://aqora.io}"
token="${AQORA_TOKEN:-}"
id_filter=""
url_only=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id)       id_filter="$2"; shift 2 ;;
    --url-only) url_only=true; shift ;;
    --token)    token="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  echo "Unexpected argument: $1" >&2; exit 1 ;;
  esac
done

# Try `aqora auth token` first. This is the refresh-aware path; the CLI
# transparently refreshes an expired access_token via the refresh_token and
# prints a fresh one. Available in aqora-cli versions that include the
# `auth` subcommand; older versions fall through to direct credential-file
# reading below.
if [[ -z "$token" ]] && command -v aqora >/dev/null 2>&1; then
  token="$(aqora auth token --url "$aqora_api" 2>/dev/null || true)"
fi

# Fall back to reading the credentials file directly (older CLI versions
# without `aqora auth token`). Known limitation: no refresh, so expired
# tokens surface as INVALID_AUTHORIZATION errors and the user has to rerun
# `aqora login`.
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
  cat >&2 <<ERR
Error: no aqora token available.

Fix one of:
  1. export AQORA_TOKEN=<your personal access token>
  2. install the aqora CLI and run \`aqora login\` for API URL ${aqora_api}

See references/auth.md in the skill directory for details.
ERR
  exit 1
fi

# GraphQL query. Field names reflect the live aqora platform schema as of
# April 2026. If the schema changes, adjust here and in the jq post-processing
# below.
query='query ListWorkspaces {
  viewer {
    workspaces {
      totalCount
      nodes {
        id
        slug
        name
        shortDescription
        editor { url command }
        viewer { url command }
      }
    }
  }
}'

payload=$(jq -n --arg q "$query" '{query: $q}')

response=$(curl -fsS -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  "${aqora_api%/}/graphql")

# Surface GraphQL errors clearly. Session errors usually mean the stored
# access token expired; tell the user how to recover.
if echo "$response" | jq -e '.errors | length > 0' >/dev/null 2>&1; then
  echo "Error from aqora GraphQL:" >&2
  echo "$response" | jq '.errors' >&2
  if echo "$response" | jq -e '.errors[] | select(.extensions.code == "INVALID_AUTHORIZATION")' >/dev/null 2>&1; then
    echo "Hint: the stored access token may be expired. Run 'aqora login' to refresh." >&2
  fi
  exit 1
fi

# Flatten each workspace into a single object with editor and viewer fields
# promoted for easier consumption
flattened=$(echo "$response" | jq '.data.viewer.workspaces.nodes | map({
  id, slug, name, shortDescription,
  editor_url: (.editor.url // null),
  editor_command: (.editor.command // null),
  viewer_url: (.viewer.url // null),
  viewer_command: (.viewer.command // null)
})')

if [[ -n "$id_filter" ]]; then
  match=$(echo "$flattened" | jq --arg id "$id_filter" \
    '[.[] | select(.id == $id or .slug == $id)] | first // null')

  if [[ "$match" == "null" ]]; then
    echo "No workspace found with id or slug '$id_filter'." >&2
    exit 1
  fi

  if [[ "$url_only" == true ]]; then
    url=$(echo "$match" | jq -r '.editor_url // .viewer_url // empty')
    if [[ -z "$url" ]]; then
      echo "Workspace '$id_filter' has no live runner. Start it from the aqora UI." >&2
      exit 1
    fi
    echo "$url"
  else
    echo "$match"
  fi
else
  echo "$flattened"
fi
