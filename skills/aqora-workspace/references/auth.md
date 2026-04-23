# Authentication

The skill's scripts resolve credentials in this order:

1. `--token TOKEN` flag passed to the script. Avoid this; flags are visible in `ps aux`.
2. `AQORA_TOKEN` environment variable. Preferred for CI and service accounts.
3. Access token read directly from the aqora CLI's credentials file, written by `aqora login`.

If none of these produce a token, the scripts exit with a clear error.

## Interactive Login

Install the aqora CLI and log in once:

```
pip install aqora-cli
aqora login
```

`aqora login` opens a browser for OAuth and writes the resulting credentials to a file the scripts then read. No extra environment variable needed.

### Credentials File Location

The CLI stores credentials at `<config_home>/credentials.json`, where `config_home` defaults to:

| Platform | Path |
| :------- | :--- |
| macOS | `~/Library/Application Support/aqora/credentials.json` |
| Linux | `~/.local/share/aqora/credentials.json` (honors `XDG_DATA_HOME`) |
| Override | Set `AQORA_CONFIG_HOME=<path>` to change it |

The file is JSON keyed by API URL. If you are logged in to multiple environments (production, staging, PR preview), each has its own entry. The scripts pick the entry matching `AQORA_API_URL` (default `https://aqora.io`), with the URL normalized to have a trailing slash.

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

`list-workspaces.sh` honors this variable. `execute-code.sh` uses the URL returned by the list script, so it follows automatically. The credentials file lookup matches the same URL, so if you `aqora login` against staging the scripts will use that session.

## Token Refresh

The aqora CLI stores both an `access_token` and a `refresh_token`, and automatically refreshes expired access tokens when it talks to the API. The skill's scripts currently read the stored `access_token` directly and do not trigger refresh.

If a call fails with a 401 or "token expired" error, run `aqora login` again to refresh the stored credentials. A future improvement is to add an `aqora auth token` subcommand to the CLI that prints a fresh access token on stdout, which would let the scripts delegate refresh to the CLI.

## Non-Aqora Hosts

`execute-code.sh` prints a warning when the target URL is not `*.aqora.io`, `*.aqora-internal.io`, or a loopback address. This is a safety check against pointing the skill at untrusted infrastructure. An unexpected warning is a signal to stop and investigate, not to dismiss.
