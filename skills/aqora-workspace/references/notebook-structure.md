# Notebook Structure

How to organize an aqora-hosted marimo notebook so it is readable, reusable, and holds up as a published primitive. The conventions here mirror what the existing workspace-demos (`portfolio-optimizer`, `benchmark`, the three simulators) do well. Follow them when authoring new notebooks and when restructuring ones the agent writes during a session.

## Canonical cell order

A notebook scrolls from top to bottom. Order cells so a reader can follow the logic linearly even though marimo's execution is dataflow-driven.

1. **Header markdown**. One cell, `mo.md(...)`, with:
   - `# Title` as the first line.
   - Three to five sentences on what the notebook does and when to use it. Agent-readable.
   - A badge row (`mo.hstack([...])` with colored spans) tagging the workspace's role, framework, algorithm, domain. Matches the tag taxonomy the `quantum` skill uses.
2. **Dependency installation** (optional). A cell wrapped in `mo.status.spinner()` that installs packages via `ctx.packages.add(...)` the first time the notebook runs.
3. **Imports**. One cell with all `import` statements.
4. **Concept and math**. One or more `mo.md` cells explaining the method. For math-heavy workspaces, use `mo.md(r"$$...$$")` with LaTeX.
5. **Helper functions**. Private helpers prefixed with `_` so marimo does not export them.
6. **Inputs / controls**. `mo.ui.*` elements (sliders, dropdowns, text areas) the user interacts with. Define creation cells here; display them below.
7. **Input display** (if separate from creation). A second cell that arranges the UI elements with `mo.vstack` or `mo.hstack`. See the gotcha below.
8. **Core logic**. Data preparation, algorithm steps, circuit builds. Split into cells by concept, not by line count.
9. **Execution / heavy work**. Wrapped in `mo.status.spinner()`. Often the cell that calls `await aq.notebook(...)` for cross-workspace work.
10. **Outputs / visualization**. Plots, tables, markdown summaries.
11. **Downloads / persistence** (optional). Buttons that save artifacts.
12. **Exports** (`@app.function` cells). Public API for other workspaces. See `exported-functions.md`.

Not every notebook has every section. Sections that are present should appear in this order.

## Cell naming

- **No explicit name for most cells.** Marimo's cell id is enough.
- **Prefix private helpers with `_`.** Marimo treats `_name` as cell-local. Functions like `_fmt_row`, `_apply_gate`, `_build_plot` stay inside the cell that defines them and are not exported to downstream cells or cross-workspace callers.
- **`@app.function`-decorated cells are the public API.** Their function name is what `aq.notebook(slug).<name>(...)` calls from another workspace. Keep names short and descriptive: `simulate`, `optimize`, `run_qaoa_portfolio`.
- **Avoid `name="setup"`**. A cell created with `name="setup"` becomes a marimo setup cell whose top-level imports and definitions do NOT propagate to the rest of the notebook. Downstream cells get `NameError` even though the setup cell ran without error. For a normal shared-imports cell, use any other name or (preferably) no name.

## The display-cell gotcha

Marimo strips unused variables from a cell's return tuple as part of dead-code elimination. If you create a UI element and arrange its layout in the same cell, and no other cell reads the layout variable, marimo removes it from the return and the UI fails to render.

Broken:

```python
@app.cell
def _(mo):
    slider = mo.ui.slider(0, 10, 1, label="n")
    layout = mo.vstack([slider])   # nothing downstream reads 'layout'
    return slider,
```

Fixed: split into two cells.

```python
@app.cell
def _(mo):
    slider = mo.ui.slider(0, 10, 1, label="n")
    return slider,

@app.cell
def _(mo, slider):
    mo.vstack([slider])
    # bare return, no variables
    return
```

Rule: the cell that produces output for the browser should only reference upstream variables and call `mo.vstack` / `mo.hstack` / `mo.md` as its last statement with a bare `return`.

## Cell granularity

One concept per cell. Readable in ten seconds. If you find yourself scrolling inside a single cell to read it, split.

A common rhythm:

- Cell A: define `f = build_something(inputs)`. Returns `f`.
- Cell B: define `g = transform(f)`. Returns `g`.
- Cell C: define `result = g.execute()`. Returns `result`.
- Cell D: `mo.vstack([plot_of(result), summary_table(result)])`. Bare return.

Each cell has one job and one return. Cross-cell dependencies are explicit through the function signatures marimo generates.

## Setup and preamble

- Top-level imports live in a single imports cell. Do not sprinkle imports across cells unless a package is genuinely only used in one place.
- Module-level constants (`SHOTS = 2048`, `SEED = 42`) live in their own short cell, right after imports. Easier to tweak than hunting them down in logic cells.
- For workspaces that need heavy data (large datasets, big matrices), load once into a named cell and let downstream cells depend on that name. Reloading on every slider movement is a usability bug.

## Reactivity and user interaction

- UI elements (`mo.ui.slider`, `mo.ui.dropdown`, `mo.ui.run_button`) cause downstream cells to rerun when their `.value` changes.
- Long-running work should be gated behind a `mo.ui.run_button` so sliders do not accidentally trigger minute-long simulations on every drag.
- `mo.stop()` halts only the cell it lives in. To gate downstream cells behind a run button, the stop guard cell must export a variable that downstream cells depend on (even if it is just a dummy `proceed = True`). A bare `mo.stop()` with no exports does NOT prevent downstream cells from running.

## Example skeleton

A skeletal simulator workspace to copy from:

```python
# Cell 1: header
@app.cell
def _(mo):
    mo.md(r"""
    # My Quantum Simulator

    A brief description.
    """)
    mo.hstack([
        mo.Html('<span class="badge">role:simulator</span>'),
        mo.Html('<span class="badge">framework:pennylane</span>'),
    ])
    return

# Cell 2: imports
@app.cell
def _():
    import pennylane as qml
    import numpy as np
    return qml, np

# Cell 3: constants
@app.cell
def _():
    DEFAULT_SHOTS = 1024
    return DEFAULT_SHOTS,

# Cell 4: private helpers
@app.cell
def _(qml):
    def _parse_qasm(qasm):
        ...
    return _parse_qasm,

# Cell 5: exported function
@app.function
def simulate(qasm: str, shots: int = 1024) -> dict:
    """Simulate a circuit and return counts."""
    ...
    return {"counts": ..., "shots": shots}
```

See also [exported-functions.md](exported-functions.md) for the `@app.function` contract and [visualization.md](visualization.md) for UI patterns.
