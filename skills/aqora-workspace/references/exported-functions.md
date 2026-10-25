# Exported Functions

How to expose a workspace's functionality to other workspaces via `@app.function`. This is the export mechanism that `aqora_cli.notebook(slug)` uses on the consumer side.

## The decorator

Any cell whose purpose is "expose a callable to other workspaces" is decorated with `@app.function`:

```python
@app.function
def simulate(qasm: str, shots: int = 1024) -> dict:
    """Simulate a circuit and return counts."""
    ...
    return {"counts": ..., "shots": shots}
```

The function's name becomes the method name on the `aq.notebook(slug)` return value. A consumer calls it like:

```python
import aqora_cli as aq

sim = await aq.notebook("aqora/my-simulator")
result = sim.simulate(qasm_string, shots=2048)
```

Rules:

- **One function per decorated cell.** Do not stack multiple `def`s inside a single `@app.function` cell.
- **The function must be self-contained.** It can reference module-level names from the notebook (other cells' outputs, imports), but not local variables defined only in other cells.
- **Private helpers stay un-decorated.** Functions that are implementation details (e.g., `_parse_qasm`, `_apply_gate`) live in a regular cell, not a `@app.function` cell. They should also be prefixed with `_` so marimo does not export them even locally to other cells within the notebook.

## Type-annotated signatures

Always annotate inputs and the return type. Other workspaces and agents read these to decide whether and how to call the function.

Good:

```python
@app.function
def optimize(qasm: str, target: str = "depth") -> dict:
    """Transform a circuit to reduce gate count or depth."""
    ...
```

Avoid:

```python
@app.function
def optimize(qasm, target="depth"):   # no types
    ...
```

Annotations to prefer:

- `str`, `int`, `float`, `bool` for primitives.
- `list[T]`, `dict[K, V]`, `tuple[T1, T2, ...]` for collections.
- `dict | None` for nullable dicts (modern style, what the existing simulators use).
- `Any` only when you genuinely cannot narrow.

Numpy arrays, pandas frames, and framework-specific types (qiskit `QuantumCircuit`, pennylane `QNode`) should NOT cross workspace boundaries. Convert to plain Python / JSON-compatible structures at the function boundary.

## Docstrings

The docstring is the API documentation that `help(ws)` shows to consumers. Use it.

Required content:

- One-line summary.
- `Args:` section naming each parameter and describing its expected format (especially for stringly-typed parameters like `qasm`, `target`, `technique`).
- `Returns:` section describing the shape of the return value. If returning a dict, list the keys and their types.
- `Raises:` section (if non-obvious) naming the exceptions a caller should handle.

Template:

```python
@app.function
def simulate(qasm: str, shots: int = 1024, noise_model: dict | None = None) -> dict:
    """Simulate a quantum circuit and return measurement outcomes.

    Args:
        qasm: OPENQASM 2.0 circuit string. Bitstring endianness:
            qubit 0 is the rightmost character of each bitstring key.
        shots: Number of measurement shots. Default 1024.
        noise_model: Optional noise specification. Shape is
            framework-specific; this simulator treats None as noise-free.

    Returns:
        {
            "counts": dict[str, int],      # bitstring to count
            "statevector": list | None,    # full state if cheap
            "shots": int,                   # copy of input
        }

    Raises:
        ValueError: if `qasm` is not valid OPENQASM 2.0.
    """
    ...
```

## Return shape conventions

Align with the role your workspace plays. The `quantum` skill's [interface-contract.md](../../../quantum/references/conventions/interface-contract.md) has role-specific shapes (simulator, optimizer, algorithm, mitigation). At a minimum, return dicts with:

- Well-known keys for the role (e.g., `counts`, `statevector`, `shots` for simulators).
- JSON-serializable values: lists, dicts, primitives, strings. Avoid numpy arrays, sets, custom classes.
- A `metadata` sub-dict for anything not covered by the role-specific contract.

Never return error dicts. If the operation fails, raise a clear exception. Consumers can wrap with try/except.

## Async

`@app.function` supports both sync and async functions. A simple rule:

- **Sync**: simple, CPU-bound, deterministic. Parsing QASM, building a circuit, computing an expectation value.
- **Async**: anything that awaits. Calling another workspace (`await aq.notebook(...)`), HTTP requests, slow I/O.

From the consumer side, the consumer does `await ws.method(...)` for async functions. Marimo handles the dispatch. Inside a consumer cell, top-level `await` works; do not wrap in `asyncio.run`.

## How `aqora_cli.notebook()` sees them

When you do `ws = await aq.notebook("aqora/my-simulator")`:

- The runner for that workspace starts (or attaches if already running).
- Every `@app.function`-decorated cell in its notebook is exposed as a method on `ws`.
- The method's signature and docstring are preserved. `help(ws.simulate)` shows them.
- Calls are sent over the aqora runtime's transport (details handled internally by `aqora_cli`).
- Return values come back as plain Python objects.

Implications:

- **`help(ws)` is the source of truth.** It reflects the live code. Prefer it over reading the workspace's `readme.py` source, which may be stale.
- **Private helpers do not appear on `ws`.** Only `@app.function` cells are exposed. That is why the `_` prefix matters.
- **Signatures are truthful.** If a consumer passes the wrong type, the call will fail with a standard Python TypeError inside the callee, not a silent behavior change.

## Anti-patterns

- **Exporting cells that have side effects.** A `@app.function` that writes a file, plots to the browser, or mutates global state is hard to compose. Keep exports pure where feasible.
- **Exporting functions that read `mo.ui.*` values.** The UI element's value is only meaningful inside the owning workspace's session. Pass such values explicitly as function parameters if a consumer needs them.
- **Overloading a single export.** If `run(mode="simulate")` and `run(mode="optimize")` do completely different things, they are two exports. Split: `simulate()` and `optimize()`.
- **Returning objects that cannot be serialized.** Custom classes, open file handles, numpy arrays. Consumers typically cannot use them.

## Quick self-check before shipping

- Does every public entry point have `@app.function`, type annotations, and a docstring?
- Are all private helpers prefixed with `_` and un-decorated?
- Does `help(my_app.simulate)` read usefully to someone seeing the workspace for the first time?
- Does the return shape match the role's contract in the `quantum` skill's interface-contract reference?
- Is everything that crosses the boundary JSON-serializable?

Five yeses means the workspace is ready for external consumption.
