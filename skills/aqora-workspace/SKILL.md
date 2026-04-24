---
name: aqora-workspace
description: Work inside a running aqora-hosted marimo workspace. List workspaces, execute code in the live kernel, create and edit cells. Use this skill whenever the user mentions an aqora workspace, aqora.io, or a marimo notebook on aqora, or wants to build, explore, debug, or modify anything in an aqora-hosted notebook, even if they do not explicitly say "workspace".
---

# Aqora Workspace Protocol

This skill gives you full access to a running aqora workspace. Aqora workspaces are marimo notebooks hosted on aqora.io infrastructure. You can read cell code, create and edit cells, install packages, run cells, and inspect the reactive graph, all through the bundled scripts.

## Philosophy

Aqora workspaces are reactive notebooks. Cells are the fundamental unit of computation, connected by the variables they define and reference. When a cell runs, marimo re-executes downstream cells automatically. You have full access to the running kernel.

- Cells are your main lever. Use them to break up work and choose when to bring the human into the loop.
- Understand intent first. When clear, act. When ambiguous, clarify.
- Follow existing signal. Check imports, `pyproject.toml`, and existing cells before reaching for external tools.
- Stay focused. Build first, polish later.

## Prerequisites

### Authentication

Aqora workspaces require authentication. Set up credentials one of two ways:

1. Install the aqora CLI and run `aqora login`. The scripts read cached credentials automatically.
2. Set the `AQORA_TOKEN` environment variable to a personal access token.

If neither is present, the scripts fail with a clear error. See [references/auth.md](references/auth.md) for the full story.

### Dependencies

- `list-workspaces.sh` needs `bash`, `curl`, and `jq` on your `PATH`.
- `execute-code.py` needs Python 3.10+ plus `httpx` and `websockets`. If `uv` is installed (recommended), the script is fully self-contained thanks to PEP 723 inline metadata: just run it. Without `uv`, run `pip install httpx websockets` once.

No marimo installation is needed locally: all code runs in the remote kernel.

## Operations

Two core operations: list workspaces and execute code.

| Operation | Script |
| :-------- | :----- |
| List workspaces | `bash scripts/list-workspaces.sh` |
| Execute code (inline) | `scripts/execute-code.py --workspace <id> -c "code"` |
| Execute code (multiline) | `scripts/execute-code.py --workspace <id> <<'EOF' ... EOF` |
| Execute code (from file) | `scripts/execute-code.py --workspace <id> script.py` |
| Execute code (by URL) | `scripts/execute-code.py --url https://... -c "code"` |

### Listing Workspaces

`list-workspaces.sh` returns JSON with workspaces owned by the current viewer. Each entry includes `id`, `slug`, `name`, `shortDescription`, plus two runner slots: `editor_url` / `editor_command` and `viewer_url` / `viewer_command`. A non-null `*_url` means a kernel is live for that mode. Both null means nothing is running and the workspace has to be started from the aqora UI first. See [references/workspace-lifecycle.md](references/workspace-lifecycle.md).

Filter by id to get one workspace, or add `--url-only` when scripting:

```bash
bash scripts/list-workspaces.sh --id ws_abc --url-only
```

### Executing Code

Every `execute-code.py` call runs inside the remote marimo kernel. All cell variables are in scope. `print(df.head())` just works. Nothing you define persists between calls, but you can freely introspect notebook state: inspect variables, test snippets, check types and shapes. Use this to explore and validate before committing anything to the notebook, then create cells to persist state and make results visible to the user.

Under the hood, `execute-code.py` opens a short-lived WebSocket to register a session with the runner, POSTs your code to the agent-only `/api/kernel/execute` endpoint, streams results back, and closes. Stdout from the kernel is mirrored to your stdout, stderr to your stderr. All of this is transparent from the skill's point of view: treat the script as "run this code, get its output."

To mutate the notebook's dataflow graph, use `marimo._code_mode`:

```python
import marimo._code_mode as cm

async with cm.get_context() as ctx:
    cid = ctx.create_cell("x = 1")
    ctx.packages.add("pandas")
    ctx.run_cell(cid)
```

You **must** use `async with`. Without it, operations silently do nothing. All `ctx.*` methods are synchronous. They queue operations that flush on context exit. Do not `await` them.

The kernel supports top-level `await`, so use `async with` at the top level. Do not wrap calls in `async def main(): ...` with `asyncio.run()`. It is unnecessary and easy to get wrong (`async with` cannot follow `def name():` on the same line, so a `-c` one-liner produces a `SyntaxError`).

Cells are not auto-executed. `create_cell` and `edit_cell` are structural changes only. Call `run_cell` to queue execution.

`code_mode` is the tested, safe API for notebook mutations. Prefer it for all structural changes. You have access to deeper marimo internals from the kernel, but treat that as a last resort.

### First Step: Explore the API

The `code_mode` API can change between marimo versions. Explore it at the start of each session:

```python
import marimo._code_mode as cm
help(cm)
```

## Guard Rails

Skip these and the workspace breaks.

- **Install packages via `ctx.packages.add()`, not `uv add` or `pip`.** The code API handles kernel restarts and dependency resolution correctly.
- **Custom widgets are anywidget.** Composed `mo.ui` is fine for simple forms and controls. For bespoke visuals, use anywidget with HTML, CSS, and JS.
- **Never write to the workspace's `.py` file directly while a session is running.** The kernel owns it.
- **No temp-file dependencies in cells.** `pathlib.Path("/tmp/...")` inside a cell is a bug. Temp state does not survive between kernel restarts.
- **Avoid empty cells.** Prefer `edit_cell` into existing empty cells over creating new ones. Clean up any cell that ends up empty after an edit.
- **Deletions are destructive.** Deleting a cell removes its variables from kernel memory. Restoring means recreating the cell and re-running it and its dependents.
- **Installing packages changes the project state.** `ctx.packages.add()` mutates the workspace's dependency set. Confirm when it is not obvious from context.

## Widgets and Reactivity

Anywidget state (traitlets) lives outside marimo's reactive graph. To hook a widget trait into the graph, pick one strategy per widget. Never mix them.

- `mo.state` plus `.observe()` lets you bridge specific traits by hand. This is the default.
- `mo.ui.anywidget()` wraps all synced traits into one reactive `.value`. Convenient but coarser.

## Keep in Mind

- **The user may be editing the workspace too.** State can change between your calls. Re-inspect notebook state when it has been a while since you last looked.
- **Network round-trips matter.** Unlike a local marimo, every `execute-code.sh` call goes to aqora.io. Batch related operations into a single call when possible.
- **Workspace sessions can be killed by the platform** for inactivity or resource limits. If execution starts failing with connection errors, check status with `list-workspaces.sh`. See [references/workspace-lifecycle.md](references/workspace-lifecycle.md).
- **The user is watching live.** Cells appear in the user's browser as you create them. Work in small, reviewable steps. Do not dump a 200-line cell and expect trust.
- **Every `execute-code.py` call is a full WebSocket plus HTTP round-trip.** The overhead is small per call but not zero. Group related work into a single call when possible.

## References

- [references/auth.md](references/auth.md) handles credentials, token rotation, and custom deployments.
- [references/workspace-lifecycle.md](references/workspace-lifecycle.md) covers starting, stopping, and session semantics.
- [references/gotchas.md](references/gotchas.md) collects remote-kernel and marimo-specific pitfalls.
