# Promotion Checklist

A checklist for turning an inline implementation into a published workspace primitive that the `quantum` skill's search can find and the orchestrators can use.

Use this both proactively (when writing a new workspace) and retroactively (when promoting a good inline fallback the agent wrote during a user session).

## The seven points

1. **Title and one-paragraph description cell.** Top of the workspace, a `mo.md()` cell with a single `#` title, then three to five sentences explaining what the workspace does, for whom, and when to use it. Short is better. Agents read this first.

2. **Tags, on the publish form.** At minimum one `role:*`, one `stage:*`, one `framework:*`. Additional tags (algorithm, domain, capability, hardware) sharpen search. Taxonomy lives in [tag-taxonomy.md](tag-taxonomy.md).

3. **`@app.function` exports with type-annotated signatures and docstrings.** Externally callable cells are decorated. Every export follows the contract in [interface-contract.md](interface-contract.md) for its role. Private helpers are prefixed with `_` so marimo does not export them.

4. **Standard return shape for the role.** Simulator returns `{"counts": ..., "statevector": ..., "shots": ...}`. Optimizer returns `{"qasm": ..., "before": ..., "after": ..., "target": ...}`. Algorithm returns `{"solution": ..., "counts": ..., "trajectory": ..., "metadata": ...}`. No deviations without a strong reason.

5. **Interchange formats are OPENQASM 2.0 and `counts` dicts.** No custom circuit objects, no pickled framework-specific types, no numpy arrays on the wire. Document bitstring endianness in the docstring if it is not self-evident.

6. **Defensive cross-workspace calls.** If the workspace orchestrates other primitives, every `await aq.notebook(slug)` is wrapped in try / except with a local fallback or a clear error. If there is no local fallback, document it: "This workspace requires `<slug>` to be available."

7. **Input validation or an explicit `not-validated` note.** If the primitive silently accepts malformed input (e.g., QASM with unsupported gates), either validate at the entry point and raise, or add a line to the docstring: "Malformed QASM is silently truncated at the regex parser; pass syntactically valid QASM 2.0." The existing simulators do the latter. Either is acceptable as long as the behavior is documented.

## Review with the user before publishing

Promotion is a product choice, not a code choice. Before publishing:

- Confirm the user wants this in the catalog. Some inline implementations are one-off experiments that should not be promoted.
- Pick a slug (the user's `owner/name`). `aqora/<name>` is reserved for curated workspaces.
- Pick tags together, matching the taxonomy.
- Confirm the description and title.
- Confirm the interface matches the contract. Skim the exports, check return shapes.

The first five minutes of review catch most divergence issues that would otherwise live forever.

## Quick self-check

Before offering promotion, sanity-check that the implementation is actually reusable.

- Would another workspace benefit from this, or is it one-off logic?
- Is the signature problem-specific (narrow scope) or problem-family (broad scope)? Broad scope is easier to reuse.
- Does it hardcode paths, tokens, owner names? Remove them.
- Does it assume the user's data schema? Generalize the input.

If all four answers suggest the code is truly primitive-shaped, it is a good candidate. If two or more suggest it is user-specific, keep it inline.
