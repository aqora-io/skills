# Gotchas

## Remote Kernel

### Network latency adds up

Every `execute-code.sh` call is an HTTPS round-trip to aqora.io. On a slow link, twenty small calls cost more than one batched call. Batch related work into a single execution when possible.

### Connection reset mid-operation

If the workspace restarts (manual restart, idle shutdown, platform operation), in-flight execution errors out and kernel state is lost. Re-run `list-workspaces.sh` to confirm status before assuming the failure was a code bug.

### The user watches in real time

Unlike a local sandbox, the user sees cells appear in their browser as you create them. Work in small, reviewable steps. Do not dump a 200-line cell and expect the user to trust it. Narrate your plan before execution on non-trivial changes.

## Marimo

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

Command-line flags appear in `ps aux`. Pass tokens via `AQORA_TOKEN` or let the scripts fetch them from the aqora CLI credential store.

### Non-aqora URLs

`execute-code.sh` warns when pointed at a host that is not `*.aqora.io` or a loopback address. A warning you did not expect is a signal to stop and investigate, not a prompt to dismiss.

## Scripts

### `jq` is required

Both scripts need `jq` for JSON handling. If `jq` is missing, installation varies by platform: `brew install jq` on macOS, `apt-get install jq` on Debian-family Linux, `choco install jq` on Windows.

### Working directory does not matter

Scripts resolve paths relative to themselves, not to the invocation directory. You can call them from anywhere.
