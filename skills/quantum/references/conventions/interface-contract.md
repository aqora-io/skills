# Interface Contract

This is the Python surface a published primitive should expose so that other workspaces can call it via `aqora_cli.notebook()`. The contract lives in marimo's `@app.function` decorator: every cell that should be externally callable is decorated, type-annotated, documented, and returns a dict with well-known keys.

A workspace that does not follow this contract will not compose cleanly. Agents can still use it, but only by reading its cells and adapting. That is why the promotion checklist insists on it.

## Simulator (`role:simulator`)

```python
@app.function
def simulate(
    qasm: str,
    shots: int = 1024,
    noise_model: dict | None = None,
) -> dict:
    """Simulate a quantum circuit and return measurement counts.

    Args:
        qasm: OPENQASM 2.0 circuit string.
        shots: Number of measurement shots.
        noise_model: Optional noise specification. Shape depends on the framework;
            if the simulator does not support noise, raise NotImplementedError.

    Returns:
        {
            "counts": {"<bitstring>": int, ...},   # measurement outcomes
            "statevector": list[complex] | None,   # full state if cheap to compute
            "shots": int,                          # copy of the input for traceability
        }
    """
```

Rules:

- `counts` bitstring endianness must be documented in the docstring or the cell's markdown header.
- `statevector` may be `None` for shot-only simulators.
- Do not add framework-specific kwargs to the signature. Keep the contract portable.

## Optimizer (`role:optimizer`)

```python
@app.function
def optimize(
    qasm: str,
    target: str = "depth",
) -> dict:
    """Transform a circuit to reduce gate count, depth, or routing cost.

    Args:
        qasm: OPENQASM 2.0 circuit string.
        target: "depth", "gates", or "routing". Implementations may add their own
            values, but "depth" must always be supported.

    Returns:
        {
            "qasm": str,                # optimized OPENQASM 2.0
            "before": {"gates": int, "depth": int},
            "after": {"gates": int, "depth": int},
            "target": str,              # echo of the input for traceability
        }
    """
```

Rules:

- Input and output are both QASM 2.0 strings.
- `before` and `after` stats are always present, even if `after == before`.
- The optimizer must be semantics-preserving. If it approximates (as some compilation passes do), raise instead of silently changing behavior.

## Algorithm (`role:algorithm`)

Algorithm workspaces vary more than simulators or optimizers, because they take problem-specific inputs. The convention is a single `@app.function` whose name reflects the algorithm (e.g., `run_qaoa_portfolio`), with a return shape that includes:

```python
@app.function
def run_<algorithm>(
    # problem-specific positional or keyword inputs
    ...
    # always include these:
    simulator: str = "Local (numpy)",
    shots: int = 2048,
) -> dict:
    """
    Returns:
        {
            "solution": Any,            # canonical answer (bitstring, energy, portfolio, ...)
            "counts": {...} | None,     # last-execution measurement outcomes
            "trajectory": list | None,  # for variational, history of (iter, value)
            "metadata": {
                "algorithm": str,       # "qaoa", "vqe", etc.
                "shots": int,
                "simulator": str,
            },
        }
    """
```

Rules:

- Always accept a `simulator` string that selects a downstream simulator primitive. Include `"Local (numpy)"` as a fallback that requires no cross-workspace call.
- Always include `shots` in the signature, even if the algorithm technically does not care (for consistency across the catalog).
- `solution` is the canonical answer whatever that means for the problem. Document its shape in the docstring.

## Mitigation (`role:mitigation`)

```python
@app.function
def mitigate(
    qasm: str,
    simulator: str,
    shots: int = 1024,
    technique: str = "zne",
    parameters: dict | None = None,
) -> dict:
    """Run a circuit with error mitigation and return corrected outcomes.

    Args:
        qasm: OPENQASM 2.0 circuit string.
        simulator: downstream simulator workspace slug (e.g., "aqora/pennylane-simulator")
            or "Local (numpy)".
        shots: shots per underlying execution.
        technique: "zne", "pec", "readout-correction", or "dd".
        parameters: technique-specific kwargs (e.g., {"noise_factors": [1, 2, 3]} for zne).

    Returns:
        {
            "counts": {...},            # mitigated measurement outcomes
            "raw_counts": {...} | list, # underlying uncorrected counts
            "technique": str,
            "parameters": dict,
            "shots_total": int,         # total shots across all underlying executions
        }
    """
```

## Benchmark (`role:benchmark`)

Benchmarks typically do not need a strict `@app.function` contract because they are consumers, not primitives. If a benchmark workspace wants to expose its comparison as a reusable function, the signature should accept a list of primitive slugs to compare and return a results table.

## Notes on signatures

- **Use `dict | None`** over `Optional[dict]`. Matches modern Python style and is what the existing simulators use.
- **Do not expose numpy arrays in return values.** Convert to lists at the boundary. Pickle / arrow / serde across workspaces is not guaranteed.
- **Document bitstring conventions.** "Qubit 0 is the rightmost character of the bitstring key" (little-endian) or "Qubit 0 is the leftmost" (big-endian). Simulators disagree; pick one, write it down.
- **Raise, do not return error dicts.** If the simulation fails, raise a clear exception. Consumers can wrap with try/except. Returning `{"error": "..."}` is an anti-pattern.
