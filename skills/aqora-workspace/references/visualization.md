# Visualization

Making an aqora-hosted marimo notebook communicate clearly to the user. Covers layout, interactive controls, plots, tables, and bespoke widgets. Uses the patterns the existing workspace-demos use well.

## Rich markdown with `mo.md`

Use `mo.md` for anything that would otherwise be a comment. Users see it; agents read it.

```python
mo.md(r"""
# Title

Short description. One to three sentences.

**Inputs:** sliders for `alpha`, `beta`; button for "Run".
**Outputs:** energy trajectory plot and final bitstring.
""")
```

LaTeX with raw strings:

```python
mo.md(r"$$\min_x x^T Q x \quad \text{subject to} \quad x \in \{0,1\}^n$$")
```

For badge-style labels (matches the tag taxonomy the `quantum` skill uses):

```python
mo.hstack([
    mo.Html('<span class="badge" style="background:#8b5cf6;color:#fff;padding:2px 8px;border-radius:4px">role:simulator</span>'),
    mo.Html('<span class="badge" style="background:#06b6d4;color:#fff;padding:2px 8px;border-radius:4px">framework:pennylane</span>'),
])
```

Colors per category are conventions the community is free to standardize. The workspace-demos use distinct hues per role, framework, and algorithm.

## Layout: `mo.vstack` and `mo.hstack`

Compose UI vertically or horizontally. Nest freely.

```python
mo.vstack([
    mo.md("## Configuration"),
    mo.hstack([shots_slider, shots_value_display]),
    mo.hstack([run_button, reset_button]),
    mo.md("## Results"),
    result_table,
])
```

Use `mo.vstack` for main structure, `mo.hstack` for controls that belong side-by-side. Avoid deep nesting; two levels is usually enough.

## Interactive controls

The common ones:

```python
# Numeric slider
shots = mo.ui.slider(start=100, stop=10000, step=100, value=1024, label="Shots")

# Dropdown select
simulator = mo.ui.dropdown(
    options=["Local (numpy)", "aqora/numpy-simulator", "aqora/pennylane-simulator"],
    value="Local (numpy)",
    label="Simulator"
)

# Text input
query = mo.ui.text(placeholder="Search workspaces", label="Query")

# Text area
hamiltonian = mo.ui.text_area(placeholder="Enter Hamiltonian as YAML", label="H")

# Checkbox
noise = mo.ui.checkbox(label="Include noise model")

# Run button (does not trigger reactivity until clicked)
run = mo.ui.run_button(label="Run simulation")

# File input
file = mo.ui.file(filetypes=[".csv", ".json"], label="Upload dataset")
```

Each has `.value` that downstream cells can read. The creation cell defines the element; a separate cell displays it (see the display-cell gotcha in [notebook-structure.md](notebook-structure.md)).

Gate long-running work on `mo.ui.run_button` so sliders do not trigger expensive recomputations on every drag:

```python
# In a downstream cell:
if not run.value:
    mo.stop()   # gate downstream cells until the button is clicked
```

`mo.stop()` only halts the cell it lives in. To actually gate downstream cells, the stop-guard cell must export a variable (even a dummy `proceed = True`) that downstream cells depend on. See the [gotchas](gotchas.md) reference for the full pattern.

## Plotting

Three common plot libraries. Pick one per notebook and stick with it.

### matplotlib (default, conservative)

```python
import matplotlib.pyplot as plt

fig, ax = plt.subplots(figsize=(8, 5))
ax.plot(x, y, label="energy")
ax.set_xlabel("iteration")
ax.set_ylabel("E")
ax.legend()
fig   # last expression is the output
```

Strengths: universal, ubiquitous. Weaknesses: static, not interactive.

### altair (interactive, declarative)

```python
import altair as alt
import pandas as pd

df = pd.DataFrame({"iteration": x, "energy": y})
chart = (
    alt.Chart(df)
    .mark_line(point=True)
    .encode(x="iteration:Q", y="energy:Q", tooltip=["iteration", "energy"])
    .properties(width=600, height=300)
    .interactive()
)
chart
```

Strengths: interactive by default (zoom, pan, tooltip), declarative, looks polished. Weaknesses: data must fit in memory.

### plotly (interactive, imperative)

```python
import plotly.express as px

fig = px.line(df, x="iteration", y="energy", markers=True)
fig
```

Strengths: interactive, rich chart types, polished. Weaknesses: heavy dependency.

Recommendation:
- Quick prototyping or research-style static output: matplotlib.
- User-facing dashboards where zoom and tooltip matter: altair.
- Need a chart type altair lacks (3D, maps, violin): plotly.

## Tables

Interactive tables with `mo.ui.table`:

```python
import pandas as pd

df = pd.DataFrame({
    "bitstring": list(counts.keys()),
    "count": list(counts.values()),
    "probability": [c / shots for c in counts.values()],
})
mo.ui.table(df, page_size=10)
```

Supports sorting, selection, and pagination. The selection is reactive; `.value` on the element returns the selected rows.

For read-only rendering:

```python
mo.ui.table(df, selection=None)
```

## Progress indicators

For anything that takes more than a few seconds:

```python
with mo.status.spinner(title="Running QAOA", subtitle="iteration 3 of 20"):
    result = await call_workspace(...)
```

The spinner displays in the browser while the cell runs. Update the subtitle via the context manager's API for progress. Inside a long loop:

```python
with mo.status.spinner(title="Grid search", remove_on_exit=True) as progress:
    for i, (gamma, beta) in enumerate(grid):
        progress.update(subtitle=f"{i+1}/{len(grid)} gamma={gamma:.3f}")
        ...
```

## Custom widgets with anywidget

For bespoke visualizations (circuit diagrams, state sphere, routing graphs) that the standard plot libraries cannot produce cleanly, use `anywidget`:

```python
import anywidget
import traitlets

class CircuitViewer(anywidget.AnyWidget):
    qasm = traitlets.Unicode().tag(sync=True)
    highlighted = traitlets.List([]).tag(sync=True)

    _esm = """
    function render({ model, el }) {
        const qasm = model.get("qasm");
        // parse qasm, render SVG
        el.innerHTML = `<svg>...</svg>`;
    }
    export default { render };
    """

viewer = CircuitViewer(qasm=my_qasm)
viewer
```

Two strategies for bridging anywidget state into the marimo reactive graph. **Pick one per widget, do not mix.**

- **`mo.state` plus `.observe()`**: bridge specific traits by hand. Default choice.

  ```python
  selected = mo.state([])
  viewer.observe(lambda change: selected.set_value(change["new"]), names="highlighted")
  ```

- **`mo.ui.anywidget(viewer)`**: wraps all synced traits into one reactive `.value`. Convenient but coarser.

  ```python
  reactive_viewer = mo.ui.anywidget(viewer)
  # reactive_viewer.value is a dict of all synced traits
  ```

## Visualization as a promotion-grade concern

A published primitive's outputs should be visually clean. The first time a consumer opens the workspace in their browser, they should see a readable header, labeled inputs, a visible "Run" gate, and clear outputs. If the notebook only communicates via print statements, promotion is premature; add visualization before publishing.

Minimum for a publishable workspace:

- Header markdown cell with title, description, and badges.
- Labeled input controls.
- At least one rendered output (plot, table, or formatted summary) that shows what the primitive does.
- A textual result in the `@app.function` return value (not just a plot). Consumers of the function never see the plot; they see the return value.

## What not to do

- **Do not hide the whole notebook behind a single run button with no visible state.** Users like seeing defaults applied on first load.
- **Do not write custom Plotly/Altair theming in every notebook.** Accept the library defaults; move on.
- **Do not build a UI framework inside marimo.** If the interaction pattern is getting complex, the notebook is probably doing too much; split into two notebooks.
- **Do not rely on matplotlib's `plt.show()`**. Return the figure as the last expression; marimo renders it.
- **Do not use `print()` as the primary output channel for a published primitive.** `print` output disappears when the cell is re-executed. Use `mo.md`, tables, or plots for anything the user needs to see.
