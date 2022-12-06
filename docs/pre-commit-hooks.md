# Pre-commit Hooks

Git hooks are scripts that run automatically every time a particular event occurs in a Git repository. They let you customize Git’s internal behavior and trigger customizable actions at key points in the development life cycle. Git hooks are a useful way to run scripts when an action such as a commit, merge, or push occurs.

To prevent the developer from committing bad code and running CI builds that would break the environment, we decided to use the pre-commit library to manage hooks and run some basic checks on the code. All the information about the pre-commit library can be found in the official documentation.

The goal of this guide is to provide a quick starting point to the developer and explain how we are using it on the single pipeline repository and how we can configure it for other projects

pre-commit runs locally while performing a commit, but with a small effort, it is possible to run it in CI too, during the CI build.

Below are the hooks available in this repository and defined in [.pre-commit-hooks.yaml](../.pre-commit-hooks.yaml)

## Helm-deps (Helm Dependency Update)

Validate the dependencies of a chart.

Add to your `.pre-commit-config.yaml`:


  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: helm-deps


## Helm Lint

Validate the liniting of a chart.

Add to your `.pre-commit-config.yaml`:


  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: helm-lint

Helm lint examine a chart for potential issues and verify the chart is well-formed. Use --strict to return an error for the step if a chart isn't formatted properly.

```- name: Lint Charts
  run: helm lint --strict $HELM_WORKING_DIRECTORY
```

## Kubepug

KubePug is a kubectl plugin checking for deprecated Kubernetes clusters or deprecated versions of Kubernetes manifests.

Validate this hook.

Add to your `.pre-commit-config.yaml`:


  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: kubepug

Example of Usage in CI with Github Actions

```name: Sample CI Workflow
# This workflow is triggered on pushes to the repository.
on: [push]
env:
  HELM_VERSION: "v3.9.0"
  K8S_TARGET_VERSION: "v1.22.0"
jobs:
 api-deprecations-test:
    runs-on: ubuntu-latest
    steps:
      - name: Check-out repo
        uses: actions/checkout@v2

      - uses: azure/setup-helm@v1
        with:
          version: $HELM_VERSION
        id: install

      - uses: cpanato/kubepug-installer@v1.0.0

      - name: Run Kubepug with your Helm Charts Repository
        run: |
          find charts -mindepth 1 -maxdepth 1 -type d | xargs -t -n1 -I% /bin/bash -c 'helm template % --api-versions ${K8S_TARGET_VERSION} | kubepug --error-on-deprecated --error-on-deleted --k8s-version ${K8S_TARGET_VERSION} --input-file /dev/stdin'
```

## Plantuml

Add to your `.pre-commit-config.yaml`:
  - repo: https://github.com/Alfresco/alfresco-build-tools
    rev: v1.22.0
    hooks:
      - id: plantuml

During the commit of any PlantUML file (file with extension: .puml), if we

add or update a PlantUML file, a PlantUML image will be generated based on the file and commit

delete a PlantUML file, existing PlantUML image will be deleted together in the commit

Open your pre-commit file and add the following code to run plantuml.pre-commit.sh

```#!/bin/bash
...

"$(git rev-parse --git-dir)/hooks/plantuml.pre-commit.sh"
```

## Checkov

To use Checkov with pre-commit, just add the following to your local repo’s .pre-commit-config.yaml file:

```- repo: https://github.com/bridgecrewio/checkov.git
  rev: '' # change to tag or sha
  hooks:
    - id: checkov
```
