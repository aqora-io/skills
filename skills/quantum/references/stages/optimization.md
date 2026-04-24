# Stage 4: Circuit Optimization

Reduce gate count, depth, or routing cost. Semantics-preserving transformations. Runs between construction and execution.

## What this stage decides

- Whether to optimize at all. Small circuits (under about 30 gates) usually do not benefit.
- Which optimizer to use based on the target metric.
- Where to run the optimizer (an aqora workspace, or an inline transpiler call).

## Find a primitive first

Three optimizer primitives exist in the catalog today:

| Slug | Under the hood | Best for |
| :--- | :------------- | :------- |
| `aqora/gate-optimizer` | pytket's FullPeepholeOptimise plus related passes | General-purpose depth and gate-count reduction. Solid default. |
| `aqora/pyzx-optimizer` | PyZX ZX-calculus rewriter | Aggressive gate reduction on circuits with many single-qubit rotations. |
| `aqora/routing-optimizer` | SABRE-style routing | Circuits that need to fit a specific hardware coupling graph. |

Search to confirm they are the latest and check for newer entrants:

```bash
bash scripts/search-workspaces.sh --tags role:optimizer,stage:optimization
```

## Compose via `aqora_cli.notebook()`

```python
import aqora_cli as aq

opt = await aq.notebook("aqora/gate-optimizer")
result = opt.optimize(qasm_string, target="depth")
optimized_qasm = result["qasm"]
print(f"depth: {result['before']['depth']} -> {result['after']['depth']}")
print(f"gates: {result['before']['gates']} -> {result['after']['gates']}")
```

Use the [defensive wrapper](../patterns/cross-workspace-calls.md) if the optimizer is critical path.

## Target choice

| `target` value | When to use | Typical optimizer fit |
| :------------- | :---------- | :-------------------- |
| `"depth"` | Hardware targets where decoherence dominates. Shallower is better even with more gates. | `aqora/gate-optimizer`, `aqora/pyzx-optimizer`. |
| `"gates"` | Simulator targets where total gate count is the cost. | `aqora/pyzx-optimizer` for rotation-heavy circuits, `aqora/gate-optimizer` for Clifford-heavy. |
| `"routing"` | Circuits being compiled to a specific coupling graph. | `aqora/routing-optimizer`. |

## When to stack optimizers

Running two optimizers in sequence sometimes beats either alone. The pattern:

```python
# 1. Gate-count reduction first
step1 = await call_workspace("aqora/pyzx-optimizer", "optimize", raw_qasm, target="gates")

# 2. Depth reduction on the smaller circuit
step2 = await call_workspace("aqora/gate-optimizer", "optimize", step1["qasm"], target="depth")

# 3. Route onto the hardware graph
step3 = await call_workspace("aqora/routing-optimizer", "optimize", step2["qasm"], target="routing")

final_qasm = step3["qasm"]
```

Rules of thumb:

- Stop at two optimizers unless you have a reason for the third. Diminishing returns are real.
- Semantics-preservation should be verified at the end. Run both the original and the optimized circuits on a simulator with the same seed and compare `counts`. If they disagree beyond shot noise, something is wrong.
- Always report `before` and `after` stats to the user. They will want to know what they paid for.

## Inline fallback

When no aqora optimizer workspace is reachable and the circuit needs help, use qiskit's transpiler:

```python
from qiskit import QuantumCircuit, transpile
from qiskit.qasm2 import loads as qasm2_loads, dumps as qasm2_dumps

def inline_optimize(qasm: str, level: int = 3) -> dict:
    """Transpile with qiskit at the given optimization level (0-3).

    Level 0: no optimization. Level 3: heaviest.
    Returns the same shape as the optimizer workspace contract.
    """
    qc = qasm2_loads(qasm)
    before_gates = len(qc.data)
    before_depth = qc.depth()

    transpiled = transpile(qc, optimization_level=level, basis_gates=["cx", "rz", "rx", "ry", "h"])
    after_gates = len(transpiled.data)
    after_depth = transpiled.depth()

    return {
        "qasm": qasm2_dumps(transpiled),
        "before": {"gates": before_gates, "depth": before_depth},
        "after": {"gates": after_gates, "depth": after_depth},
        "target": f"qiskit-level-{level}",
    }
```

For pytket inline (closer to what `aqora/gate-optimizer` does internally):

```python
from pytket.qasm import circuit_from_qasm_str, circuit_to_qasm_str
from pytket.passes import FullPeepholeOptimise

def inline_pytket_optimize(qasm: str) -> dict:
    circ = circuit_from_qasm_str(qasm)
    before_gates = circ.n_gates
    before_depth = circ.depth()
    FullPeepholeOptimise().apply(circ)
    return {
        "qasm": circuit_to_qasm_str(circ, header="qelib1"),
        "before": {"gates": before_gates, "depth": before_depth},
        "after": {"gates": circ.n_gates, "depth": circ.depth()},
        "target": "pytket-fullpeephole",
    }
```

## Heuristics for picking an optimizer

- **Circuit dominated by rotations (VQE, QAOA depth >= 3):** try `aqora/pyzx-optimizer` first. ZX calculus merges rotations aggressively.
- **Circuit dominated by Clifford gates (error correction, stabilizer simulation):** try `aqora/gate-optimizer`. PyZX has less leverage here.
- **Targeting real hardware with a non-all-to-all coupling graph:** `aqora/routing-optimizer` is the final step, regardless of what else you ran first.
- **Just want it smaller without thinking:** `aqora/gate-optimizer` with `target="depth"`.

## Gotchas

- **Some optimizers change global phase.** Do not compare optimized and original circuits by amplitude. Compare by measurement statistics.
- **Rotation angles are never exact after optimization.** Floating-point drift in angles is normal. If you depend on a specific angle (for controlled measurement), reapply it after optimization, do not assume it survives.
- **Custom gates in the original QASM can be unpacked by the optimizer.** If the circuit used `gate my_block() ...`, the optimizer may inline and optimize away the abstraction. This is usually fine but can surprise you when reading the output.
- **Optimization on tiny circuits is not worth it.** Below about 30 gates, the `before` and `after` are often identical. The cross-workspace call costs more than you save.
