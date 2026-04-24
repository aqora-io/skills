# Stage 3: Circuit Construction

Produce the gate sequence from the algorithmic framing. This stage is framework-heavy (qiskit, pennylane, pytket). Primitives are rare because canonical circuits are small enough to inline. The skill's contribution here is knowing the idioms and knowing when compact versus verbose QASM matters.

## What this stage produces

An OPENQASM 2.0 string that represents the circuit. This is the format every downstream stage expects.

For algorithms whose circuit is parameterized (QAOA, VQE, quantum-ML), the stage produces a `build_*(params)` function that takes parameters and returns QASM. The outer variational loop then calls the builder repeatedly.

## Find a primitive first

Canonical circuits (Bell state, GHZ, QFT, Trotter steps, adders) are good candidates for a small primitive workspace that exports `bell(n)`, `ghz(n)`, `qft(n)`, etc. None of these exist in the catalog yet. If the user asks for one, the skill's inline fallbacks below are enough for v0.1.

```bash
bash scripts/search-workspaces.sh --tags stage:circuit --search "<circuit name>"
```

## Framework choice

| Framework | Strengths | Use when |
| :-------- | :-------- | :------- |
| qiskit | Widest ecosystem, native IBM hardware access, strong transpiler. | Targeting IBM hardware; need transpiler levels 0 to 3; want a specific noise model. |
| pennylane | Differentiable circuits, autograd for variational. | VQE, quantum-ML, anything needing gradients. |
| pytket | Aggressive peephole optimization, multi-backend. | Circuit optimization is the goal (use `aqora/gate-optimizer` directly). |
| cirq | Google Sycamore hardware, clean Python API. | Targeting Google hardware or using cirq-specific tooling. |
| numpy | No framework, just linear algebra. | Didactic explanations, tiny circuits, fallback simulator. |

The skill defaults to qiskit or pennylane for construction because the ecosystem simulators and algorithm workspaces use both. Picking anything else forces a QASM 2.0 handoff at the boundary anyway, so the framework choice here is more about ergonomics than capability.

## Compact versus verbose decomposition

**Target a simulator: emit compact QASM.** Use `CX`, `RZ`, `RX`, `RY`, `H`, and standard Clifford gates directly. The simulator does not care about readability and compact is faster.

**Target an optimizer: emit verbose QASM.** Decompose `CX` into `CZ + H`, decompose rotations into smaller primitives where possible. This gives the optimizer workspace room to collapse redundancy. The existing `aqora/portfolio-optimizer` does this intentionally ([source comment](../../../aqora-workspace/references/persisting-cells.md) shows the pattern).

**Unsure? Emit compact, optimize if needed.** The optimizer workspaces can work with compact input too, just with less headroom.

## Inline fallbacks

### Bell state

```python
def bell_qasm() -> str:
    return """OPENQASM 2.0;
include "qelib1.inc";
qreg q[2];
creg c[2];
h q[0];
cx q[0],q[1];
measure q[0] -> c[0];
measure q[1] -> c[1];
"""
```

### GHZ state

```python
def ghz_qasm(n: int) -> str:
    lines = [
        'OPENQASM 2.0;',
        'include "qelib1.inc";',
        f'qreg q[{n}];',
        f'creg c[{n}];',
        'h q[0];',
    ]
    for i in range(n - 1):
        lines.append(f'cx q[{i}],q[{i + 1}];')
    for i in range(n):
        lines.append(f'measure q[{i}] -> c[{i}];')
    return '\n'.join(lines)
```

### Quantum Fourier Transform

```python
def qft_qasm(n: int, inverse: bool = False) -> str:
    import math
    lines = [
        'OPENQASM 2.0;',
        'include "qelib1.inc";',
        f'qreg q[{n}];',
        f'creg c[{n}];',
    ]
    pairs = list(range(n))
    if inverse:
        pairs.reverse()
    for i in pairs:
        lines.append(f'h q[{i}];')
        for j, target in enumerate(range(i + 1, n), start=2):
            theta = math.pi / (2 ** (j - 1)) * (-1 if inverse else 1)
            lines.append(f'cu1({theta}) q[{target}],q[{i}];')
    # Swap the order of the qubits to match standard QFT convention
    for i in range(n // 2):
        j = n - 1 - i
        lines.extend([
            f'cx q[{i}],q[{j}];',
            f'cx q[{j}],q[{i}];',
            f'cx q[{i}],q[{j}];',
        ])
    for i in range(n):
        lines.append(f'measure q[{i}] -> c[{i}];')
    return '\n'.join(lines)
```

### Hardware-efficient ansatz

For VQE and quantum-ML when no domain-specific ansatz is better:

```python
def hea_qasm(n_qubits: int, n_layers: int, params: list[float]) -> str:
    """Hardware-efficient ansatz: layers of single-qubit rotations plus linear entanglement.

    Total parameter count is n_qubits * 3 * n_layers.
    """
    assert len(params) == n_qubits * 3 * n_layers
    lines = [
        'OPENQASM 2.0;',
        'include "qelib1.inc";',
        f'qreg q[{n_qubits}];',
        f'creg c[{n_qubits}];',
    ]
    idx = 0
    for _ in range(n_layers):
        for q in range(n_qubits):
            lines.append(f'rx({params[idx]}) q[{q}];'); idx += 1
            lines.append(f'ry({params[idx]}) q[{q}];'); idx += 1
            lines.append(f'rz({params[idx]}) q[{q}];'); idx += 1
        for q in range(n_qubits - 1):
            lines.append(f'cx q[{q}],q[{q + 1}];')
    for q in range(n_qubits):
        lines.append(f'measure q[{q}] -> c[{q}];')
    return '\n'.join(lines)
```

### QAOA mixer and problem Hamiltonian layers

Covered in the [algorithm reference](algorithm.md#inline-fallback-patterns).

## When to reach for qiskit or pennylane

Inline QASM string-building is fine for circuits under about 50 gates. Above that, bugs creep in.

**Use qiskit for construction:**

```python
from qiskit import QuantumCircuit
from qiskit.qasm2 import dumps as qasm2_dumps

def build_with_qiskit() -> str:
    qc = QuantumCircuit(4, 4)
    qc.h(0)
    for i in range(3):
        qc.cx(i, i + 1)
    qc.measure(range(4), range(4))
    return qasm2_dumps(qc)
```

`QuantumCircuit.qasm()` was removed in qiskit 2.x. Use `qiskit.qasm2.dumps` (for QASM 2.0) or `qiskit.qasm3.dumps` (for QASM 3.0). Default to 2.0.

**Use pennylane for construction:**

```python
import pennylane as qml

def build_with_pennylane() -> str:
    dev = qml.device("default.qubit", wires=4)

    @qml.qnode(dev)
    def circuit():
        qml.Hadamard(wires=0)
        for i in range(3):
            qml.CNOT(wires=[i, i + 1])
        return [qml.sample(qml.PauliZ(i)) for i in range(4)]

    # pennylane can dump to qasm
    return circuit.qtape.to_openqasm()
```

## Gotchas

- **Endianness.** Qiskit and pennylane disagree on qubit ordering in bitstring outputs. Document which you use; convert at the boundary if you compose them.
- **Global phase.** Many optimizers reduce gates while changing the global phase. Do not compare optimized circuits to originals by statevector; compare by measurement outcomes.
- **Parameterized gates in QASM 2.0.** `rx(pi/4)`, `ry(theta)`, etc. work. `pi` is recognized as a literal. Complex expressions (`pi/2 - theta`) work too. Keep them readable.
- **Custom gates in QASM 2.0.** You can define them with `gate name (params) qubits { body }` at the top of the file, but not all simulators parse them cleanly. Stick to the standard library.
