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

### Known issues

- The longer-term goal is a stateless `runWorkspaceCode` mutation in the aqora GraphQL schema (tracked in https://github.com/aqora-io/skills/issues/1). With that mutation in place, `execute-code.py` can collapse to a single GraphQL call, drop the WebSocket dance, and eliminate the Python runtime dependency.
- In edit mode, marimo refuses a second WebSocket connection when a frontend is already attached (see `_can_connect` in the upstream `ws_endpoint.py`). If the user has the workspace open in a browser, `execute-code.py` may fail with `MARIMO_ALREADY_CONNECTED`. Close the browser tab or use a workspace that is not actively open. Long-term fix would be using kiosk or RTC mode where available.

## [0.1.0]

Initial release. (Pending.)
