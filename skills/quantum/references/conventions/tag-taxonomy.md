# Tag Taxonomy

Tags are how the skill finds primitives. Without consistent tags, `search-workspaces.sh` returns noise. This document is the community convention. The aqora publish UI should nudge contributors toward these tags; the skill's search assumes them.

## Categories and values

Use `category:value` form. Multiple tags per category are allowed (a workspace is both `framework:pennylane` and `framework:pytket` if it really is).

### `role:` what kind of primitive is this

| Value | Description |
| :---- | :---------- |
| `role:simulator` | Consumes a circuit, returns measurement outcomes. |
| `role:optimizer` | Consumes a circuit, returns a rewritten circuit plus stats. |
| `role:algorithm` | Encodes a problem into a circuit and (optionally) runs the variational loop. |
| `role:dataset` | Provides data (problem instances, Hamiltonians, graphs, molecules). |
| `role:mitigation` | Applies error mitigation around a circuit or a run. |
| `role:use-case` | Full end-to-end example for a specific domain problem. |
| `role:benchmark` | Compares two or more primitives head to head. |
| `role:pipeline-template` | A reusable composition across multiple stages. |

### `stage:` where this workspace fits in the pipeline

The seven stages from `SKILL.md`. A workspace can be tagged with more than one if it spans stages.

| Value | |
| :---- | :- |
| `stage:data` | Data loading. |
| `stage:algorithm` | Algorithm selection and framing. |
| `stage:circuit` | Circuit construction. |
| `stage:optimization` | Circuit optimization. |
| `stage:mitigation` | Error mitigation. |
| `stage:execution` | Execution (simulator or hardware). |
| `stage:analysis` | Post-execution analysis. |

### `framework:` underlying library or toolkit

| Value | |
| :---- | :- |
| `framework:qiskit` | IBM's qiskit. |
| `framework:pennylane` | Xanadu's pennylane. |
| `framework:pytket` | Quantinuum's pytket. |
| `framework:pyzx` | PyZX for ZX-calculus optimization. |
| `framework:cirq` | Google's cirq. |
| `framework:braket` | AWS Braket SDK. |
| `framework:mitiq` | Mitiq for error mitigation. |
| `framework:numpy` | Pure numpy / scipy, no quantum framework. |

### `algorithm:` quantum algorithm this implements

| Value | |
| :---- | :- |
| `algorithm:qaoa` | Quantum Approximate Optimization Algorithm. |
| `algorithm:vqe` | Variational Quantum Eigensolver. |
| `algorithm:phase-estimation` | Quantum phase estimation. |
| `algorithm:grover` | Grover's search. |
| `algorithm:shor` | Shor's factoring. |
| `algorithm:qft` | Quantum Fourier Transform. |
| `algorithm:quantum-ml` | Quantum machine learning (QCNN, variational classifiers, etc.). |

### `domain:` problem space

| Value | |
| :---- | :- |
| `domain:finance` | Portfolio, risk, option pricing. |
| `domain:chemistry` | Ground state estimation, reaction energetics, molecular dynamics. |
| `domain:logistics` | Routing, scheduling, assignment. |
| `domain:ml` | Classification, regression, generative. |
| `domain:crypto` | Shor-style, QKD analysis. |
| `domain:optimization` | General combinatorial optimization (MaxCut, SAT, ILP embeddings). |

### `capability:` notable properties

| Value | |
| :---- | :- |
| `capability:differentiable` | Supports gradient-based parameter optimization. |
| `capability:noise-aware` | Accepts or exposes a noise model. |
| `capability:hardware-efficient` | Uses hardware-efficient ansatz patterns. |
| `capability:stateless` | No session state between calls. |
| `capability:streaming` | Can stream partial results. |

### `hardware:` real-device backend the workspace targets

| Value | |
| :---- | :- |
| `hardware:ibm` | IBM Quantum Platform (Heron, Eagle, etc.). |
| `hardware:ionq` | IonQ cloud. |
| `hardware:quantinuum` | Quantinuum H-series. |
| `hardware:rigetti` | Rigetti Aspen / Ankaa. |
| `hardware:neutral-atoms` | QuEra, Pasqal, Atom Computing. |
| `hardware:simulator` | Only reaches simulators, no real-device integration. |

## Minimum tag set for a published primitive

Every published primitive should carry at least:

- Exactly one `role:*` tag.
- At least one `stage:*` tag.
- At least one `framework:*` tag (even if it is `framework:numpy`).

Algorithm, domain, capability, and hardware tags are optional but helpful. Skipping them hides the workspace from tag-scoped search.

## Examples

**`aqora/pennylane-simulator`** should carry:
```
role:simulator stage:execution framework:pennylane capability:differentiable hardware:simulator
```

**`aqora/gate-optimizer`** (pytket):
```
role:optimizer stage:optimization framework:pytket
```

**`aqora/portfolio-optimizer`**:
```
role:algorithm role:use-case stage:algorithm stage:execution algorithm:qaoa domain:finance
```

**`aqora/benchmark`**:
```
role:benchmark stage:analysis
```

## Migration

Workspaces published before this taxonomy existed will not have these tags. The skill's search scripts degrade gracefully: `--tags role:simulator` filters for the tag but also respects a `--search` query that surfaces older workspaces by name or description. As the aqora publish UI adopts the taxonomy, tagging becomes richer and search gets sharper.
