# Stage 2: Algorithm

Pick the quantum method and frame the problem. For variational algorithms this stage also owns the classical outer loop.

## What this stage decides

- Which quantum algorithm fits the problem shape (QAOA, VQE, phase estimation, Grover, quantum-ML).
- How to encode the problem into the algorithm's expected input (QUBO for QAOA, Hamiltonian for VQE, etc.).
- For variational algorithms, the parameter search strategy (grid, Nelder-Mead, COBYLA, SPSA, Adam).
- Shot budget per iteration and stopping criteria.

## Find a primitive first

```bash
bash scripts/search-workspaces.sh --tags role:algorithm --search "<problem keyword>"
```

Useful tag combinations:

| Goal | Tags |
| :--- | :--- |
| Any QAOA implementation | `role:algorithm,algorithm:qaoa` |
| QAOA for a specific domain | `role:algorithm,algorithm:qaoa,domain:<finance\|optimization\|logistics>` |
| VQE for chemistry | `role:algorithm,algorithm:vqe,domain:chemistry` |
| Grover's search | `role:algorithm,algorithm:grover` |

When in doubt, prefer a workspace tagged both `role:algorithm` and `role:use-case`, which typically means "end-to-end tested on a realistic instance." `aqora/portfolio-optimizer` is the canonical example.

## Evaluate candidates

Introspect the top one or two candidates before adopting:

```python
import aqora_cli as aq

ws = await aq.notebook("aqora/<slug>")
help(ws)
```

Red flags:

- No `@app.function` exports at all. Workspace is likely interactive only, not reusable.
- Single giant export that takes the entire problem as a free-form string. Hard to compose and hard to reason about.
- Return shape deviates from the [interface contract](../conventions/interface-contract.md). Usable but will need a shim.
- No local fallback option in the signature. Means the orchestrator cannot degrade gracefully.

Green flags:

- One or two narrow `@app.function` entry points with type-annotated signatures.
- Return includes `counts`, `trajectory` (for variational), and a `metadata` dict.
- Signature includes a `simulator` string argument with `"Local (numpy)"` as a default.

## Algorithm selection guidance

| Problem class | Algorithm | Typical primitive fit |
| :------------ | :-------- | :-------------------- |
| Combinatorial optimization (MaxCut, portfolio, TSP) | QAOA | `aqora/portfolio-optimizer` for finance; generic QAOA is a promotion target. |
| Ground state of a fermionic Hamiltonian | VQE | TBD in the catalog; currently inline fallback. |
| Period finding, factoring | Phase estimation, Shor | TBD; educational only. Do not claim runtime advantage. |
| Unstructured search | Grover | TBD; useful for small didactic examples. |
| Classification / regression with kernel methods | Quantum-ML | TBD; pennylane-based patterns below. |

## Variational outer loop

QAOA and VQE are not single-shot; they iterate. The pipeline shape wraps stages 3 through 7 in a classical optimizer loop. Two shapes are common:

**Grid search** (portfolio-optimizer's pattern):

```python
best = None
for gamma in gammas:
    for beta in betas:
        qasm = build_qaoa_qasm(Q, p_layers, gamma, beta)
        counts = await run_simulator(qasm, shots=2048)
        energy = expected_energy(counts, Q)
        if best is None or energy < best[0]:
            best = (energy, gamma, beta, counts)
```

Use for small parameter spaces (2 to 3 variational parameters) where grid resolution matters.

**Classical optimizer**:

```python
from scipy.optimize import minimize

def objective(params):
    qasm = build_ansatz_qasm(params)
    counts = asyncio.run(run_simulator(qasm, shots=2048))
    return -expected_value(counts, hamiltonian)

result = minimize(objective, x0=initial_params, method="COBYLA")
```

Use for VQE and larger parameter spaces. COBYLA and SPSA tolerate the shot noise; BFGS and similar gradient methods fail without careful variance reduction.

**Persist intermediate parameters.** Variational loops are long. Save `(iteration, params, value)` to a cell variable or the `trajectory` output so that interruption does not destroy progress. Do not use `/tmp/` for this; temp files do not survive kernel restarts.

## Inline fallback patterns

When no suitable primitive exists, the inline QAOA pattern from `portfolio-optimizer` is a reasonable starting point:

```python
def build_qaoa_qasm(
    Q: dict[tuple[int, int], float],   # QUBO coefficients
    p_layers: int,
    gamma: list[float],
    beta: list[float],
) -> str:
    """Build the QAOA circuit for a QUBO problem at depth p_layers.

    Returns OPENQASM 2.0. Uses verbose CZ + H decomposition to give
    downstream optimizers room to work.
    """
    n = max(max(i, j) for (i, j) in Q) + 1
    lines = [
        'OPENQASM 2.0;',
        'include "qelib1.inc";',
        f'qreg q[{n}];',
        f'creg c[{n}];',
    ]
    # Initial superposition
    for i in range(n):
        lines.append(f'h q[{i}];')
    # p QAOA layers
    for p in range(p_layers):
        for (i, j), w in Q.items():
            if i == j:
                lines.append(f'rz({2 * gamma[p] * w}) q[{i}];')
            else:
                lines.append(f'cz q[{i}],q[{j}];')
                lines.append(f'rz({2 * gamma[p] * w}) q[{j}];')
                lines.append(f'cz q[{i}],q[{j}];')
        for i in range(n):
            lines.append(f'rx({2 * beta[p]}) q[{i}];')
    # Measurement
    for i in range(n):
        lines.append(f'measure q[{i}] -> c[{i}];')
    return '\n'.join(lines)
```

The VQE-style ansatz construction follows the same pattern but builds hardware-efficient or problem-specific layers instead of QAOA's alternating Hamiltonians. If the inline implementation gets reused across tasks, apply the [promotion checklist](../conventions/promotion-checklist.md) and offer to publish it as a workspace.

## Gotchas

- **Parameter initialization for QAOA.** Random initialization often lands in a barren plateau. Start with `gamma = 0.1`, `beta = 0.1`, or warm-start from a shallower `p_layers - 1` solution.
- **Variational loops on noisy simulators diverge.** If the simulator returns shot-noise statistics, use COBYLA or SPSA, not BFGS. Increasing shots per iteration helps but is expensive.
- **Measurement basis matters.** QAOA measures in the computational basis (Z). VQE and quantum-ML often need X or Y basis measurement; rotate before measuring.
- **Shot counts are hyperparameters.** 1024 is a common default but underestimates variance for small expectation values. Bump to 8192+ when the expected value is near zero and matters.
