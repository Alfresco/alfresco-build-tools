# alfresco-build-tools

[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)

Shared [Travis CI](https://travis-ci.com/), [GitHub Actions](https://docs.github.com/en/actions) and [pre-commit](https://pre-commit.com/) configuration files plus misc tools.

## Travis

[![Build Status](https://travis-ci.com/Alfresco/alfresco-build-tools.svg?branch=master)](https://travis-ci.com/Alfresco/alfresco-build-tools)

## GitHub Actions

![GitHub Workflow Status](https://img.shields.io/github/workflow/status/alfresco/alfresco-build-tools/CI)

Hosted runners come with many bundled packages, see
[Available Environments](https://github.com/actions/virtual-environments#available-environments)
for details.

### pre-commit

You can execute pre-commit step in a dedicated new workflow:

```yml
name: pre-commit

on:
  pull_request:
  push:

jobs:
  pre-commit:
    runs-on: ubuntu-latest
    steps:
      - uses: Alfresco/alfresco-build-tools/.github/actions/pre-commit@master
```

or into an existing workflow of your choice just declaring the step:

```yml
      - uses: Alfresco/alfresco-build-tools/.github/actions/pre-commit@master
```

### calculate-next-internal-version

### setup-checkov

### setup-helm

If you need the helm cli available in the runner path:

```yml
jobs:

  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v1
      - uses: Alfresco/alfresco-build-tools/.github/actions/setup-helm@master
```

### setup-helm-docs

### setup-jx-release-version

### setup-pysemver

### setup-rancher-cli

### setup-updatebot

### setup-yq
