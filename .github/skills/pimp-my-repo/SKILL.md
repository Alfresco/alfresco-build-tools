---
name: pimp-my-repo
description: "Bootstrap a full-featured GitHub repository's standard configuration. Use when: setting up a new repository, adding a missing Dependabot or pre-commit config, or standardizing an existing repo. Generates .github/dependabot.yml from the ecosystems the repo actually uses, a baseline .pre-commit-config.yaml, ensures every workflow SHA-pins its third-party actions, ignores .claude in .gitignore, sets up .github/copilot-instructions.md with a thin CLAUDE.md importing it, and hardens workflow secret scoping and permissions."
---

# Pimp My Repo

Bootstrap the standard configuration a full-featured GitHub repository should have. Work
through the steps below, tailoring each to what the repo actually contains. Skip anything
already configured correctly; merge rather than overwrite.

1. **Dependabot** — `.github/dependabot.yml` derived from the ecosystems in use.
2. **Pre-commit** — a baseline `.pre-commit-config.yaml` with the standard hooks.
3. **SHA-pinning** — every workflow references third-party actions by commit SHA.
4. **Gitignore** — common ignores for the repo's stack, plus Claude Code artifacts.
5. **AI assistant instructions** — `.github/copilot-instructions.md` with a thin `CLAUDE.md`.
6. **Secrets & permissions** — least-privilege secret scoping and workflow permissions.

## 1. Dependabot config

Generate (or extend) `.github/dependabot.yml` based on what the repo actually
contains. Detect the ecosystems in use from their marker files (`package.json`,
`pom.xml`, `pyproject.toml`/`uv.lock`, `go.mod`, `Dockerfile`, `*.tf`, etc.) and emit
one `updates` block per ecosystem found — never for tooling the repo doesn't use.

Rules for every block:

- **`github-actions` is always included**, even when no other ecosystem is detected.
- **Grouping is always enabled** — at least one catch-all group so Dependabot opens one
  grouped PR per ecosystem instead of many.
- Weekly `schedule`, 7-day `cooldown`, and `directories:` (plural) pointing at the
  parent dirs of the marker files (collapse siblings with a glob).
- Label with `dependencies` plus an ecosystem-specific label.

```yaml
# Documentation for all configuration options:
# https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference
version: 2
updates:
  - package-ecosystem: "github-actions"
    directories:
      - "/"
    schedule:
      interval: "weekly"
    labels:
      - "dependencies"
      - "github_actions"
    cooldown:
      default-days: 7
    groups:
      github-actions:
        patterns:
          - "*"
```

Add further blocks in the same shape for each detected ecosystem. Only split into extra
named groups when a family of dependencies must always move together. When the file
already exists, preserve existing `ignore`, `groups`, and custom `directories`.

## 2. Pre-commit config

Add a baseline `.pre-commit-config.yaml` with the standard hooks (pin `rev`s to the
latest release of each repo). Include language-specific hooks (black/isort/flake8,
shellcheck, …) only for languages the repo actually uses.

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v6.0.0
    hooks:
      - id: check-yaml
        args: [--allow-multiple-documents]
      - id: check-json
      - id: check-xml
      - id: check-merge-conflict
      - id: fix-byte-order-marker
      - id: mixed-line-ending
        args: ['--fix=lf']
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/sirosen/check-jsonschema
    rev: 0.37.1
    hooks:
      - id: check-dependabot
      - id: check-github-actions
      - id: check-github-workflows

  - repo: https://github.com/igorshubovych/markdownlint-cli
    rev: v0.47.0
    hooks:
      - id: markdownlint

  - repo: https://github.com/rhysd/actionlint
    rev: v1.7.12
    hooks:
      - id: actionlint

  - repo: https://github.com/hyland/github-actions-ensure-sha-pinned-actions
    rev: v1.2.0
    hooks:
      - id: gha-sha-convert
        args: [--allowlist, 'Alfresco/alfresco-build-tools/*']
```

## 3. SHA-pin third-party actions

Every workflow and composite action must reference third-party actions by full 40-char
commit SHA, with the version as a trailing comment — mutable tags (`@v4`, `@main`) are
forbidden for security.

```yaml
- uses: actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8 # v5.0.0
```

The `gha-sha-convert` hook above converts existing tag refs to SHA pins automatically.
After wiring up pre-commit, run it across the repo and commit the result:

```bash
pre-commit run gha-sha-convert --all-files
```

Keep `Alfresco/alfresco-build-tools/*` refs on the allowlist — those are
immutable tags and safe to use.

## 4. Gitignore

Ensure `.gitignore` covers the common entries for what the repo actually contains —
build outputs, dependency directories, caches, editor/OS cruft, and local tooling
artifacts for the languages and tools detected in step 1. Derive the set from the repo
structure rather than dropping in a fixed list, and always include Claude Code's local
artifacts:

```gitignore
# Claude Code local artifacts
.claude
```

Add missing entries and keep the existing ordering and comment style consistent; don't
duplicate or reorder what's already there.

## 5. AI assistant instructions

Keep repo guidance in a **single shared source of truth**. The actual instructions live
in `.github/copilot-instructions.md`; `CLAUDE.md` is a thin file that imports them via
Claude's native `@` syntax rather than duplicating content.

If `.github/copilot-instructions.md` is missing, generate it with the agent's `/init`
operation, which documents the codebase (purpose, layout, build/test commands,
conventions). Then arrange the result into the single-source layout:

- Put the generated instructions in `.github/copilot-instructions.md`.
- Make `CLAUDE.md` at the repo root contain only the import:

  ```markdown
  @.github/copilot-instructions.md
  ```

If `CLAUDE.md` already holds real content, move it into `.github/copilot-instructions.md`
and replace `CLAUDE.md` with the single import line.

## 6. Secrets and permissions in workflows

Harden how workflows handle secrets and permissions.

**Never put secrets in a top-level (workflow) `env` block.** A workflow-level `env`
exposes secrets to every job and every step, including any third-party action that runs.

Scope secrets as tightly as possible:

- **Prefer step-level `env`** — declare the secret on the specific step that needs it.
  Duplicating the same `env` block across several steps is fine and preferred; the
  narrower exposure is worth the repetition.
- **Job-level `env` is acceptable only** when the job runs no third-party actions —
  GitHub-maintained actions such as `actions/checkout` don't count against this. As soon
  as a job uses a third-party action, move secrets back down to the steps that need them.

**Prefer a GitHub App over a personal access token (PAT)** for authenticated
operations: App tokens are short-lived, scoped to the installation, and not tied to an
individual. Mint a token at runtime (e.g. `actions/create-github-app-token`) instead of
storing a long-lived PAT.

**Always declare a workflow-level `permissions` block** with the minimum needed to check
out the repo, then widen per-job only where required:

```yaml
permissions:
  contents: read

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z

  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write   # widened only for the job that needs it
    steps:
      - uses: actions/checkout@<sha> # vX.Y.Z
      - name: Publish
        env:
          NPM_TOKEN: ${{ secrets.NPM_TOKEN }}   # step-level: scoped to where it's used
        run: npm publish
```
