# alfresco-build-tools

[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)

| Build     | Status                                                                                                                                                                      |
|-----------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| Travis CI | [![Build Status](https://app.travis-ci.com/Alfresco/alfresco-build-tools.svg?branch=master)](https://app.travis-ci.com/Alfresco/alfresco-build-tools)                       |
| GitHub    | [![CI](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml/badge.svg)](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml) |

Shared [Travis CI](https://travis-ci.com/), [GitHub Actions](https://docs.github.com/en/actions) and [pre-commit](https://pre-commit.com/) configuration files plus misc tools.

## GitHub Actions

### Java setup

#### Setup JDK

[actions/setup-java](https://github.com/actions/setup-java) should be used, here is a sample usage:

```yml
      - name: Set up JDK 11
        uses: actions/setup-java@v3
        with:
          java-version: '11'
          distribution: 'temurin'
          cache: 'maven'
```

#### Setup Maven Credentials

Credentials should be already available via organization secrets, otherwise they would need to be
provided as repository secrets.

Since repositories hold a `settings.xml` file at the root with environment variables `MAVEN_USERNAME` and
`MAVEN_USERNAME` filled for the username and password, only a mapping of variables is needed:

```yml
      - name: Build with Maven
        run: mvn --settings settings.xml [...]
        env:
          MAVEN_USERNAME: ${{ secrets.NEXUS_USERNAME }}
          MAVEN_USERNAME: ${{ secrets.NEXUS_PASSWORD }}
```

Alternatively, the [s4u/maven-settings-action](https://github.com/s4u/maven-settings-action) could be used.

#### Setup Maven Build Options

Maven build options can be shared for a given step on the mvn command line, or extracted as environment variables.

Sample usage:

```yml
      - name: Test with Maven
        run: mvn verify ${{ env.MAVEN_CLI_OPTS }}
        env:
          MAVEN_CLI_OPTS: --show-version -Ddocker.skip -Dlogging.root.level=off -Dspring.main.banner-mode=off
```

When deploying in a second step, these variables can be shared:

```yml
env:
  MAVEN_CLI_OPTS: --show-version -Dlogging.root.level=off -Dspring.main.banner-mode=off

[...]

      - name: Test with Maven
        run: mvn verify ${{ env.MAVEN_CLI_OPTS }}
      - name: Deploy with Maven
        run: mvn deploy ${{ env.MAVEN_CLI_OPTS }} -DskipTests
```

When migrating from Travis, depending on the previous configuration, docker.skip and docker.tag properties might need
to be setup on the command line.

Here is a sample way to extract a branch name that would be used for docker images built with the `build-and-push-docker-images.sh` script, although using the [dedicated action](#dockerbuild-push-action) can also be
useful.

```yml
      - name: Set stripped branch name as tag
        run: echo "STRIPPED_TAG=$(echo ${{ github.ref_name }} | sed -e 's/[^-_.[:alnum:]]/_/g')" >> $GITHUB_ENV
      - name: Docker Build and Push
        run: sh ./build-and-push-docker-images.sh
        env:
          TAG: ${{ env.STRIPPED_TAG }}
```

## Migrate from Travis to GitHub Actions

Before starting migrating your first repository, make sure you read [Migrating from Travis CI to GitHub Actions](https://docs.github.com/en/actions/migrating-to-github-actions/migrating-from-travis-ci-to-github-actions).

Hosted runners come with many bundled packages, see
[Available Environments](https://github.com/actions/virtual-environments#available-environments)
for details of what is already available when running GitHub Actions.

Here follows a table to ease migrating Travis build that were using config offered by this repo:

| Travis CI config file                     | GitHub Actions replacement                                                  |
|-------------------------------------------|-----------------------------------------------------------------------------|
| .travis.aws-iam-authenticator_install.yml | Not yet determined                                                          |
| .travis.awscli_install.yml                | Preinstalled                                                                |
| .travis.checkov_install.yml               | [setup-checkov](.github/actions/setup-checkov/action.yml)                   |
| .travis.common.yml                        | Outdated: use equivalent steps in the workflow                              |
| .travis.docker-buildx_install.yml         | [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action) |
| .travis.docker_hub_login.yml              | [docker/login-action](#dockerlogin-action)                                  |
| .travis.docker_login.yml                  | [docker/login-action](#dockerlogin-action)                                  |
| .travis.gh_install.yml                    | Preinstalled                                                                |
| .travis.helm-docs_install.yml             | [setup-helm-docs](.github/actions/setup-helm-docs/action.yml)               |
| .travis.helm.yml                          | Not yet determined                                                          |
| .travis.helm_install.yml                  | Preinstalled                                                                |
| .travis.home_bin_path.yml                 | Not yet determined                                                          |
| .travis.java.yml                          | See [Java Setup section](#setup-maven-build-options)                        |
| .travis.java_config.yml                   | See [Java Setup section](#java-setup)                                       |
| .travis.java_docker.yml                   | See [Java Setup section](#setup-maven-build-options)                        |
| .travis.jq_install.yml                    | Preinstalled                                                                |
| .travis.kcadm_install.yml                 | Not yet determined                                                          |
| .travis.kubepug_install.yml               | [setup-kubepug](.github/actions/setup-kubepug/action.yml)                   |
| .travis.kubernetes_install.yml            | Preinstalled                                                                |
| .travis.maven_config.yml                  | See [Java Setup section](#java-setup)                                       |
| .travis.pre-commit.yml                    | [pre-commit](.github/actions/pre-commit)                                    |
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

Credentials should be already available via organization secrets, otherwise they would need to be
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

### nick-fields/retry

[This action](https://github.com/nick-fields/retry) retries an Action step on failure or timeout. Useful for unstable commands or that relies on remote resources that can be flaky sometimes.

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

### setup-helm-docs

### setup-jx-release-version

### setup-pysemver

### setup-rancher-cli

### setup-updatebot

### setup-yq

## Known issues

### realpath not available under macosx

When running pre-commit locally you may get failures with the following error:

```
realpath: command not found
```

This is because macosx lacks support for that, and it can be fixed with:

```
brew install coreutils
```
