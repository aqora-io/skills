# Changelog

All notable changes to this repository are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Initial repository scaffold.
- `aqora-workspace` skill for pair-programming inside a live aqora-hosted marimo workspace.
- `execute-code.py`: Python script that performs the full WebSocket plus HTTP handshake (GET runner page, scrape `Marimo-Server-Token`, open WebSocket to register `Marimo-Session-Id`, POST to `/api/kernel/execute`, stream SSE results). Runs code end to end in a live aqora workspace and mirrors stdout/stderr to the caller. Uses `uv` with PEP 723 inline dependencies (`httpx`, `websockets`) for zero-install when `uv` is available.
- Validation script (`scripts/validate-skills.sh`) and GitHub Actions workflow.
- Claude Code plugin and marketplace manifests.
- CLAUDE.md for contributors using Claude Code.

### Changed

- `execute-code.sh` pivoted to `execute-code.py`. The bash version could not complete the handshake because registering a `Marimo-Session-Id` requires a WebSocket connection. Pure `bash + curl` does not cover WebSockets. Python plus `websockets` does, and Python is already ubiquitous in the aqora ecosystem (the CLI itself is pip-installable).
- `execute-code.py` gained a `--persist` flag. `marimo._code_mode` mutations (`create_cell`, `edit_cell`, `delete_cell`, `move_cell`) update the kernel's in-memory graph but do not write the notebook `.py` file. Without `--persist`, cell outputs broadcast to the browser while editors keep showing the stale file contents, leaving users with empty-looking cells. The flag appends a small epilogue that regenerates the file from kernel state. The `aqora-workspace` SKILL body now treats `--persist` as the default for any mutation call, with a new `references/persisting-cells.md` for depth and a matching entry in `references/gotchas.md`.
- `list-workspaces.sh` and `execute-code.py` now try the refresh-aware `aqora auth token` command before falling back to reading `credentials.json` directly. On aqora-cli versions that include the `auth` subcommand (landing from aqora-io/cli#187), expired access tokens refresh transparently via the stored refresh token. Older CLIs still work via the file-read fallback. This closes the roughly-24-hour "re-run `aqora login`" footgun for users on up-to-date CLIs.

### Fixed

- `execute-code.py` now authenticates to the workspace runner with the editor URL's token as an `Authorization: Bearer` header, matching the contract `aqora pair` uses, instead of scraping `Marimo-Server-Token` from the runner page and replaying the session cookie. It attaches to the notebook's live browser session when there is one (so `MARIMO_ALREADY_CONNECTED` no longer blocks agents while the user has the notebook open) and otherwise opens a private session and waits for `kernel-ready` before executing. Previously the script POSTed before the kernel had registered its session, which failed with `Invalid session id`. Fixes [#1](https://github.com/aqora-io/skills/issues/1).
- `execute-code.py --url` no longer warns about `kubimo.org`, the runner host the aqora API now hands out, and URLs resolved through `--workspace` skip the host check entirely.

### Known issues

- When no browser has the notebook open, `execute-code.py` still needs a WebSocket (and so Python plus `websockets`) to open a private marimo session. A stateless execute endpoint on the aqora platform would remove that dependency.

## [0.1.0]

Initial release. (Pending.)
