# alfresco-build-tools

[![Last release](https://img.shields.io/github/v/release/alfresco/alfresco-build-tools)](https://github.com/Alfresco/alfresco-build-tools/releases/latest)
[![CI](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml/badge.svg)](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test.yml)
[![CI with BATS 🦇](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test-with-bats.yml/badge.svg)](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/test-with-bats.yml)
[![Release](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/release.yml/badge.svg)](https://github.com/Alfresco/alfresco-build-tools/actions/workflows/release.yml)
[![GitHub contributors](https://img.shields.io/github/contributors/alfresco/alfresco-build-tools)](https://github.com/Alfresco/alfresco-build-tools/graphs/contributors)

This repository contains shared/reusable CI configurations for GitHub Actions to serve the repositories of the Alfresco org but virtually usable by everyone.

For reading the docs, please browse the [web version](https://alfresco.github.io/alfresco-build-tools/).

For the index of the docs, see the [docs README.md](docs/README.md)

For security-related topics of GitHub Actions, see the [Security section](docs/security.md).

For terraform-related topics of GitHub Actions, see the [Terraform section](docs/terraform.md).

For pre-commit hooks documentation, see the [Pre-commit Hooks section](docs/pre-commit-hooks.md).

For Python scripts testing guidelines, see the [Python Testing documentation](.github/tests/python-scripts/README.md).

For GitHub Copilot instructions and development guidelines, see [`.github/copilot-instructions.md`](.github/copilot-instructions.md).

## Release

Add a label to the PR among `release/major`, `release/minor`, or `release/patch`
to trigger a release upon merging the PR.

New versions should follow [Semantic versioning](https://semver.org/), so:

- A bump in the third number will be required if you are bug fixing an existing
  action.
- A bump in the second number will be required if you introduced a new action or
  improved an existing action, ensuring backward compatibility.
- A bump in the first number will be required if there are major changes in the
  repository layout, or if users are required to change their workflow config
  when upgrading to the new version of an existing action.
