#!/usr/bin/env bash
# Search aqora for published workspaces matching a query or tag filter.
# Thin wrapper over the aqora GraphQL workspaces() query. Emits JSON on stdout.
#
# Output shape (one entry per workspace):
#   { id, slug, name, shortDescription, owner, url, tags, votes }
# `tags` may be empty for workspaces that were not tagged on publish.
# `url` is the editor URL for the current viewer (or null if no runner is live).
#
# Usage:
#   search-workspaces.sh --search "QAOA"
#   search-workspaces.sh --tags role:simulator,framework:pennylane
#   search-workspaces.sh --search "portfolio" --first 5 --order TRENDING
#
# Options:
#   --search QUERY    Full-text search. Pass quoted phrases for exact match.
#   --tags TAG,TAG    Comma-separated tag filter. See references/conventions/tag-taxonomy.md.
#   --first N         Maximum results. Default 10. Max 100.
#   --order ORDER     TRENDING (default) or CREATED_AT.
#
# Auth resolution order:
#   1. --token TOKEN flag (avoid; visible in ps)
#   2. AQORA_TOKEN env var (preferred for CI)
#   3. access_token from the aqora CLI credentials file
#      (written by `aqora login`, located at <config_home>/credentials.json)
#
# Custom deployments: set AQORA_API_URL to override the default endpoint.

set -euo pipefail

aqora_api="${AQORA_API_URL:-https://aqora.io}"
token="${AQORA_TOKEN:-}"
search=""
tags_csv=""
first=10
order="TRENDING"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --search) search="$2"; shift 2 ;;
    --tags)   tags_csv="$2"; shift 2 ;;
    --first)  first="$2"; shift 2 ;;
    --order)  order="$2"; shift 2 ;;
    --token)  token="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  echo "Unexpected argument: $1" >&2; exit 1 ;;
  esac
done

if [[ "$order" != "TRENDING" && "$order" != "CREATED_AT" ]]; then
  echo "Invalid --order '$order'. Expected TRENDING or CREATED_AT." >&2
  exit 1
fi

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

See aqora-workspace/references/auth.md in the skills repo for details.
ERR
  exit 1
fi

# GraphQL query. Shellcheck flags $var inside single quotes (SC2016); those
# are GraphQL variable placeholders, not bash vars. Intentional.
# shellcheck disable=SC2016
query='query SearchWorkspaces($first: Int!, $search: String, $tags: [String!], $order: WorkspaceConnectionOrder!) {
  workspaces(first: $first, filters: { search: $search, tags: $tags, order: $order }) {
    totalCount
    nodes {
      id
      slug
      name
      shortDescription
      owner { ... on Entity { username } }
      editor { url }
      viewer { url }
    }
  }
}'

if [[ -n "$tags_csv" ]]; then
  tags_json=$(echo "$tags_csv" | jq -Rc 'split(",") | map(select(length > 0))')
else
  tags_json='null'
fi

variables=$(jq -n \
  --argjson first "$first" \
  --arg search "$search" \
  --argjson tags "$tags_json" \
  --arg order "$order" \
  '{first: $first, search: (if $search == "" then null else $search end), tags: $tags, order: $order}')

payload=$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')

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

echo "$response" | jq '.data.workspaces.nodes | map({
  id,
  slug,
  name,
  shortDescription,
  owner: (.owner.username // null),
  editor_url: (.editor.url // null),
  viewer_url: (.viewer.url // null)
})'
