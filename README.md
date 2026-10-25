# Aqora Skills

Agent skills for building quantum computing workflows. Equip your AI coding agent to design circuits, run simulators, orchestrate quantum optimization, and pair-program inside live aqora-hosted marimo notebooks. Works with Claude Code, opencode, pi, GitHub Copilot, Cursor, Codex, and any agent that reads the [Agent Skills](https://agentskills.io) open standard.

The repo treats the platform (aqora workspaces) and the domain (quantum computing) as two complementary axes. Platform skills know how to drive a live workspace. Domain skills know qiskit, pennylane, circuit optimization, and simulator choice. Together they cover the full loop from "sketch a circuit" to "run it on a simulator in an aqora workspace and compare results."

## Available Skills

| Skill | Purpose |
| :---- | :------ |
| [`aqora-workspace`](skills/aqora-workspace/SKILL.md) | Pair-program inside a live aqora-hosted marimo workspace. List workspaces, execute code in the remote kernel, create and edit cells. The entry point for running quantum code on aqora. |
| [`quantum`](skills/quantum/SKILL.md) | Build end-to-end quantum computing pipelines. Search aqora for simulators, optimizers, and algorithms; compose them across data loading, algorithm, circuit construction, optimization, error mitigation, execution, and analysis; fall back to inline qiskit/pennylane/pytket when no primitive exists. Pairs with `aqora-workspace` for execution. |

## Roadmap

- **Additional stage references** inside `quantum`: data loading, error mitigation, analysis (v0.2).
- **Additional platform skills** as the aqora API grows: dataset management, competition submission, and workspace search.
- **Additional domain skills** for adjacent tooling (AI/ML, simulation) as the ecosystem evolves.

## Installation

### Claude Code

```
/plugin marketplace add aqora-io/skills
/plugin install aqora-skills@aqora-io-skills
```

Enable auto-update to stay current:

```
/plugin  ->  Marketplaces  ->  aqora-io-skills  ->  Enable auto-update
```

### Any Agent Skills Compatible Tool

Works with any agent that supports the [Agent Skills](https://agentskills.io) open standard, including opencode, pi, GitHub Copilot, Cursor, and Codex.

Install everything:

```
npx skills add aqora-io/skills
```

Install a single skill:

```
npx skills add aqora-io/skills --skill aqora-workspace
```

If you do not have `npx` but have `uv`:

```
uvx deno -A npm:skills add aqora-io/skills
```

### Manual

Clone this repository and symlink individual skill directories into your agent's skills path. Common locations:

| Agent | Path |
| :---- | :--- |
| Claude Code | `~/.claude/skills/<skill-name>` |
| opencode | `~/.config/opencode/skills/<skill-name>` |
| pi | `~/.pi/agent/skills/<skill-name>` |
| GitHub Copilot | `~/.copilot/skills/<skill-name>` |

Only the leaf skill directory matters. The `skills/` parent is not copied.

## Quick Start

After installing, log in to aqora so the skills can authenticate:

```
pip install aqora-cli
aqora login
```

Then ask your agent a workspace question, for example:

- "list my aqora workspaces"
- "in my portfolio-optimizer workspace, add a cell that runs QAOA on the pennylane simulator and plots the efficient frontier"
- "open the numpy-simulator workspace and sanity-check the Hadamard gate"

The agent loads the relevant skill, targets the right workspace, and starts working. Cells appear live in the workspace UI.

## Philosophy

Skills in this repo follow three rules.

1. **Portable first, Claude Code second.** Skills are authored to the Agent Skills open standard. Claude Code manifests sit on top as an overlay. If a piece of guidance only applies to one agent, it belongs in a reference file, not the skill body.
2. **Progressive disclosure.** The body of `SKILL.md` is short and action-oriented. Depth lives in `references/*.md` files the body links to. Only the body enters context on invocation. References load on demand.
3. **Scripts own the machine, kernels own the state.** Bundled scripts run on the user's machine and talk HTTP. Business logic lives in the remote kernel, driven through `marimo._code_mode`.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for authoring conventions, frontmatter rules, and the validation script CI runs on every pull request.

## Credits

The execute-code script pattern is adapted from [marimo-team/marimo-pair](https://github.com/marimo-team/marimo-pair). Credit to the marimo team for the design.

## License

MIT. See [LICENSE](LICENSE).
