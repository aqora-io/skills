# Contributing

Thanks for helping improve `aqora-io/skills`. This repo ships agent skills that need to work across Claude Code, opencode, pi, GitHub Copilot, Cursor, Codex, and anything else that reads the Agent Skills open standard. That multi-agent target shapes most of the rules below.

## Repository Layout

```
skills/<name>/
  SKILL.md          # required
  scripts/          # optional, executable shell or Python
  references/       # optional, markdown for progressive disclosure
  assets/           # optional, non-code files the skill needs
```

The directory name must match the `name` field in the skill frontmatter. The `name` must match the regex `^[a-z0-9]+(-[a-z0-9]+)*$` and be at most 64 characters.

## Frontmatter Rules

Include only fields every target agent respects:

```yaml
---
name: my-skill
description: One tight sentence about when to use this, front-loading the use case. The agent matches against this for auto-invocation. 1024 character hard limit.
---
```

Do **not** add `allowed-tools`. That field is Claude Code specific and is silently ignored elsewhere. If a skill needs special permissions, document them in the body and rely on the host agent's permission model.

## Writing Style

Skills are instructions for an agent, not documentation for a human.

- Keep `SKILL.md` under 500 lines. Front-load the decision tree. Push depth into `references/*.md` files the skill body links to. If a single reference file goes past 300 lines, add a table of contents.
- Front-load the use case in the first sentence of the description. "Execute code inside a running aqora workspace" is better than "Provides aqora workspace execution capabilities."
- Avoid em dashes and en dashes in prose. Use commas, periods, colons, semicolons, or parentheses.
- Prefer short declarative sentences. If a sentence has three clauses, it is probably two sentences.
- Never reference Claude-Code-specific UX (`/plugin`, `TaskCreate`, subagents) in the skill body. Put that in `reference/claude-code.md` if truly needed.

## Script Portability

Bundled scripts run on the host machine. Make them portable.

- Shebang: `#!/usr/bin/env bash` or `#!/usr/bin/env python3`.
- Dependencies: assume `bash`, `curl`, `jq`, `python3`. Anything else installs itself on first run or fails with a clear message.
- Paths: resolve relative to the script's own directory using `$(cd "$(dirname "$0")" && pwd)`. Never hard-code `.claude/` or any other agent-specific location.
- Secrets: accept via environment variable, not positional argument. Command-line flags show up in `ps aux`.
- `set -euo pipefail` at the top of every bash script.

## Validation

Run the validator before pushing:

```
bash scripts/validate-skills.sh
```

The validator checks:

- Directory name and frontmatter `name` match.
- `name` matches the agentskills.io regex and length limit.
- `description` is present and within 1024 characters.
- All markdown links from `SKILL.md` to `references/*.md` resolve.

CI runs the same script plus `shellcheck` on every pull request.

## Adding a New Skill

1. Pick a name. Prefix aqora-platform-specific skills with `aqora-`. Leave domain skills (`qiskit`, `pennylane`) unprefixed so they stay useful outside aqora.
2. Create `skills/<name>/SKILL.md` with the frontmatter template above.
3. Add `scripts/` and `reference/` as needed.
4. Update the skill table in `README.md`.
5. Add an entry in `CHANGELOG.md` under `Unreleased`.
6. Run the validator.
7. Open a pull request.

## Versioning

Semantic versioning, tracked in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.

- Patch: content edits, clarifications, typo fixes.
- Minor: new skill, new script, new reference file.
- Major: breaking changes to script interfaces or removal of a skill.

Bump versions in the same pull request that introduces the change.

## Code of Conduct

Be kind, assume good faith, and keep reviews focused on the work.
