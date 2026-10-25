# Config Files

The configuration surfaces around an aqora-hosted marimo workspace and around the skill's own scripts. Knowing which file controls what saves debugging time.

## Inside a workspace: `pyproject.toml`

Every aqora workspace has a `pyproject.toml` alongside its `readme.py`. It declares the workspace's Python dependencies and basic metadata.

Typical shape:

```toml
[project]
name = "my-workspace"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = [
    "marimo>=0.11",
    "pennylane>=0.35",
    "numpy>=1.26",
]

[tool.marimo]
# Optional marimo-specific settings
```

Rules:

- **Let `ctx.packages.add()` manage dependencies in-session.** When the agent adds a package via `marimo._code_mode.get_context().packages.add("scipy")`, marimo updates `pyproject.toml` and the lockfile for you. Do not hand-edit `pyproject.toml` inside a running workspace; the kernel owns it.
- **Pin versions when it matters.** For reproducibility (published primitives, use-case workspaces), pin to compatible ranges (`pennylane>=0.35,<0.40`). For exploratory notebooks, unpinned `pennylane` is fine.
- **Keep `requires-python` honest.** If you use `typing.Self`, `match`, or `str | None` union syntax, require Python 3.10+.

## Inside a workspace: `.aqora/` directory

Workspaces may carry an `.aqora/` directory at the root for aqora-specific configuration. Contents vary but typically include cached lockfiles, workspace metadata, and data the kubimo runner uses to orchestrate the kernel. Treat `.aqora/` as kernel-owned: do not hand-edit unless you know what you are doing.

## Inside a workspace: `marimo.toml`

Marimo's configuration file, often inside `.aqora/` or at the workspace root. Controls editor defaults, theme, display preferences. Most workspaces do not need a custom `marimo.toml`; the aqora runner ships sensible defaults. When you do need one, common tweaks:

```toml
[display]
theme = "dark"
dataframes = "rich"       # or "plain"

[runtime]
auto_instantiate = true   # cells run on open
auto_reload = "lazy"      # on file change
```

Changes take effect when the runner restarts.

## PEP 723 inline script metadata

For standalone scripts that are not full workspaces (like `execute-code.py` in this skill), PEP 723 inline metadata declares dependencies in the script itself:

```python
#!/usr/bin/env -S uv run --quiet --script
# /// script
# requires-python = ">=3.10"
# dependencies = [
#   "httpx>=0.27",
#   "websockets>=12",
# ]
# ///
"""Module docstring."""

import httpx
...
```

When run via `uv run script.py` (or with the `uv run --script` shebang), `uv` creates an ephemeral environment with the declared dependencies. Without `uv`, the user does `pip install httpx>=0.27 websockets>=12` once and runs `python script.py`.

Use inline metadata for:

- Standalone scripts in the skill's `scripts/` directory.
- Small utility scripts that are not part of a workspace.
- Anything a user or agent might run outside a marimo kernel.

Do NOT use inline metadata inside a marimo `readme.py`. Workspace dependencies live in `pyproject.toml`, not inline in the cells.

## Skill-side environment variables

The skill's scripts honor these environment variables:

| Variable | Purpose | Default |
| :------- | :------ | :------ |
| `AQORA_TOKEN` | Explicit access token. Preferred for CI. | unset |
| `AQORA_API_URL` | Aqora API endpoint. | `https://aqora.io` |
| `AQORA_CONFIG_HOME` | Aqora CLI config directory. | macOS: `~/Library/Application Support/aqora`; Linux: `~/.local/share/aqora` (honors `XDG_DATA_HOME`) |
| `EXECUTE_CODE_LOG` | Path to append one ISO timestamp per `execute-code.py` call. Useful for eval / audit. | unset |

Set them in your shell session or in a `.env` file sourced by your environment. The scripts do not read `.env` themselves; use a tool like `direnv` or manually `source .env`.

## Custom aqora deployments

For staging, PR preview, or on-prem:

```bash
export AQORA_API_URL=https://staging.aqora.io
aqora login   # logs in to staging
# the skill's scripts now target staging
```

The aqora CLI's credentials file is keyed by API URL, so multiple environments (production, staging, PR previews) coexist in one `credentials.json`. The scripts match the entry based on `AQORA_API_URL`.

## The skill repo's own config

When working on the skill repo itself (as opposed to authoring workspaces):

- **`.claude-plugin/plugin.json`**: single-plugin manifest for the Claude Code installation flow.
- **`.claude-plugin/marketplace.json`**: marketplace manifest that lists the plugin.
- **`.editorconfig`**: line endings, indent style, final newline. Honored by most editors.
- **`.github/workflows/validate.yml`**: CI that runs the repo's validator and shellcheck.
- **`scripts/validate-skills.sh`**: the validator. Run locally before pushing.
- **`CLAUDE.md`**: project-level instructions for Claude Code contributors. Includes the no-em-dash rule.
- **`CONTRIBUTING.md`**: authoring conventions for skills in this repo.

None of these need to change when authoring a workspace. They are for working on the skill repo itself.

## Debugging config issues

A few common symptoms and fixes:

| Symptom | Likely cause | Fix |
| :------ | :----------- | :-- |
| `Error: no aqora token available` | `aqora login` has not been run or `AQORA_TOKEN` is unset. | Run `aqora login`. |
| `INVALID_AUTHORIZATION` on every call | Stored `access_token` expired. | Run `aqora login` (pre-`aqora auth token`) or upgrade aqora-cli. |
| `ModuleNotFoundError` inside a workspace cell | Dependency not in `pyproject.toml`. | `ctx.packages.add("missing-pkg")` from code mode. |
| `ModuleNotFoundError` running `execute-code.py` | `uv` not installed, or `pip install httpx websockets` never ran. | Install `uv` (recommended) or install the two deps. |
| Staging token used against production | `AQORA_API_URL` pointing at one environment while `aqora login` ran against another. | Re-run `aqora login` with the right `AQORA_API_URL` in the environment. |
| `MARIMO_ALREADY_CONNECTED` on WS open | Browser tab still open against the workspace, blocking `execute-code.py`. | Close the browser tab; retry. |
