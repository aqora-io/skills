# CLAUDE.md

Guidance for Claude Code (and any agent with project-level instructions) when working inside this repository.

## What this repo is

`aqora-io/skills` ships agent skills for building quantum computing workflows on aqora.io and beyond. Platform skills (workspace pair-programming, dataset handling) live alongside domain skills (qiskit, pennylane, circuit optimization). Skills here are authored to the [Agent Skills](https://agentskills.io) open standard so they work across Claude Code, opencode, pi, GitHub Copilot, Cursor, Codex, and anything else that reads `SKILL.md`. The `.claude-plugin/` manifests are an overlay on top, not the source of truth.

Read [README.md](README.md) for the user-facing story and [CONTRIBUTING.md](CONTRIBUTING.md) for the full authoring rules. This file highlights what matters specifically when Claude is editing the repo.

## Writing style rules

- Never use em dashes or en dashes in any file (markdown, code comments, commit messages, PR descriptions). Do not substitute them with hyphens or double hyphens either. Use commas, periods, colons, semicolons, or parentheses.
- Keep `SKILL.md` bodies under 500 lines. Push depth into `references/*.md`.
- Do not reference Claude-Code-specific UX (`/plugin`, `TaskCreate`, subagents) in the body of a skill. If such guidance is unavoidable, put it in a dedicated `references/claude-code.md`.
- Prefer imperative sentences in skill bodies. Explain the why in one line before a rule rather than stacking all-caps MUSTs.

## Directory convention

Each skill lives in `skills/<name>/` with this layout:

```
skills/<name>/
  SKILL.md          # required, frontmatter plus body
  scripts/          # executable helpers
  references/       # markdown for progressive disclosure
  assets/           # non-code files used in outputs
```

Directory name equals the `name` frontmatter field. The name matches `^[a-z0-9]+(-[a-z0-9]+)*$` and is at most 64 characters.

## Frontmatter rules

Keep frontmatter portable:

```yaml
---
name: example-skill
description: One tight sentence that front-loads the use case. The agent matches on this.
---
```

Do not add `allowed-tools`. It is Claude Code specific and silently ignored elsewhere. Permissions belong in the host agent's permission system, not in the skill.

## Validation

Before committing, run:

```
bash scripts/validate-skills.sh
```

The validator checks directory and frontmatter `name` agreement, description length, regex compliance, and link resolution. CI runs the same script plus `shellcheck` on every pull request.

## Working on a new or existing skill

1. Read or write the skill's `SKILL.md` first. The body is the contract.
2. When adding scripts, make them portable: `#!/usr/bin/env bash`, `set -euo pipefail`, resolve paths relative to the script's own directory, accept secrets via environment variables.
3. Never hard-code agent-specific install paths (for example, do not write `.claude/` into a script).
4. When a reference file passes 300 lines, add a table of contents.
5. Update `README.md` if the skill inventory changes. Add a `CHANGELOG.md` entry under `Unreleased`.

## Common tasks

- Add a new skill: create `skills/<name>/SKILL.md`, add entry to `README.md` skill table, bump `CHANGELOG.md`, run the validator.
- Review an existing skill against Anthropic's authoring guide: install the `skill-creator` skill (`npx skills add anthropics/skills --skill skill-creator --yes --global`) and read `~/.claude/skills/skill-creator/SKILL.md`.
- Test a skill locally in Claude Code: symlink `skills/<name>/` into `~/.claude/skills/<name>/` for a fast iteration loop, then remove the symlink when done.

## Do not

- Do not push to `main` from Claude. Open a pull request.
- Do not commit `credentials.json`, access tokens, or anything that resembles a secret. The validator does not check for this; reviewers do.
- Do not add dependencies to scripts beyond `bash`, `curl`, `jq`, and `python3`. Anything else must self-install or fail clearly.
