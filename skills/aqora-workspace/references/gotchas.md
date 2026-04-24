# Gotchas

## Remote Kernel

### Network latency adds up

Every `execute-code.py` call is a WebSocket handshake plus an HTTPS round-trip to aqora.io. On a slow link, twenty small calls cost more than one batched call. Batch related work into a single execution when possible.

### Connection reset mid-operation

If the workspace restarts (manual restart, idle shutdown, platform operation), in-flight execution errors out and kernel state is lost. Re-run `list-workspaces.sh` to confirm status before assuming the failure was a code bug.

### The user watches in real time

Unlike a local sandbox, the user sees cells appear in their browser as you create them. Work in small, reviewable steps. Do not dump a 200-line cell and expect the user to trust it. Narrate your plan before execution on non-trivial changes.

## Marimo

### `code_mode` mutations do not persist to the file

`create_cell`, `edit_cell`, `delete_cell`, and `move_cell` update the kernel's in-memory graph but do not write the notebook `.py` file. Cell outputs broadcast to the browser correctly, so markdown and plots render, but the cell editors keep showing the pre-mutation file contents. Users see rendered outputs overlaid on empty editors and assume the notebook is broken.

Fix: pass `--persist` to `execute-code.py` on every mutation call. See [persisting-cells.md](persisting-cells.md).

### `name="setup"` isolates the cell's scope

A cell created with `name="setup"` becomes a marimo setup cell. Its top-level imports and definitions are not shared with the rest of the notebook. Downstream cells fail with `NameError` even though the setup cell ran without error. For a plain shared-imports cell, use any other name (or no name).

### `mo.stop()` only gates its own cell

`mo.stop()` halts the cell it lives in. To gate downstream cells behind a `mo.ui.run_button`, the stop cell must export a variable that downstream cells depend on. If stop fires, the variable is never defined, so dependent cells do not run. A bare `mo.stop()` cell with no exports does not prevent downstream cells from executing.

### Variables prefixed with `_` are cell-private

Marimo treats `_name` as cell-local and does not export it. If a helper needs to be reused by another cell, drop the underscore.

### UI display cells must be separate from creation cells

Marimo strips unused variables from return tuples as dead-code elimination. If you create a UI element and its layout (`form = mo.vstack(...)`) in the same cell, and no downstream cell reads `form`, marimo removes it from the return tuple and the UI fails to render.

Fix: split into two cells. A creation cell returns the UI element. A display cell consumes it and calls `mo.vstack([...])` with a bare `return`.

### Qiskit 2.x removed `QuantumCircuit.qasm()`

Use `from qiskit.qasm2 import dumps as qasm2_dumps` instead. The forthcoming `quantum` skill will cover broader quantum-computing guidance.

## Auth

### Do not pass tokens as flags

Command-line flags appear in `ps aux`. Pass tokens via `AQORA_TOKEN`, not `--token`.

### Non-aqora URLs

`execute-code.py` warns when pointed at a host that is not `*.aqora.io`, `*.aqora-internal.io`, or a loopback address. A warning you did not expect is a signal to stop and investigate, not a prompt to dismiss.

### Token refresh

The stored aqora access token has a short lifetime (roughly 24 hours). The scripts read the stored `access_token` directly and do not trigger refresh. If a call fails with `INVALID_AUTHORIZATION` or HTTP 401, run `aqora login` to mint a fresh one. A follow-up `aqora auth token` subcommand is being added to the CLI to handle refresh transparently.

## Scripts

### Dependencies

- `list-workspaces.sh`: needs `bash`, `curl`, `jq`. Install `jq` with `brew install jq` on macOS, `apt-get install jq` on Debian-family Linux, `choco install jq` on Windows.
- `execute-code.py`: needs Python 3.10+ plus `httpx` and `websockets`. The recommended path is `uv` (which handles the deps via PEP 723 inline metadata): running `scripts/execute-code.py` just works. Without `uv`, run `pip install httpx websockets` once.

### Working directory does not matter

Scripts resolve paths relative to themselves, not to the invocation directory. You can call them from anywhere.
