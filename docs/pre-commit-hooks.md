---
title: Pre-commit Hooks
---

Git hooks are scripts that run automatically every time a particular event
occurs in a Git repository. They let you customize Git’s internal behavior and
trigger customizable actions at key points in the development life cycle. Git
hooks are a useful way to run scripts when an action such as a commit, merge, or
push occurs.

To prevent the developer from committing bad code and running CI builds that
would break the environment, we decided to use the pre-commit library to manage
hooks and run some basic checks on the code. All the information about the
pre-commit library can be found in the official documentation.

The goal of this guide is to provide a quick starting point to the developer and
explain how we are using it on the single pipeline repository and how we can
configure it for other projects

pre-commit runs locally while performing a commit, but with a small effort, it
is possible to run it in CI too, during the CI build.

Below are the hooks available in this repository and defined in
[.pre-commit-hooks.yaml](https://github.com/Alfresco/alfresco-build-tools/blob/master/.pre-commit-hooks.yaml)

## Helm-deps (Helm Dependency Update)

Validate the dependencies of a chart.

Add to your `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: helm-deps
```

## Helm Lint

Validate the liniting of a chart.

Add to your `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: helm-lint
```

Helm lint examine a chart for potential issues and verify the chart is well-formed.

## Kubepug

KubePug is a kubectl plugin checking for deprecated Kubernetes clusters or
deprecated versions of Kubernetes manifests.

Validate this hook.

Add to your `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: kubepug-latest
```

Note:- Some more kubepug hooks are available like kubepug-minimum, and kubepug-recommend.

## Check README entries

Verify that each action under `.github/actions` has a matching entry in `docs/README.md`.

Arguments:

- `--actions-dir DIR` (default: `.github/actions`)
- `--readme-file FILE` (default: `docs/README.md`)
- `--missing-entries N` (default: `0`)
- `--exclude-path PATH` (repeatable)

Add to your `.pre-commit-config.yaml`:

```yaml
  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v13.1.0
    hooks:
      - id: check-readme
        args: [--readme-file, docs/README.md, --exclude-path, .github/actions/dbp-charts]
        pass_filenames: false
```
