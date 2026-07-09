---
title: Skills
---

This repository ships [Agent Skills](https://docs.claude.com/en/docs/claude-code/skills):
reusable instructions that AI coding agents (such as Claude Code) load on demand to
perform repository-specific tasks. Each skill lives in its own directory under
[`.github/skills/`](https://github.com/Alfresco/alfresco-build-tools/tree/master/.github/skills)
as a `SKILL.md` file with YAML front-matter (`name`, `description`) followed by the
instructions.

Agents discover skills automatically from the `description` field, so keep it specific
about **what the skill does** and **when to use it**.

## Available skills

### migrate-action-to-uv

Migrate a composite GitHub Action from `requirements.txt` + `pip` to
[`uv`](https://github.com/astral-sh/uv) with `pyproject.toml` and a lockfile. Use it
when modernizing Python dependency management in an action: it replaces the
`setup-python` + pip-cache + `pip install` steps with `setup-uv`, converts scripts to
run via `uv run --frozen --project`, and updates `dependabot.yml` accordingly.

### pimp-my-repo

Bootstrap the standard configuration files a full-featured GitHub repository should have. It
generates a `.github/dependabot.yml` tailored to the ecosystems the repo actually uses
(`github-actions` always included, grouping always enabled), adds a baseline
`.pre-commit-config.yaml` with the standard hooks, ensures every workflow SHA-pins its
third-party actions, ignores `.claude` in `.gitignore`, sets up AI assistant
instructions (`.github/copilot-instructions.md` with a thin `CLAUDE.md` importing it),
and hardens how workflows scope secrets and permissions.

## Adding a new skill

1. Create `.github/skills/<skill-name>/SKILL.md` with `name` and `description`
   front-matter, then the instructions in Markdown.
2. Keep the `description` action-oriented and list the triggering situations, so agents
   know when to load it.
3. Add supporting files (scripts, templates) alongside `SKILL.md` when needed.
4. Document the new skill in this file.
