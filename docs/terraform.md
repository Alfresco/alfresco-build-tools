# Terraform in Alfresco CI

This document describes the Terraform approach to managing infrastructure as
code (IaC) using Terraform. It outlines best practices, directory structure, and
workflow automation for Terraform projects within the Alfresco organization.

## Reusable workflow

We are currently maintaining a reusable workflow which implements an opinionated
workflow to manage terraform repositories leveraging the
[dflook/terraform-github-actions](https://github.com/dflook/terraform-github-actions),
optionally allowing a multi-state approach for managing resources.

You can provide Github environment name with `terraform_env` input. If not set,
this workflow assumes a GitHub environment named `production` to be present when
run against the `main` branch, and any other environment when run against
`develop` branch or any other branch.

GitHub Environments must be configured with the following GitHub variables
(repository or environment):

- `AWS_DEFAULT_REGION`: where the AWS resources will be created
- `AWS_ROLE_ARN` (optional): the ARN of the role to assume in case OIDC
  authentication is available
- `RANCHER2_URL` (optional): automatically register EKS cluster on a given rancher
  instance
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

The following GitHub secrets (all optional) are also accepted by this workflow:

- `AWS_ACCESS_KEY_ID`: access key to use the AWS terraform provider
- `AWS_SECRET_ACCESS_KEY`: secret key to use the AWS terraform provider
- `BOT_GITHUB_TOKEN` (to access private terraform modules in the Alfresco org)
- `DOCKER_USERNAME` (optional): Docker Hub credentials
- `DOCKER_PASSWORD` (optional): Docker Hub credentials
- `RANCHER2_ACCESS_KEY` (optional): access key to use the rancher terraform
  provider
- `RANCHER2_SECRET_KEY` (optional): secret key to use the rancher terraform
  provider

An example workflow using this reusable workflow could look like this:

```yaml
name: "terraform"
run-name: "terraform ${{ inputs.terraform_operation || (github.event_name == 'issue_comment' && 'apply') || ((github.event_name == 'pull_request' || github.event_name == 'pull_request_review') && 'plan' || 'apply') }} on ${{ github.event_name == 'issue_comment' && 'pr comment' || github.base_ref || github.ref_name }}"

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
  # optional - to trigger a terraform apply adding a pr comment with text 'terraform apply'
  issue_comment:
    types: [created]
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

jobs: # one job for each terraform folder/stack
  invoke-terraform-infra:
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v8.32.0
    with:
      terraform_root_path: infra
      terraform_operation: ${{ inputs.terraform_operation }}
    secrets: inherit

  invoke-terraform-k8s:
    needs: invoke-terraform-infra
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform.yml@v8.32.0
    with:
      terraform_root_path: k8s
      terraform_operation: ${{ inputs.terraform_operation }}
      # Optionally make `kubectl` available to terraform
      # install_kubectl: true
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
    uses: Alfresco/alfresco-build-tools/.github/workflows/terraform-pre-commit.yml@v8.32.0
    with:
      BOT_GITHUB_USERNAME: ${{ vars.BOT_GITHUB_USERNAME }}
    secrets: inherit
```

## Environment badges

At the top of the README file, you should list a badge for every configured environment, to ease raising PRs to keep them up to date. You can use the following Markdown snippet to add a badge for each environment:

```markdown
[![update ENV-NAME env](https://img.shields.io/badge/⚠️-update%20ENV--NAME%20env-blue)](https://github.com/Alfresco/REPO-NAME/compare/ENV-NAME...develop?expand=1&title=Update%20ENV-NAME%20env)
```

Replace `REPO-NAME` with the name of the GitHub repository and `ENV-NAME` with
the name of the environment (e.g., `development`, `staging`, `production`) which
also correspond to the branch name.

Please note that `img.shields.io` badge also requires escaping single dash to
double dash to work properly.
