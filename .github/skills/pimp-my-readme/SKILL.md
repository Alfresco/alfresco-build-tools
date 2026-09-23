---
name: pimp-my-readme
description: "Create or upgrade a repository's README.md to a standard layout: title, CI/release/license badges, purpose, related repositories, a table of contents, a copy-paste quickstart, a testing section, and a configuration table when the project has parameters to document. Use when the user asks to write, fix, update, or standardize a README, or invokes /pimp-my-readme."
---

# Pimp My Readme

Bring a repository's `README.md` to a standard shape. If the file is missing or
close to empty, write it from scratch. If it already has content, upgrade it in
place: fix what is stale or missing, keep what is accurate, and keep any
section that isn't part of this template where it already is.

## Target layout

In this order:

1. `# <project name>` — the repo name, unless the current README already uses
   a nicer display name.
2. A badges line right under the title (see [Badges](#badges) below).
3. One or a few sentences on what the project is and why it exists. Not a
   feature list.
4. `## Features` — only when the project's purpose is broad enough that one
   or two sentences undersell it. A bullet list.
5. `## Related repositories` — see [Related repositories](#related-repositories)
   below.
6. `## Contents` — a table of contents for every `##` and `###` heading that
   follows it (nested bullets for `###`), using GitHub's anchor slugs. Leave
   out the title, the intro, Features, Related repositories, and Contents
   itself.
7. `## Quickstart` — see [Quickstart](#quickstart) below.
8. `## Configuration` — only when the project has configuration parameters.
   A table: `| Name | Description | Default | Required |`. Use `-` when
   there's no default.
9. `## Testing` — what test suites exist and the command to run each one
   locally. If there are no automated tests, say so in one line and list any
   lint or pre-commit checks instead.

Any other section already in the README (Architecture, Contributing,
License, Troubleshooting, ...) stays where it is; only insert the missing
standard sections around it, and add it to the table of contents too.

## Badges

Add, directly under the title:

- One GitHub Actions badge per workflow file in `.github/workflows/` whose
  `on:` triggers on `push` or `pull_request` against the default branch, or
  on `schedule`. For `push`, that means no `branches` filter and no
  tag-only `tags` filter, or a `branches` filter that includes the default
  branch. Skip workflows that only run on `workflow_dispatch`,
  `workflow_call`, tags, or releases.

  ```markdown
  [![<workflow name>](https://github.com/<owner>/<repo>/actions/workflows/<file>/badge.svg)](https://github.com/<owner>/<repo>/actions/workflows/<file>)
  ```

  Use the workflow's `name:` as the label, or the file name if it has none.

- A latest-release badge, when `gh release list` shows at least one release:

  ```markdown
  [![Release](https://img.shields.io/github/v/release/<owner>/<repo>)](https://github.com/<owner>/<repo>/releases)
  ```

- A license badge, when a `LICENSE` file exists:

  ```markdown
  [![License](https://img.shields.io/github/license/<owner>/<repo>)](LICENSE)
  ```

Get the owner, repo, and default branch from `gh repo view --json
nameWithOwner,defaultBranchRef` (fall back to `git remote show origin` if
`gh` isn't set up). Skip the shields.io badges entirely on a private repo —
shields.io can't read it and renders "repo not found".

## Related repositories

List other repositories the reader of this one is likely to also need, as
`[owner/repo](url) - one-line description`.

Find candidates by checking the git repos checked out as siblings of this
one (`../*`) for ones that reference this repo or are referenced by it —
matching remote URLs, `uses:` in workflows, dependency names, container
image names, or links already in the docs. Also keep any related
repositories already linked in the current README.

Show the candidate list to the user and ask them to add or remove entries
before writing the section. Only drop the section entirely once the user
confirms there really are none.

## Quickstart

Copy-paste fenced shell commands to get a new user from clone to running the
project: install, build, run. At most one short line of explanation per
step — this section is commands, not prose.

Take every command from what the repository actually has — a `Makefile`,
`package.json` scripts, `pom.xml`/Gradle tasks, `pyproject.toml`, a
`Dockerfile` or compose file, or the steps a CI workflow already runs. Never
invent a command that isn't backed by something in the repo.

## Configuration

Pull parameters from wherever the project defines them: environment
variables and CLI flags read in the code, `.env.example`, an `action.yml`'s
`inputs:`, or a config schema. Skip this section if there's nothing to
document.

## Testing

Identify the test suites (unit, integration, end-to-end) and the local
command for each. Also mention lint or pre-commit checks if the repo has
any. When there are no automated tests, say so directly instead of leaving
the section out.

## Verifying the result

Before finishing:

- List the Quickstart and Testing commands you'd run to check them (build,
  unit tests, lint, `--help`), and ask the user which ones to run before
  running any of them. Never propose one that deploys, publishes, pushes,
  needs credentials, or reaches a remote system beyond fetching
  dependencies. Run only what the user approves, and list the rest as
  unverified.
- If a command fails because the README described it wrong, fix the README.
  If it fails because the project itself is broken, say so — don't paper
  over it.
- Check that every badge points at a workflow file that exists, and that
  every table of contents entry matches a real heading.

## Style

- Simple English: short sentences, plain words, no jargon. Explain a
  project-specific term the first time you use it.
- Wrap prose at 80 columns. Leave tables, badge lines, headings, and code
  blocks unwrapped.
- Follow standard Markdown lint rules: a single `#` title, blank lines
  around headings/lists/fenced blocks, a language on every fenced code
  block.
- Once the file is written, if a `humanizer` skill is available, run it on
  the README and apply its edits, keeping every command, table, badge, and
  link unchanged.
- When upgrading an existing README, tell the user what you added, changed,
  moved, or removed, and keep the accurate parts of the original wording
  rather than rewriting everything.
- Don't commit the result — leave that to the user.
