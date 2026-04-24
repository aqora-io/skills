# Persisting Cells

`marimo._code_mode` mutates the kernel's in-memory cell graph. It does not write to the workspace's `.py` notebook file. The browser editor reads **cell editor content** from the file, but renders **cell outputs** from kernel broadcasts. When those two sources disagree, the user sees rendered markdown and plots overlaid on empty code editors, and concludes (reasonably) that the notebook is broken.

Pass `--persist` to `execute-code.py` on every call that mutates cells. The flag appends a small epilogue to your code that regenerates the file from the kernel's current cell graph after your own code runs.

## What counts as a mutation

Any of these trigger the need for `--persist`:

- `ctx.create_cell(...)`
- `ctx.edit_cell(...)` (code or config changes)
- `ctx.delete_cell(...)`
- `ctx.move_cell(...)`
- `ctx.install_packages(...)` combined with any of the above

Pure introspection does not need `--persist`:

- Reading `ctx.cells`
- Running `help(cm)` or inspecting kernel globals
- Calling `ctx.run_cell(...)` on already-defined cells without structural changes

Passing `--persist` on an introspection call is harmless, just wasteful: the epilogue re-reads the file, recomputes contents, and only writes on difference.

## What the epilogue actually does

Equivalent to running this at the end of your code:

```python
import re
import marimo._code_mode as cm
from marimo._ast.codegen import generate_filecontents
from marimo._code_mode._context import _cell_names

ctx = cm.get_context()
cells = list(ctx.cells)
fn = ctx._kernel.app_metadata.filename

with open(fn) as f:
    orig = f.read()

# Preserve the PEP 723 script header that marimo writes.
hdr = re.match(r"^(# /// script.*?# ///\n)", orig, re.DOTALL)

contents = generate_filecontents(
    [c.code or "" for c in cells],
    [c.name or _cell_names.get(c.cell_id) or "_" for c in cells],
    [c.config for c in cells],
    config=ctx._kernel.app_metadata.app_config,
    header_comments=hdr.group(1) if hdr else None,
)

if contents != orig:
    with open(fn, "w") as f:
        f.write(contents)
```

The real epilogue uses `_aq_`-prefixed locals to avoid clashing with user code, and swallows exceptions to stderr so a persistence failure does not mask the primary output. If persistence fails, you see `[aqora-workspace] --persist failed: ...` in stderr.

## Why writing the file is safe here

The skill's guard rails say: never write to the workspace's `.py` file directly. That rule is about writing **arbitrary** content, which would diverge from the kernel's in-memory graph. The persist epilogue writes content **generated from kernel state**, so the file always matches what the kernel thinks is there. Marimo's file watcher can safely reload it without losing work.

## Symptom cheat sheet

If the user reports any of these, you almost certainly forgot `--persist`:

- "The notebook has empty cells between my real ones."
- "The markdown renders but there is no code above it."
- "I see tables and the plot, but the cells are blank."
- "I refreshed and the code is gone."

Re-run the last mutation with `--persist`, then ask the user to refresh the browser tab.
