# Authentication

The skill's scripts resolve credentials in this order:

1. `--token TOKEN` flag passed to the script. Avoid this; flags are visible in `ps aux`.
2. `AQORA_TOKEN` environment variable. Preferred for CI and service accounts.
3. `aqora auth token` command output. Refresh-aware: the CLI transparently refreshes an expired `access_token` via the stored `refresh_token` and prints a fresh one. Available in aqora-cli versions that include the `auth` subcommand.
4. Direct read of the aqora CLI credentials file, written by `aqora login`. Fallback for older CLIs; does not refresh, so expired tokens surface as 401 errors.

If none of these produce a token, the scripts exit with a clear error.

## Interactive Login

Install the aqora CLI and log in once:

```
pip install aqora-cli
aqora login
```

`aqora login` opens a browser for OAuth and writes the resulting credentials to a file the scripts then read (via `aqora auth token` when available). No extra environment variable needed.

### Credentials File Location

The CLI stores credentials at `<config_home>/credentials.json`, where `config_home` defaults to:

| Platform | Path |
| :------- | :--- |
| macOS | `~/Library/Application Support/aqora/credentials.json` |
| Linux | `~/.local/share/aqora/credentials.json` (honors `XDG_DATA_HOME`) |
| Override | Set `AQORA_CONFIG_HOME=<path>` to change it |

The file is JSON keyed by API URL. If you are logged in to multiple environments (production, staging, PR preview), each has its own entry. The scripts pick the entry matching `AQORA_API_URL` (default `https://aqora.io`), with the URL normalized to have a trailing slash. When `aqora auth token` is used, the CLI handles the URL matching and refresh internally; when the direct file read is used (fallback path), the scripts match the URL themselves.

## CI and Service Accounts

Generate a personal access token from the aqora.io settings page, then export it:

```
export AQORA_TOKEN=aqora_pat_xxx
```

Rotate tokens on a regular schedule. A token scoped to `workspace:read` and `workspace:execute` is enough for this skill.

## Custom Deployments

For staging or on-premise aqora deployments, override the API endpoint:

```
export AQORA_API_URL=https://staging.aqora.io
```

`list-workspaces.sh` honors this variable. `execute-code.py` uses the URL returned by the list script, so it follows automatically. When `aqora auth token` is the active path, the scripts pass `--url "$AQORA_API_URL"` so the CLI returns the correct session's token.

## Token Refresh

Before `aqora auth token` existed, the skill's scripts read the stored `access_token` directly and did not trigger refresh. Tokens expired after roughly 24 hours and users had to rerun `aqora login`.

With `aqora auth token` as the preferred path, the CLI refreshes on demand using the stored `refresh_token`. The scripts delegate refresh entirely to the CLI, so users stay signed in until their refresh token itself expires (roughly two weeks).

If a call still fails with a 401 or "session not found" error, the refresh token has expired: rerun `aqora login`.

## Non-Aqora Hosts

`execute-code.py` prints a warning when the target URL is not `*.aqora.io`, `*.aqora-internal.io`, or a loopback address. This is a safety check against pointing the skill at untrusted infrastructure. An unexpected warning is a signal to stop and investigate, not to dismiss.
