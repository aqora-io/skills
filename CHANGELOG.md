# Changelog

All notable changes to this repository are documented here. Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Initial repository scaffold.
- `aqora-workspace` skill for pair-programming inside a live aqora-hosted marimo workspace.
- Validation script (`scripts/validate-skills.sh`) and GitHub Actions workflow.
- Claude Code plugin and marketplace manifests.
- CLAUDE.md for contributors using Claude Code.

### Known issues

- `execute-code.sh` returns HTTP 401 "Missing server token" against production aqora workspaces. The aqora runner proxy requires a skew protection token that external callers cannot currently obtain. Marimo exempts `POST /api/kernel/execute` from its own skew check, but the aqora proxy in front enforces one. This is tracked as a separate issue; once the proxy handshake is documented, the script will be updated. `list-workspaces.sh` is unaffected and works end to end.
- `list-workspaces.sh` reads the stored access token from the aqora CLI credentials file directly. When the token expires, calls fail with `INVALID_AUTHORIZATION` and the user must re-run `aqora login`. The clean fix is an `aqora auth token` subcommand on the CLI that handles refresh transparently; this is being tracked separately against `aqora-io/cli`.

## [0.1.0]

Initial release. (Pending.)
