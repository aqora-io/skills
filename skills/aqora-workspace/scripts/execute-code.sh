#!/usr/bin/env bash
# Execute code inside a running aqora workspace's marimo kernel.
# No marimo installation required. Talks directly to the workspace HTTP API
# via the aqora proxy.
#
# Usage:
#   execute-code.sh --workspace ID|SLUG [--session SID] -c "code"
#   execute-code.sh --workspace ID|SLUG [--session SID] script.py
#   execute-code.sh --workspace ID|SLUG [--session SID] <<'EOF'
#     code
#   EOF
#   execute-code.sh --url URL [--session SID] -c "code"
#
# Auth resolution order:
#   1. --token TOKEN flag (avoid; visible in ps)
#   2. AQORA_TOKEN env var (preferred for CI)
#   3. access_token from the aqora CLI credentials file
#      (written by `aqora login`, located at <config_home>/credentials.json)

set -euo pipefail

# Optional call logging
if [[ -n "${EXECUTE_CODE_LOG:-}" ]]; then
  date -u +%Y-%m-%dT%H:%M:%SZ >> "$EXECUTE_CODE_LOG"
fi

aqora_api="${AQORA_API_URL:-https://aqora.io}"
workspace=""
url=""
code=""
session=""
token="${AQORA_TOKEN:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --workspace) workspace="$2"; shift 2 ;;
    --url)       url="$2"; shift 2 ;;
    --session)   session="$2"; shift 2 ;;
    --token)     token="$2"; shift 2 ;;
    -c)          code="$2"; shift 2 ;;
    -h|--help)
      sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *)  break ;;
  esac
done

# Source the code: -c, positional file, or stdin
if [[ -n "$code" ]]; then
  :
elif [[ $# -gt 0 ]]; then
  code=$(cat "$1")
elif [[ ! -t 0 ]]; then
  code=$(cat)
else
  cat >&2 <<'USAGE'
Usage:
  execute-code.sh --workspace ID -c "code"
  execute-code.sh --workspace ID script.py
  execute-code.sh --url URL -c "code"

Auth: set AQORA_TOKEN or run `aqora login` first.
USAGE
  exit 1
fi

# Resolve token from the CLI credentials file if not set
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

# Resolve workspace URL via the list script if only --workspace was given
if [[ -z "$url" && -n "$workspace" ]]; then
  script_dir="$(cd "$(dirname "$0")" && pwd)"
  url=$(bash "$script_dir/list-workspaces.sh" --id "$workspace" --url-only 2>/dev/null || true)
fi

if [[ -z "$url" ]]; then
  echo "Error: provide --workspace ID or --url URL." >&2
  exit 1
fi

# Warn when connecting to a non-aqora host (exfiltration risk)
url_host="${url#*://}"
url_host="${url_host%%[:/]*}"
case "$url_host" in
  *.aqora.io|aqora.io|*.aqora-internal.io|localhost|127.0.0.1|::1|0.0.0.0) ;;
  *) echo "Warning: connecting to non-aqora host '${url_host}'. Ensure this is trusted." >&2 ;;
esac

base="${url%/}"

# Build payload. The session id is optional; omit it to target the default
# scratchpad.
if [[ -n "$session" ]]; then
  payload=$(jq -n --arg code "$code" --arg session "$session" \
    '{code: $code, sessionId: $session}')
else
  payload=$(jq -n --arg code "$code" '{code: $code}')
fi

# KNOWN LIMITATION (as of 0.1.0): the aqora runner proxy enforces a skew
# protection token that external callers cannot currently obtain. Marimo
# exempts POST /api/kernel/execute from its own check, but the aqora proxy in
# front of marimo does not. Until the aqora platform documents the
# proxy-level auth handshake, this script will return an HTTP 401 "Missing
# server token" error. See the "known issues" section of CHANGELOG.md and the
# tracking GitHub issue for status.
#
# Once the proxy contract is clarified, adjust the endpoint, headers, and
# auth token here. The intended target endpoint is the agent-only
# /api/kernel/execute path (marimo exempts it from the skew-protection
# middleware, see marimo/_server/api/middleware.py).
#
# Payload shape matches ExecuteScratchpadRequest in
# marimo/_server/api/endpoints/execution.py.
curl -fsS -X POST \
  -H "Authorization: Bearer $token" \
  -H "Content-Type: application/json" \
  --data "$payload" \
  "$base/api/kernel/execute"
