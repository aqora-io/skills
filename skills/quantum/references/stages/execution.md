# Stage 6: Execution

Run the circuit. First question: simulator or hardware. Hardware selection is the first decision inside execution, not a separate stage.

## What this stage decides

- Simulator or real hardware.
- Which simulator or which hardware backend.
- Shot count.
- How to handle queue time and potential failures for hardware runs.

## Simulator versus hardware, at a glance

| Consideration | Simulator | Hardware |
| :------------ | :-------- | :------- |
| Latency | Milliseconds to seconds. | Minutes to hours (queue). |
| Cost | Free on aqora simulators. | Metered by provider. |
| Noise | Optional, configurable. | Real and nontrivial. |
| Scale | Up to about 32 qubits on statevector simulators; more on tensor networks. | Today up to about 150 physical qubits (IBM Heron); practical algorithms usually much fewer. |
| Reproducibility | Deterministic with a seed. | Non-deterministic. |

Default to simulator for development, small circuits, variational loops, and anything under 20 qubits. Reach for hardware only when the user specifically wants it or when the problem demands noise-aware results.

## Simulator primitives in the catalog

Three simulator workspaces exist today:

| Slug | Framework | Strengths |
| :--- | :-------- | :-------- |
| `aqora/numpy-simulator` | Pure numpy statevector | Smallest dependency footprint, predictable, no autograd. |
| `aqora/pennylane-simulator` | PennyLane `default.qubit` | Differentiable, supports gradients for variational training. |
| `aqora/qiskit-simulator` | Qiskit Aer | Most features (noise models, large statevector, tensor network). |

All three export the same `simulate(qasm: str, shots: int, noise_model: dict | None) -> dict` interface. Swap between them without rewriting orchestration code.

Find them and any newer entrants:

```bash
bash scripts/search-workspaces.sh --tags role:simulator --first 10
```

## Simulator selection

| Task | Prefer |
| :--- | :----- |
| Small sanity check (under 6 qubits, under 1000 shots) | Local inline numpy (no cross-workspace call). |
| Generic QAOA / VQE with variational loop | `aqora/pennylane-simulator` (differentiable). |
| Circuit up to 25 qubits, no gradients needed | `aqora/numpy-simulator`. |
| Circuit 25+ qubits or need noise model | `aqora/qiskit-simulator` (Aer tensor network). |
| Differentiable gradient-based training | `aqora/pennylane-simulator`. |

## Compose via `aqora_cli.notebook()`

```python
import aqora_cli as aq

sim = await aq.notebook("aqora/pennylane-simulator")
result = sim.simulate(qasm_string, shots=2048)
counts = result["counts"]
statevector = result.get("statevector")
```

The defensive wrapper from [cross-workspace-calls](../patterns/cross-workspace-calls.md) should wrap this call when the simulator is on the critical path. Always include a local fallback:

```python
def _local_simulate(qasm: str, shots: int = 1024) -> dict:
    # numpy-only statevector simulation, inline
    ...

result = await call_workspace(
    "aqora/pennylane-simulator",
    "simulate",
    qasm,
    shots=2048,
    fallback=_local_simulate,
)
```

## Inline fallback: numpy statevector

For self-contained execution without any cross-workspace call:

```python
import numpy as np
import re
from collections import Counter

def inline_simulate(qasm: str, shots: int = 1024, seed: int | None = None) -> dict:
    """Statevector simulation of a small OPENQASM 2.0 circuit, pure numpy.

    Fast for up to about 15 qubits. Above that, reach for an aqora simulator.
    """
    rng = np.random.default_rng(seed)
    n = int(re.search(r"qreg q\[(\d+)\]", qasm).group(1))
    state = np.zeros(2 ** n, dtype=complex)
    state[0] = 1.0

    def apply(gate_matrix, qubits):
        # Omitted for brevity. For full implementation see
        # aqora/numpy-simulator or portfolio-optimizer's _apply_gate helper.
        ...

    # Parse and apply each gate line
    for line in qasm.splitlines():
        line = line.strip().rstrip(";")
        if not line or line.startswith(("OPENQASM", "include", "qreg", "creg")):
            continue
        # Dispatch gate names (h, x, cx, rz, rx, ry, cz, ...) to apply()
        ...

    probs = np.abs(state) ** 2
    samples = rng.choice(2 ** n, size=shots, p=probs)
    counts = Counter(f"{s:0{n}b}" for s in samples)
    return {
        "counts": dict(counts),
        "statevector": state.tolist(),
        "shots": shots,
    }
```

A full working version of this parser is in `aqora/numpy-simulator`'s source. For inline use, copy it verbatim rather than reimplementing.

## Hardware execution

Hardware execution via aqora is still being built. When it lands, it will be a set of workspaces tagged `hardware:ibm`, `hardware:ionq`, etc., each exposing the same `simulate()`-shaped contract but with additional kwargs for calibration data. Until then, direct SDK use (qiskit-ibm-runtime, amazon-braket-sdk) is the path.

When you do run on real hardware:

- Queue time can exceed wall-clock patience. Set a timeout on the outer loop.
- Shot budget is not free. Ask the user before spending thousands of shots.
- Results always need mitigation. See [stages/mitigation.md] (v0.2) for ZNE, readout correction, and PEC.
- Some providers rate-limit circuit depth. Know the ceiling before submitting.

## Shot budget

| Use case | Shots |
| :------- | :---- |
| Quick sanity check (Bell state, GHZ verification) | 100 to 1000. |
| Production QAOA energy estimate | 2048 to 8192. |
| Expectation value near zero (sign-sensitive) | 8192 to 65536. |
| Hardware run (cost-sensitive) | Ask the user; start at 1024. |

Default to 2048 unless the user specifies. Flag when jumping above 8192 since it is noticeably slower on real hardware and unnecessary on simulators.

## Gotchas

- **Endianness, again.** `{"01": count}` in a pennylane simulator might mean something different in a qiskit simulator. Convert to a canonical form at the orchestrator boundary.
- **Silent gate drops.** Simulators that use regex parsing for QASM may silently ignore gates they do not understand. If the counts look wrong, compare the circuit with what the simulator actually executed (if it exposes that; not all do).
- **Measurement in the wrong basis.** Default QASM measurement is computational (Z) basis. For X-basis measurement, rotate with an H before `measure`. For Y-basis, rotate with S-dagger then H.
- **Order of measurement matters for simulators that return partial states.** `measure q[0]` followed by `measure q[1]` is different from measuring both at once if the simulator respects the collapse between them. Stick to measuring all at the end of the circuit.
