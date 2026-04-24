---
name: quantum
description: Build quantum computing workflows end to end on aqora. Search published aqora workspaces for simulators, optimizers, algorithms, and compose them into pipelines across data loading, algorithm, circuit construction, circuit optimization, error mitigation, execution, and analysis. Use this skill whenever the user mentions qiskit, pennylane, pytket, pyzx, QAOA, VQE, quantum circuits, quantum simulation, quantum hardware, error mitigation, or any quantum-computing task, even if they do not explicitly say "quantum".
---

# Quantum Computing Protocol

Quantum workloads on aqora are built as pipelines, not one-shot scripts. Given a user goal, decompose the work into stages, search aqora for existing workspaces that solve each stage, compose them, and fall back to writing inline code only when no suitable primitive exists.

This skill teaches the decomposition, the search and evaluation of candidates, the composition pattern, and the inline fallbacks. Execution and cell authoring in a user's workspace are the job of the `aqora-workspace` skill. Load both when you work on quantum problems.

## Pipeline Mental Model

Every quantum workflow fits this seven-stage template:

| Stage | Purpose | Typical aqora primitives | Reference |
| :---- | :------ | :----------------------- | :-------- |
| 1. Data loading | Problem input to canonical representation. | aqora datasets, aqorafs. | not yet written for v0.1 |
| 2. Algorithm | Choose and frame the quantum method (QAOA, VQE, phase estimation, Grover). Includes the classical outer loop for variational algorithms. | Algorithm workspaces such as `aqora/portfolio-optimizer`. | [references/stages/algorithm.md](references/stages/algorithm.md) |
| 3. Circuit construction | Produce the gate sequence from the algorithmic framing. | Canonical circuit workspaces (mostly to be built). | [references/stages/circuit.md](references/stages/circuit.md) |
| 4. Circuit optimization | Gate count, depth, routing. | `aqora/gate-optimizer` (pytket), `aqora/pyzx-optimizer`, `aqora/routing-optimizer`. | [references/stages/optimization.md](references/stages/optimization.md) |
| 5. Error mitigation | ZNE, PEC, readout correction, dynamical decoupling. | Mitigation workspaces (to be built). | not yet written for v0.1 |
| 6. Execution | Run on simulator or hardware. Includes shot budget and backend selection. | `aqora/numpy-simulator`, `aqora/pennylane-simulator`, `aqora/qiskit-simulator`. | [references/stages/execution.md](references/stages/execution.md) |
| 7. Analysis | Statistics, fidelity, benchmarking, comparison. | `aqora/benchmark` as the template. | not yet written for v0.1 |

Not every task touches every stage. A "simulate this Bell state" task is stages 3 and 6. A full variational portfolio run is stages 1 through 7.

**Variational algorithms (QAOA, VQE) are not a stage.** They are a pipeline shape: a classical optimizer loops around stages 3 through 7 and reruns them with updated parameters. Document and implement this as an outer loop pattern.

**Hardware selection is part of stage 6**, not a separate stage. The first question inside execution is always "simulator or hardware, which one."

## The Core Loop

For any quantum task:

1. **Decompose into stages.** Write down the pipeline before writing any code. If the user's goal does not fit a stage boundary, ask for clarification.
2. **Search aqora for a primitive** at each stage using `bash scripts/search-workspaces.sh`. See [references/conventions/tag-taxonomy.md](references/conventions/tag-taxonomy.md) for the tag conventions.
3. **Evaluate candidates** using `bash scripts/describe-workspace.sh` plus a runtime introspection call (see below). Favor workspaces owned by `aqora` or that have high vote counts and recent updates.
4. **Compose via `aqora_cli.notebook()`** inside the user's workspace. See [references/patterns/cross-workspace-calls.md](references/patterns/cross-workspace-calls.md) for the exact pattern.
5. **Fall back to inline code** only if no suitable primitive exists. Use the framework references and the stage references' "inline fallback" sections.
6. **Offer to promote good inline implementations to workspaces** using [references/conventions/promotion-checklist.md](references/conventions/promotion-checklist.md). This is how the aqora catalog grows.

## Operations

Two operations this skill adds on top of the `aqora-workspace` skill:

| Operation | Script |
| :-------- | :----- |
| Search for published primitives | `bash scripts/search-workspaces.sh --tags role:simulator --first 10` |
| Describe a specific workspace | `bash scripts/describe-workspace.sh aqora/pennylane-simulator` |

Execution (running code inside the user's workspace) and cell editing come from the `aqora-workspace` skill's `scripts/execute-code.py`.

## Canonical Interchange Formats

- **Circuits: OPENQASM 2.0 strings.** Every simulator, optimizer, and algorithm primitive in the aqora ecosystem expects QASM 2.0 on input and emits QASM 2.0 on output. Qiskit, pennylane, and pytket all parse 2.0 natively. Do not use QASM 3.0 unless a target explicitly requires it.
- **Measurement results: `counts` dicts.** Simulator output is `{"counts": {"0010": 412, "1001": 388, ...}, "statevector": ..., "shots": N}`. Keys are bitstrings (little- or big-endian depends on the simulator; document which), values are integers.
- **Optimization results: QASM-in, QASM-out plus stats.** `optimize(qasm, target="depth")` returns `{"qasm": str, "before": {...}, "after": {...}}`.

**Gate decomposition is a conscious choice.** When handing a circuit to an optimizer, emit verbose (CZ + H) decomposition to give the optimizer room to work. When going straight to a simulator, emit compact (CX + RZ) decomposition.

## Cross-Workspace Calls

The canonical pattern inside a user's workspace:

```python
import aqora_cli as aq

sim = await aq.notebook("aqora/pennylane-simulator")
result = sim.simulate(qasm_string, shots=2048)
counts = result["counts"]
```

Three non-negotiables:

1. **Use `await`**. `aq.notebook()` is async. Inside a marimo cell, this works at the top level.
2. **Wrap in defensive error handling.** Dead primitives and auth failures should not crash the orchestrator. See the wrapper template in [references/patterns/cross-workspace-calls.md](references/patterns/cross-workspace-calls.md).
3. **Provide a local fallback where possible.** The portfolio and benchmark orchestrators both let the user select `Local (numpy)` as the simulator. Follow suit.

## Guard Rails

Skip these and the workflow breaks or is wrong.

- **Check for a primitive before writing code.** Rewriting QAOA from scratch when `aqora/portfolio-optimizer` already implements the pattern is waste plus risk of divergence.
- **Treat OPENQASM 2.0 as the interchange format.** Mixing QASM versions between stages is the number one source of confusion.
- **Do not mix endianness assumptions.** Document which simulator convention you are using and convert at boundaries if needed.
- **Variational loops must persist intermediate parameters.** If the user's session is interrupted between iterations, the optimizer should resume from the last `(gamma, beta)` vector, not restart. Persist to a cell, not `/tmp`.
- **Error mitigation is additive.** Stack at most two techniques (e.g., readout correction plus ZNE). Stacking three or four tends to amplify variance, not reduce it. See the mitigation reference (to be added in v0.2).
- **Real hardware has queues.** Assume minutes, not seconds. Do not run variational loops on real hardware without a queue budget and a timeout on the outer loop.

## First Steps in a New Quantum Task

1. Decompose. Write the pipeline as a list of stages in your working memory or a scratch cell.
2. `bash scripts/search-workspaces.sh --search "<keyword>" --tags role:<role>` for each stage.
3. Skim the top three candidates with `bash scripts/describe-workspace.sh`.
4. Introspect the most promising one via a scratch probe in the user's workspace:
   ```python
   import aqora_cli as aq
   ws = await aq.notebook("aqora/<slug>")
   help(ws)
   ```
   This lists the `@app.function` exports, their signatures, and their docstrings. It is always truthful because it reflects the live code, not stale metadata.
5. Compose. Fall back to inline. Run. Analyze.

## References

- [references/conventions/tag-taxonomy.md](references/conventions/tag-taxonomy.md) lists the community tag conventions the search scripts assume.
- [references/conventions/interface-contract.md](references/conventions/interface-contract.md) shows the Python signatures published workspaces follow, per role.
- [references/conventions/promotion-checklist.md](references/conventions/promotion-checklist.md) is the list an inline implementation has to meet to become a workspace primitive.
- [references/patterns/cross-workspace-calls.md](references/patterns/cross-workspace-calls.md) is the `aqora_cli.notebook()` pattern with the error-handling wrapper.
- Stage references: [algorithm](references/stages/algorithm.md), [circuit](references/stages/circuit.md), [optimization](references/stages/optimization.md), [execution](references/stages/execution.md). Data loading, mitigation, and analysis stages land in v0.2.
