# alfresco-build-tools

[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)

| Build     | Status                                                                                                                                                                      |
|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Travis CI | [![Build Status](https://app.travis-ci.com/Alfresco/alfresco-build-tools.svg?branch=master)](https://app.travis-ci.com/Alfresco/alfresco-build-tools)                       |
| GitHub    | [![CI](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml/badge.svg)](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml) |

Shared [Travis CI](https://travis-ci.com/), [GitHub Actions](https://docs.github.com/en/actions) and [pre-commit](https://pre-commit.com/) configuration files plus misc tools.

## Travis

## Migrate from Travis to GitHub Action

Before starting migrating your first repository, make sure you read [Migrating from Travis CI to GitHub Actions](https://docs.github.com/en/actions/migrating-to-github-actions/migrating-from-travis-ci-to-github-actions).

Hosted runners come with many bundled packages, see
[Available Environments](https://github.com/actions/virtual-environments#available-environments)
for details of what is already available when running GitHub Actions.

Here follows a table to ease migrating Travis build that were using config offered by this repo:

| Travis config file                        | GitHub action replacement                                                   |
|-------------------------------------------|-----------------------------------------------------------------------------|
| .travis.aws-iam-authenticator_install.yml | Not yet determined                                                          |
| .travis.awscli_install.yml                | Preinstalled                                                                |
| .travis.checkov_install.yml               | [setup-checkov](.github/actions/setup-checkov/action.yml)                   |
| .travis.common.yml                        | Not yet determined                                                          |
| .travis.docker-buildx_install.yml         | [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action) |
| .travis.docker_hub_login.yml              | [docker/login-action](#dockerlogin-action)                                  |
| .travis.docker_login.yml                  | [docker/login-action](#dockerlogin-action)                                  |
| .travis.gh_install.yml                    | Preinstalled                                                                |
| .travis.helm-docs_install.yml             | [setup-helm-docs](.github/actions/setup-helm-docs/action.yml)               |
| .travis.helm.yml                          | Not yet determined                                                          |
| .travis.helm_install.yml                  | Preinstalled                                                                |
| .travis.home_bin_path.yml                 | Not yet determined                                                          |
| .travis.java.yml                          | Not yet determined                                                          |
| .travis.java_config.yml                   | Not yet determined                                                          |
| .travis.java_docker.yml                   | Not yet determined                                                          |
| .travis.jq_install.yml                    | Preinstalled                                                                |
| .travis.kcadm_install.yml                 | Not yet determined                                                          |
| .travis.kubepug_install.yml               | [setup-kubepug](.github/actions/setup-kubepug/action.yml)                   |
| .travis.kubernetes_install.yml            | Preinstalled                                                                |
| .travis.kubernetes_config.yml             | Not yet determined                                                          |
| .travis.kubernetes_install.yml            | Not yet determined                                                          |
| .travis.maven_config.yml                  | Not yet determined                                                          |
| .travis.pre-commit.yml                    | Not yet determined                                                          |
| .travis.rancher_cli_config.yml            | [setup-rancher-cli](.github/actions/setup-rancher-cli/action.yml)           |
| .travis.rancher_cli_install.yml           | [setup-rancher-cli](.github/actions/setup-rancher-cli/action.yml)           |
| .travis.rancher_cli_kubernetes_config.yml | [setup-rancher-cli](.github/actions/setup-rancher-cli/action.yml)           |
| .travis.srcclr_install.yml                | Not yet determined                                                          |
| .travis.terraform-docs_install.yml        | Not yet determined                                                          |
| .travis.terraform_install.yml             | Preinstalled                                                                |
| .travis.tflint_install.yml                | Not yet determined                                                          |
| .travis.trigger.yml                       | Not yet determined                                                          |
| .travis.veracode.yml                      | Not yet determined                                                          |
| .travis.yml                               | Not yet determined                                                          |
| .travis.yq_install.yml                    | Preinstalled                                                                |

## GitHub Actions provided by community

### docker/build-push-action

Consider using this official [Docker action](https://github.com/marketplace/actions/build-and-push-docker-images) for building and pushing containers instead of doing it by hand, for buildx support, caching and more.

### docker/login-action

Credentials should be already available via organization secrets or needs to be
provided as repository secrets.

```yml
      - name: Login to Docker Hub
        uses: docker/login-action@v1
        with:
          username: ${{ secrets.DOCKER_USERNAME }}
          password: ${{ secrets.DOCKER_PASSWORD }}

      - name: Login to Quay.io
        uses: docker/login-action@v1
        with:
          registry: quay.io
          username: ${{ secrets.QUAY_USERNAME }}
          password: ${{ secrets.QUAY_PASSWORD }}
```

### styfle/cancel-workflow-action

[This action](https://github.com/styfle/cancel-workflow-action) is a replacement for the Travis settings **Auto cancel branch builds** and **Auto cancel pull request builds**.

## GitHub Actions provided by us

### pre-commit

You can execute pre-commit step in a dedicated new workflow:

```yml
name: pre-commit

on:
  pull_request:
    branches: [ master ]
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
