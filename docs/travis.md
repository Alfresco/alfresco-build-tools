# Travis

This repository historically provides a bunch of common configuration that can be imported in
any travis build by adding:

```yaml
import:
  - source: Alfresco/alfresco-build-tools:.travis.<value>.yml@master
```

Travis snippets should be considered in maintenance mode only since we are actively
migrating all of our repos to GitHub Actions.

## Migrate from Travis to GitHub Actions

Before starting migrating your first repository, make sure you read [Migrating from Travis CI to GitHub Actions](https://docs.github.com/en/actions/migrating-to-github-actions/migrating-from-travis-ci-to-github-actions).

Hosted runners come with many bundled packages, see
[Available Environments](https://github.com/actions/virtual-environments#available-environments)
for details of what is already available when running GitHub Actions.

Here follows a table to ease migrating Travis build that were using config offered by this repo:

| Travis CI config file                     | GitHub Actions replacement                                                    |
|-------------------------------------------|-------------------------------------------------------------------------------|
| .travis.aws-iam-authenticator_install.yml | Not yet determined                                                            |
| .travis.awscli_install.yml                | Preinstalled                                                                  |
| .travis.checkov_install.yml               | [bridgecrewio/checkov-action](https://github.com/bridgecrewio/checkov-action) |
| .travis.common.yml                        | Outdated: use equivalent steps in the workflow                                |
| .travis.docker-buildx_install.yml         | [docker/setup-buildx-action](https://github.com/docker/setup-buildx-action)   |
| .travis.docker_hub_login.yml              | [docker/login-action](README.md#docker-login)                                 |
| .travis.docker_login.yml                  | [docker/login-action](README.md#docker-login)                                 |
| .travis.gh_install.yml                    | Preinstalled                                                                  |
| .travis.helm-docs_install.yml             | [setup-helm-docs](/.github/actions/setup-helm-docs/action.yml)                |
| .travis.helm.yml                          | Not yet determined                                                            |
| .travis.helm_install.yml                  | Preinstalled                                                                  |
| .travis.home_bin_path.yml                 | Not yet determined                                                            |
| .travis.java.yml                          | See [Java Setup section](README.md#setup-maven-build-options)                 |
| .travis.java_config.yml                   | See [Java Setup section](README.md#java-setup)                                |
| .travis.java_docker.yml                   | See [Java Setup section](README.md#setup-maven-build-options)                 |
| .travis.jq_install.yml                    | Preinstalled                                                                  |
| .travis.kcadm_install.yml                 | Not yet determined                                                            |
| .travis.kubepug_install.yml               | [setup-kubepug](/.github/actions/setup-kubepug/action.yml)                    |
| .travis.kubernetes_install.yml            | Preinstalled                                                                  |
| .travis.maven_config.yml                  | See [Java Setup section](README.md#java-setup)                                |
| .travis.pre-commit.yml                    | [pre-commit](/.github/actions/pre-commit)                                     |
| .travis.rancher_cli_config.yml            | [setup-rancher-cli](/.github/actions/setup-rancher-cli/action.yml)            |
| .travis.rancher_cli_install.yml           | [setup-rancher-cli](/.github/actions/setup-rancher-cli/action.yml)            |
| .travis.rancher_cli_kubernetes_config.yml | [setup-rancher-cli](/.github/actions/setup-rancher-cli/action.yml)            |
| .travis.srcclr_install.yml                | Not yet determined                                                            |
| .travis.terraform-docs_install.yml        | [setup-terraform-docs](/.github/actions/setup-terraform-docs/action.yml)      |
| .travis.terraform_install.yml             | Preinstalled                                                                  |
| .travis.tflint_install.yml                | Not yet determined                                                            |
| .travis.trigger.yml                       | Not yet determined                                                            |
| .travis.veracode.yml                      | [veracode](/.github/actions/veracode)                                         |
| .travis.yq_install.yml                    | Preinstalled                                                                  |

### Default environment variables

| Travis CI           | GitHub Actions          |
|---------------------|-------------------------|
| ${TRAVIS_BRANCH}    | ${{ github.ref_name }}  |
| ${TRAVIS_BUILD_DIR} | ${{ github.workspace }} |
| ${TRAVIS_COMMIT}    | ${{ github.sha }}       |

### Get back maven build output

Travis is very strict regarding maximum size of the build logs output and builds
that exceed 5MB in output will fail with `The job exceeded the maximum log
length, and has been terminated`. GitHub Actions doesn't have this kind of
limitation and it's highly recommended to **remove any logs suppression** of the
build tool.

With Maven this is usually achieved by using the `-q` option, that is usually
set globally inside the `MAVEN_CLI_OPTS` environment variable. Please remove any
usage of `-q` when migrating from Travis.

### Workflow schema validation

The `.pre-commit-config.yaml` configuration should be updated to remove the obsolete `check-travis` hook and replace it with `check-github-workflows`.
Note that a recent version of the `check-jsonschema` hook should be used to support reusable workflows.
Here is a sample configuration:

```yml
  - repo: https://github.com/sirosen/check-jsonschema
    rev: 0.17.0
    hooks:
      - id: check-github-workflows
      - id: check-jsonschema
        alias: check-dependabot
        name: "Validate Dependabot Config"
        files: '.github/dependabot\.yml$'
        args: ["--schemafile", "https://json.schemastore.org/dependabot-2.0.json"]
```
