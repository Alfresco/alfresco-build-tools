# alfresco-build-tools

[![pre-commit](https://img.shields.io/badge/pre--commit-enabled-brightgreen?logo=pre-commit&logoColor=white)](https://github.com/pre-commit/pre-commit)
[![Codacy Badge](https://app.codacy.com/project/badge/Grade/fd8899233e1246c0b48a0684ada35d05)](https://www.codacy.com/gh/Alfresco/alfresco-build-tools/dashboard?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=Alfresco/alfresco-build-tools&amp;utm_campaign=Badge_Grade)

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
| .travis.terraform-docs_install.yml        | [setup-terraform-docs](.github/actions/setup-terraform-docs/action.yml)     |
| .travis.terraform_install.yml             | Preinstalled                                                                |
| .travis.tflint_install.yml                | Not yet determined                                                          |
| .travis.trigger.yml                       | Not yet determined                                                          |
| .travis.veracode.yml                      | Not yet determined                                                          |
| .travis.yml                               | Not yet determined                                                          |
| .travis.yq_install.yml                    | Preinstalled                                                                |

## Security hardening for GitHub Actions

Before creating / modifying a GitHub Actions workflow make sure you're familiar with [Security hardening for GitHub Actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions). Pay special attention to:

- [Understanding the risk of script injections](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#understanding-the-risk-of-script-injections)
- [Good practices for mitigating script injection attacks](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#good-practices-for-mitigating-script-injection-attacks)
- [Using third-party actions](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)

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

### Triggering a workflow in another repository

[actions/github-script](https://github.com/actions/github-script) can be used, here is a sample:

```yml
      - name: Trigger Downstream Builds
        if: steps.is_default_branch.outputs.result == 'true'
        uses: actions/github-script@v5
        with:
          github-token: ${{ secrets.BOT_GITHUB_TOKEN }}
          script: |
            await github.rest.actions.createWorkflowDispatch({
              owner: 'Alfresco',
              repo: 'alfresco-process-connector-services',
              workflow_id: 'build.yml',
              ref: 'develop'
            });
```

Note that this requires using a dedicated token.

Also, the triggered workflow should allow workflow dispatch in its definition (and this configuration should be setup
on the default branch):

```yml
on:
  # allows triggering workflow manually or from other jobs
  workflow_dispatch:
```

## GitHub Actions provided by us

### build-helm-chart

Run `helm dep up` and `helm lint` on the specified chart

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/build-helm-chart@ref
        with:
          chart-dir: charts/common
```

### git-commit-changes

Commits local changes after configuring git user and showing the status of what is going be committed.

```yaml
    - uses: Alfresco/alfresco-build-tools/.github/actions/git-commit-changes@ref
      with:
        username: ${{ secrets.BOT_GITHUB_USERNAME }}
        add-options: -u
        commit-message: "My commit message"
```

### package-helm-chart

Packages a helm chart into a `.tgz` file and provides the name of the file produced in the output named `package-file`

```yaml
    - uses: Alfresco/alfresco-build-tools/.github/actions/package-helm-chart@ref
      id: package-helm-chart
      with:
        chart-dir: charts/common
```

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
      - uses: Alfresco/alfresco-build-tools/.github/actions/pre-commit@ref
```

or into an existing workflow of your choice just declaring the step:

```yml
      - uses: Alfresco/alfresco-build-tools/.github/actions/pre-commit@ref
```

### publish-helm-chart

Publishes a new helm chart package (`.tgz`) to a helm chart repository

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/publish-helm-chart@ref
        with:
          helm-charts-repo: Activiti/activiti-cloud-helm-charts
          helm-charts-repo-branch: gh-pages
          chart-package: ${{ steps.package-helm-chart.outputs.package-file }}
          token: ${{ secrets.BOT_GITHUB_TOKEN}}
```

### send-slack-notification

Sends a slack notification with a pre-defined payload, relying on the [slackapi/slack-github-action](https://github.com/slackapi/slack-github-action) official action.

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/send-slack-notification@ref
        with:
          channel-id: 'channel-id'
          token: ${{ secrets.SLACK_BOT_TOKEN }}
          notification-color: '#A30200'
```

### setup-github-release-binary

[setup-github-release-binary](.github/actions/setup-github-release-binary/action.yml)
Allows the installation of a generic binary from GitHub Releases and add it to the PATH.
See [setup-helm-docs](.github/actions/setup-helm-docs/action.yml) for a usage example.

### travis-env-load

To ease the migration to GitHub Actions of repositories that contains one or
more yaml files containing an `env.global` section of Travis CI. It supports env vars
referencing as value env vars defined early in the file (like Travis does).

```yaml
      - uses: ./.github/actions/travis-env-load
        with:
          ignore_regex: ^BRANCH_NAME=.*
          yml_path: .travis/env.yml
```

### update-chart-version

Updates `version` attribute inside `Chart.yaml` file:

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/update-chart-version@ref
        with:
          new-version: 1.0.0
          chart-dir: charts/common
```

## Reusable workflows provided by us

### helm-publish-new-package-version.yml

Calculates the new alpha version, creates new git tag and publishes the new package to the helm chart repository

```yaml
  publish:
    uses: Alfresco/alfresco-build-tools/.github/workflows/helm-publish-new-package-version.yml@ref
    needs: build
    with:
      next-version: 7.4.0
      chart-dir: charts/common
      helm-charts-repo: Activiti/activiti-cloud-helm-charts
      helm-charts-repo-branch: gh-pages
    secrets: inherit
```

### build-and-tag-maven.yml

Builds a maven project and generates the new alpha version for it:

- publish maven artifacts to Nexus
- push docker images to quay.io
- create GitHub tag for the new alpha release

```yaml
  build:
    uses: Alfresco/alfresco-build-tools/.github/workflows/build-and-tag-maven.yml@ref
    secrets: inherit
```

### dependabot-auto-merge.yml

Handles automated approval and merge of dependabot PRs, for minor and patch version updates only.

The workflow requires a [dependabot secret](https://docs.github.com/en/code-security/dependabot/working-with-dependabot/managing-encrypted-secrets-for-dependabot), with the `repo > repo:status` and `repo > public_repo` scopes.

```yaml
  enable-auto-merge:
    uses: Alfresco/alfresco-build-tools/.github/workflows/dependabot-auto-merge.yml@ref
    with:
      token: ${{ secrets.DEPENDABOT_GITHUB_TOKEN }}
```

### versions-propagation-auto-merge.yml

Handles automated approval and merge of propagation PRs used to handle alpha releases on builds.

The workflow requires a secret named `BOT_GITHUB_TOKEN` to setup the "auto-merge" behaviour: the default `GITHUB_TOKEN`
is not used, otherwise a build would not be triggered when the PR is merged, [see reference solution](https://david.gardiner.net.au/2021/07/github-actions-not-running.html).

```yaml
  enable-auto-merge:
    uses: Alfresco/alfresco-build-tools/.github/workflows/versions-propagation-auto-merge.yml@ref
    secrets: inherit
```

## Cookbook

This section contains a list of recipes and common patterns organized by desired
outcome.

### Serialize pull request builds

When a workflow requires to access an external shared resource, it may be
desirable to prevent concurrent builds of the same pull request using
`concurrency` as a top-level keyword:

```yml
name: my-workflow
on:
  pull_request:
    branches:
      - develop
  push:
    branches:
      - develop
concurrency:
  group: ${{ github.head_ref || github.ref_name || github.run_id }}
  cancel-in-progress: false
```

The `github.head_ref` is available when workflow is triggered by pull_request
event, while `github.ref_name` when pushing branches and tags. The
`github.run_id` is just a fallback to avoid failure when both variables are both
empty.

More docs on [using concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency)

## Known issues

### realpath not available under macosx

When running pre-commit locally you may get failures with the following error:

```sh
realpath: command not found
```

This is because macosx lacks support for that, and it can be fixed with:

```sh
brew install coreutils
```

## Release

Run the release script to release a new version from this repository:

```sh
./release.sh v1.2.3
```
