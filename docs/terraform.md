---
title: Terraform in Alfresco CI
---

This document describes the Terraform approach to managing infrastructure as
code (IaC) using Terraform. It outlines best practices, directory structure, and
workflow automation for Terraform projects within the Alfresco organization.

## Reusable workflow

We are currently maintaining a reusable workflow which implements an opinionated
workflow to manage terraform repositories leveraging the
[dflook/terraform-github-actions](https://github.com/dflook/terraform-github-actions).

The combination of dynamic stack/folder detection based on changed files and
environment detection based on changed tfvars files for PRs targeting the
default branch, and branch-based environment selection for other branches,
allows for a flexible and automated workflow that adapts to different
development and deployment scenarios. With this approach you can:

- raise a PR with changes to a specific stack/folder and tfvars file to target a
  specific environment
- raise a PR with changes to a specific stack/folder without changing any tfvars file
  to target the default environment for that stack
- promote changes already merged to the default branch to other environments by
  raising a PR to merge the default branch into the target environment branch.
  Optionally use the [branch promotion workflow](#branch-promotion-workflow) to
  automate this process.

Or alternatively, you can always provide a specific stack/folder and environment
as workflow inputs for a more controlled deployment (see `terraform_root_path`
and `terraform_env` inputs below).

### GitHub Environments

GitHub Environments must be used to manage different deployment stacks (your
infrastructure) and environments (e.g. dev, preprod, production) and their
associated secrets and variables.

You can provide a GitHub environment name with the `terraform_env` input to
target a specific environment.

When `terraform_env` is not explicitly set, the workflow will attempt to
determine the environment dynamically by locating the first changed `.tfvars`
file which matches the environment name. This detection applies to both pull
requests and pushes against the **default branch**.

If no `.tfvars` file is changed, the workflow will default to an environment
named `<terraform_root_path>-dev` (e.g. `infra-dev` if `terraform_root_path` is
`infra`), or to the value provided in the `terraform_default_env` input if set
(e.g. `develop`).

For branches that are not the default branch, the tfvars file matching will not
be applied, and the workflow falls back to a branch-based environment approach,
where: PRs and pushes targeting the `main` branch use the `production`
environment, while all the other branches use the branch name as the environment
(e.g. `develop` for the `develop` branch, `preprod` for the `preprod` branch,
etc.).

GitHub Environments must be configured with the following GitHub variables
(repository or environment):

- `AWS_DEFAULT_REGION`: where the AWS resources will be created
- `AWS_ROLE_ARN` (optional): the ARN of the role to assume in case OIDC
  authentication is available
- `RESOURCE_NAME`: used to namespace every resource created, e.g. State file in
  the S3 bucket. You can use it as well inside Terraform by defining a variable
  `resource_name` in your Terraform code.
- `TERRAFORM_STATE_BUCKET`: the name of the S3 bucket where to store the terraform
  state. You can reuse the same bucket for multiple environments as long as you
  provide a different `RESOURCE_NAME` for each environment.

Alternatively to providing `AWS_ROLE_ARN` as GitHub variable, you can set
`create_oidc_token_file` input to `true` to request an AWS OIDC token which will
be persisted into a file and can be used inside terraform code e.g. like this:

```tf
backend "s3" {
  assume_role_with_web_identity = {
    role_arn                = "arn:aws:iam::372466110691:role/AlfrescoCI/alfresco-common-resources-deploy"
    web_identity_token_file = "/github/workspace/idtoken.json"
  }
}
```

### GitHub Secrets

The following GitHub secrets (all optional) are also accepted by this workflow:

- `AWS_ACCESS_KEY_ID`: (optional when using OIDC) access key to use the AWS terraform provider
- `AWS_SECRET_ACCESS_KEY`: (optional when using OIDC) secret key to use the AWS terraform provider
- `BOT_GITHUB_TOKEN` (to access private terraform modules in the Alfresco org)
- `DOCKER_USERNAME` (optional): Docker Hub credentials
- `DOCKER_PASSWORD` (optional): Docker Hub credentials
- `RANCHER2_ACCESS_KEY` (optional): access key to use the rancher terraform
  provider
- `RANCHER2_SECRET_KEY` (optional): secret key to use the rancher terraform
  provider

### Tfvars files

By default, the workflow will look for tfvars files in the root of the
`terraform_root_path` folder. You can specify a different relative subfolder
using the `tfvars_subfolder` input. It's highly recommended to use a `vars`
subfolder to store your tfvars files.

Having a shared `common.tfvars` file is required to define common variables
across all environments, e.g. tags, resource names, etc. It can be a blank file
if no common variables are needed.

Any other tfvars file must be named after the GitHub environment name, e.g.
`production.tfvars`, `develop.tfvars`, etc.

When running against the default branch, the workflow will target the
environment matching the first changed `.tfvars` file, or fallback to the
default environment as per `terraform_default_env` input or
`<terraform_root_path>-dev` convention if no tfvars file is changed.

When running against any other branch, the workflow will target the environment
matching the branch name (`base_ref` for `pull_request`, `ref_name` for `push`).

### PR comments

When the workflow is triggered by a PR comment, it will look for the presence of
the strings `terraform plan` or `terraform apply` in the comment body to determine
the requested operation.

Currently there are no additional restrictions on who/when can trigger terraform
operations via PR comments, so it's recommended to enable deployment protection
rules on production environments.

### Environment variables

You can provide additional environment variables to the terraform execution by
creating a file named `tfenv.yml` in the root of your terraform workspace,
following the syntax supported by [env-load-from-yaml action](README.md#env-load-from-yaml)

### Example usage

An example workflow using this reusable workflow could look like this:

```yaml
name: "terraform"
run-name: "terraform ${{ inputs.terraform_operation || (github.event_name == 'issue_comment' && 'run') || ((github.event_name == 'pull_request' || github.event_name == 'pull_request_review') && 'plan' || 'apply') }} on ${{ github.event_name == 'issue_comment' && 'pr comment' || github.base_ref || github.ref_name }}"

on:
  pull_request:
    branches:
      - main
      - develop
      - preprod
  push:
    branches:
      - main
      - develop
      - preprod
  # optional - to trigger a terraform operation by adding a PR comment
  # with text 'terraform plan' or 'terraform apply'
  issue_comment:
    types: [created]
  # optional - to trigger manually from the Actions tab with a specific operation
  workflow_dispatch:
    inputs:
      terraform_operation:
        description: 'CAUTION: perform the requested operation with Terraform on the selected branch'
        type: choice
        required: true
        options:
          - plan
          - apply
          - destroy

permissions:
  pull-requests: write
  contents: read
  # id-token: write # required to use OIDC authentication with AWS

jobs:
  # Single job for all terraform folders/stacks, with dynamic detection of the root path
  # and environment based on changed files in PRs/pushes against the default branch,
  # or branch name for other branches.
  invoke-terraform:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v15.6.2
    with:
      # Autodetected using the first changed folder (alphabetically) in PR/push
      #
      # terraform_root_path: my-subfolder

      # Autodetected using the first changed tfvars file in PR/push,
      # or by branch name for non-default branches.
      #
      # terraform_env: my-env

      # Used as fallback if no tfvars file is changed in PR/push against the default branch
      # Defaults to <terraform_root_path>-dev if not set
      #
      # terraform_default_env:

      # Only needed for workflow_dispatch, auto-detected for PRs and pushes:
      terraform_operation: ${{ inputs.terraform_operation }}

      # Recommended to have a structured layout with tfvars files in a separate subfolder.
      tfvars_subfolder: vars
    secrets: inherit

  # One job for a specific terraform folder/stack.
  # Environment can still be auto-detected based on changed tfvars files or branch name.
  invoke-terraform-infra:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v15.6.2
    with:
      terraform_root_path: infra
      terraform_default_env: develop
      terraform_operation: ${{ inputs.terraform_operation }}
      tfvars_subfolder: vars
    secrets: inherit

  # Another job for a different terraform folder/stack
  # which depends on the previous one if you want to ensure
  # a specific execution order (e.g. infra before k8s).
  invoke-terraform-k8s:
    needs: invoke-terraform-infra
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v15.6.2
    with:
      terraform_root_path: k8s
      terraform_default_env: develop
      terraform_operation: ${{ inputs.terraform_operation }}
      tfvars_subfolder: vars
      # Optionally install kubectl (see kubectl support section below)
      # install_kubectl: true
      # kubectl_version: v1.28.0  # optional - defaults to latest stable
    secrets: inherit

  # The most static approach with hardcoded terraform root path and environment,
  # which can be useful for simple repositories with a single stack and environment,
  # or for scheduled workflows.
  invoke-terraform-static:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v15.6.2
    with:
      terraform_root_path: infra
      terraform_env: production
      terraform_operation: plan
      tfvars_subfolder: vars
```

### kubectl support

The terraform workflow can optionally install `kubectl` CLI tool to make it
available during terraform execution. This is useful when you need to interact
with Kubernetes clusters as part of your terraform provisioning
e.g. in a `null_resource`.

You can enable kubectl installation by setting the `install_kubectl` input to
`true`. By default, this will install the latest stable version of kubectl.

If you need a specific version, you can specify it using the `kubectl_version`
input. The version should be provided in the format `vX.Y.Z` (e.g., `v1.28.0`).

Example:

```yaml
jobs:
  invoke-terraform-k8s:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v15.6.2
    with:
      terraform_root_path: k8s
      install_kubectl: true
      kubectl_version: v1.28.0  # optional - defaults to latest stable
    secrets: inherit
```

## pre-commit config

Each terraform repository should have a `.pre-commit-config.yaml` file in the
root directory with the following configuration:

```yaml
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-json
      - id: check-xml
      - id: mixed-line-ending
        args: ["--fix=lf"]
      - id: end-of-file-fixer
      - id: trailing-whitespace

  - repo: https://github.com/antonbabenko/pre-commit-terraform
    rev: v1.97.0
    hooks:
      - id: terraform_fmt
      - id: terraform_docs
        args:
          - --hook-config=--path-to-file=README.md
          - --hook-config=--add-to-existing-file=true
          - --hook-config=--create-file-if-not-exist=true
      - id: terraform_tflint
      - id: terraform_providers_lock
        args:
        - --hook-config=--mode=only-check-is-current-lockfile-cross-platform
        - --args=-platform=linux_amd64
        - --args=-platform=darwin_amd64
        - --args=-platform=darwin_arm64
      - id: terraform_checkov
```

The pre-commit workflow should look like this:

```yaml
name: pre-commit

on:
  pull_request:
    branches:
      - develop
      - ...
  push:
    branches:
      - develop
      - ...

permissions:
  contents: write

jobs:
  pre-commit:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform-pre-commit.yml@v15.6.2
    with:
      BOT_GITHUB_USERNAME: ${{ vars.BOT_GITHUB_USERNAME }}
    secrets: inherit
```

## Branch promotion workflow

For Terraform projects with multiple environment branches, you can use the
branch promotion workflow to automate the creation of pull requests when
promoting changes across environments.

See [main documentation](README.md#branch-promotion-prs) for usage
documentation.
