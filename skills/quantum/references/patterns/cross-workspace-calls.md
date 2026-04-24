# Cross-Workspace Calls

The `aqora_cli.notebook()` pattern, with the error handling the existing workspaces omit.

## Canonical call

Inside a cell in the user's workspace:

```python
import aqora_cli as aq

sim = await aq.notebook("aqora/pennylane-simulator")
result = sim.simulate(qasm_string, shots=2048)
counts = result["counts"]
```

Three facts worth internalizing:

1. **`aq.notebook(slug)` is async.** Use `await`. Inside a marimo cell, top-level `await` works; do not wrap in `asyncio.run()`.
2. **The returned object exposes the workspace's `@app.function` cells as methods.** A simulator workspace gives you `.simulate(...)`; an optimizer gives you `.optimize(...)`; an algorithm gives you `.run_qaoa(...)` or similar. `help(ws)` lists them.
3. **Return values are plain Python dicts (or primitives).** No framework-specific objects cross the boundary.

## Defensive wrapper template

The existing orchestrator workspaces (`portfolio-optimizer`, `benchmark`) skip error handling around `aq.notebook()` calls. A dead primitive, expired auth, or a change in the downstream workspace's signature crashes the orchestrator. Do better.

```python
import aqora_cli as aq

async def call_workspace(slug: str, method: str, *args, fallback=None, **kwargs):
    """Call a method on an aqora workspace primitive with graceful fallback.

    Returns the method's result on success, the fallback's result on failure.
    Raises only if both fail.
    """
    try:
        ws = await aq.notebook(slug)
    except Exception as e:
        if fallback is None:
            raise RuntimeError(f"workspace '{slug}' unreachable and no fallback") from e
        return fallback(*args, **kwargs)

    fn = getattr(ws, method, None)
    if fn is None:
        if fallback is None:
            raise RuntimeError(f"workspace '{slug}' has no method '{method}'")
        return fallback(*args, **kwargs)

    try:
        return fn(*args, **kwargs)
    except Exception as e:
        if fallback is None:
            raise
        print(f"Warning: {slug}.{method} failed, using local fallback: {e}")
        return fallback(*args, **kwargs)
```

Usage with a local fallback:

```python
def _local_simulate(qasm, shots):
    # numpy-only implementation lives in this workspace
    ...

result = await call_workspace(
    "aqora/pennylane-simulator",
    "simulate",
    qasm_string,
    shots=2048,
    fallback=_local_simulate,
)
```

Usage without a fallback (acceptable when there is no local path):

```python
result = await call_workspace(
    "aqora/gate-optimizer",
    "optimize",
    qasm_string,
    target="depth",
)
```

## Introspecting a primitive at runtime

Before wiring a newly found primitive into an orchestrator, verify its surface. From inside a scratch cell:

```python
import aqora_cli as aq

ws = await aq.notebook("aqora/<slug>")
help(ws)
# Or, for a single method:
help(ws.simulate)
```

`help()` reads the live `@app.function` signatures and docstrings. It is always truthful even if the workspace was updated between your last read and now. Prefer this over reading the `readme.py` source, which can drift.

## Common failure modes

| Failure | Likely cause | Fix |
| :------ | :----------- | :-- |
| `aq.notebook(slug)` raises | Workspace does not exist, or owner is wrong. | Double-check the slug with `describe-workspace.sh`. |
| `aq.notebook` succeeds, method not found | Workspace does not expose that method as `@app.function`. | `help(ws)` to list the real exports. |
| Method call raises deep inside the downstream | Malformed input (often QASM). | Validate the QASM string before the call; pretty-print errors. |
| Method call succeeds but returns unexpected shape | The workspace does not follow the interface contract. | Read the workspace's source and adapt, or request the author fix the contract. |
| Call hangs | Downstream workspace's runner was stopped by idle shutdown. | Tell the user; they restart from the aqora UI. |

## Multiple workspaces in one orchestration

Composition is straightforward because `aqora_cli.notebook()` is just a Python call. Chain as many primitives as the pipeline needs:

```python
# 1. Optimize the circuit
opt_result = await call_workspace(
    "aqora/gate-optimizer",
    "optimize",
    raw_qasm,
    target="depth",
)

# 2. Simulate the optimized circuit
sim_result = await call_workspace(
    "aqora/pennylane-simulator",
    "simulate",
    opt_result["qasm"],
    shots=2048,
)

# 3. Compare to the unoptimized circuit
baseline_result = await call_workspace(
    "aqora/pennylane-simulator",
    "simulate",
    raw_qasm,
    shots=2048,
)
```

Each call is independent, each has its own fallback. If the optimizer workspace is down, the baseline path still works. That is the point of defensive wrappers.

## When not to use `aqora_cli.notebook()`

- **Pure local work.** Running a circuit on the user's machine with a cheap numpy simulator is faster than a cross-workspace call for tiny circuits (below 6 qubits, below 100 shots).
- **Hot variational loops.** If the outer loop runs hundreds of iterations with tight circuit changes, the cross-workspace round-trip dominates. Consider either (a) colocating the outer loop in the simulator workspace itself, or (b) calling the simulator in large batches.
- **During development.** Inline the logic while iterating on the algorithm. Promote to a workspace once the shape is stable.

## When to treat this as tech debt

The current `aqora_cli.notebook()` contract works but has some sharp edges (async everywhere, minimal error info when things go wrong, no explicit version pinning of primitives). Watch for:

- Primitive updates that break callers silently. Interface changes in a downstream workspace are not caught by the skill; they surface as runtime errors.
- Version pinning. Until aqora exposes workspace versions through `aq.notebook(slug, version=...)`, orchestrators call "latest" implicitly.

The skill's search defaults plus the defensive wrapper mitigate most of this today. A proper versioning story is a future aqora platform improvement.
