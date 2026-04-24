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

### Known issues

- `list-workspaces.sh` and `execute-code.py` read the stored access token from the aqora CLI credentials file directly. When the token expires (roughly every 24 hours), calls fail with `INVALID_AUTHORIZATION` and the user must re-run `aqora login`. The clean fix is an `aqora auth token` subcommand on the CLI that handles refresh transparently. A draft PR is open against `aqora-io/cli` tracking this.
- The longer-term goal is a stateless `runWorkspaceCode` mutation in the aqora GraphQL schema (tracked in https://github.com/aqora-io/skills/issues/1). With that mutation in place, `execute-code.py` can collapse to a single GraphQL call, drop the WebSocket dance, and eliminate the Python runtime dependency.

## [0.1.0]

Initial release. (Pending.)
