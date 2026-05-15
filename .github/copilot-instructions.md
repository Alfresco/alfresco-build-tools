# GitHub Copilot Instructions for alfresco-build-tools

This repository contains shared/reusable CI configurations for GitHub Actions serving the Alfresco organization and broader community.

## Primary Development Guidelines

### Version Management (CRITICAL)

**Always add a label for every PR that contains functional changes** (not documentation-only changes):

- **release/patch**: Bug fixes in existing actions
- **release/minor**: New actions or backward-compatible improvements
- **release/major**: Breaking changes requiring users to update their workflows

When referencing internal actions in workflow YAML files, **always use the latest released tag** (e.g., `v9.2.0`),
the release workflow will automatically update these references during releases.

### Documentation Requirements (CRITICAL)

**MANDATORY: Always update `docs/README.md` when adding or modifying user-facing features of GitHub Actions.**

Documentation updates are required only for **user-facing changes**, such as:

- New actions or workflows
- New or modified inputs/outputs in existing actions
- New features or enhancements to existing action behavior
- Updated usage patterns or examples

Documentation updates are **NOT required** for:

- Bug fixes that restore expected behavior without changing the user-facing interface
- Internal refactoring with no observable change for users
- CI/infrastructure-only changes

**Before opening a PR with user-facing changes, you MUST:**

1. Update `docs/README.md` with the user-facing changes
2. Run `.github/scripts/check_readme.sh` to validate all actions are documented
3. Verify the documentation accurately reflects the current state

**Action Documentation Pattern**:

```markdown

### action-name

Brief description of what the action does.

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/action-name@ref
        with:
          parameter: value
```

Additional notes or configuration details.

**Note**: Always replace `@ref` with the most recent released tag (e.g., `@v9.1.0`).

**Run validation script** to ensure all actions are documented:

```bash
.github/scripts/check_readme.sh
```

## Action Development Guidelines

### File Structure

- Each action must be in `.github/actions/action-name/`
- Must contain `action.yml` file with proper metadata
- Include `README.md` for complex actions
- Follow existing action patterns for consistency

### Internal vs External Action References (CRITICAL)

**For reusable workflows and composite actions referencing actions within this repository:**

- **MUST** use SHA pins: `Alfresco/alfresco-build-tools/.github/actions/action-name@<40-char-sha>`
- **NEVER** use version tags: `Alfresco/alfresco-build-tools/.github/actions/action-name@v17.7.0`
- SHA pins are managed **automatically by the release process** — do not set them manually
- The release workflow creates a release candidate commit (SHA_RC) from the current HEAD, then the final release commit pins refs to SHA_RC — growing consistent depth by +2 levels per release cycle

**Examples:**

✅ **Correct (SHA pin):**

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2
```

❌ **Incorrect (version tag):**

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@v17.7.0
```

**For external actions (from other repositories):**

- **MUST** use SHA pins for security: `actions/checkout@08c6903cd8c0fde910a37f88322edcfb5dd907a8`
- Can't use version tags as they are mutable, SHA pins are mandatory for security

### Security Best Practices

- Pin external action versions to specific SHA commits in examples for security
- Avoid exposing secrets in logs
- Use `secrets.BOT_GITHUB_TOKEN` for authenticated operations
- Validate inputs and sanitize user-provided data

### Testing Requirements

- Add tests to `.github/tests/` for new actions when applicable
- Add new actions to existing workflow tests in `.github/workflows/tests.yml`
  if there are no side effects, secrets required, or external resources needed
- Test actions locally using the `test/local-actions` label
- Ensure actions work on both `ubuntu-latest` and `ubuntu-24.04-arm` runners
- Validate backward compatibility for existing actions

## Code Quality Standards

### Pre-commit Hooks

Always run pre-commit checks before submitting PRs:

```bash
# Install pre-commit hooks
pre-commit install

# Run checks manually
pre-commit run --all-files
```

### Shell Scripts

- Use `#!/bin/bash` with `set -e` for error handling
- Follow existing patterns in `release.sh` and `check_readme.sh`
- Validate script functionality on different OS platforms
- Use shellcheck for linting

### YAML/Workflow Files

- Use consistent indentation (2 spaces)
- Pin action versions with SHA comments
- Follow existing workflow patterns
- Validate YAML syntax with yamllint

## Release Process

### Automated Releases

- Releases are triggered automatically when PRs are merged to master
- The released version is determined from PR labels (`release/major`, `release/minor`, `release/patch`)
- Actions will automatically be updated with the release tag by the release workflow itself, no need to do it manually
- Release notes are auto-generated from PR titles and descriptions
- The `release.sh` script automatically pins all internal references to the SHA of the release candidate commit
- **CRITICAL**: Internal references must use SHA pins (not version tags); these are managed automatically by the release process — do not set them manually

### Pull Request Guidelines

- Use the provided PR template
- Select appropriate version increment checkbox
- Provide external PR link for testing
- Include Jira reference in title when applicable

## Action Categories and Patterns

### Setup Actions

For installing tools and dependencies:

- Pattern: `setup-*` naming convention
- Should output installed version
- Support version pinning via inputs
- Add tool to PATH

### Build/Deploy Actions

For CI/CD operations:

- Follow semantic patterns (`maven-*`, `helm-*`, `docker-*`)
- Support preview/dry-run modes when applicable
- Provide build artifacts as outputs
- Cache dependencies when possible

### Utility Actions

For common operations:

- Clear, descriptive naming
- Single responsibility principle
- Reusable across different workflows
- Well-documented inputs/outputs

## Common Pitfalls to Avoid

- **Never** skip version bumping for functional changes
- **CRITICAL**: Never use version tags for internal action references (`Alfresco/alfresco-build-tools/.github/...`) - always use SHA pins (managed automatically by the release process)
- **Don't** use `latest` tags for external actions - always pin versions
- **Avoid** hardcoding repository-specific values in reusable actions
- **Don't** merge PRs with user-facing changes (new features or enhancements) without updating `docs/README.md`
- **Never** commit secrets or sensitive information
- **Avoid** breaking backward compatibility without major version bump

## Pull Request Checklist

Before opening or reviewing a PR, verify:

1. ✅ **Documentation updated**: `docs/README.md` reflects all user-facing changes (new features or enhancements); skip for bug fixes
2. ✅ **Validation passed**: `.github/scripts/check_readme.sh` runs successfully
3. ✅ **Version label**: Appropriate `release/patch|minor|major` label added
4. ✅ **Pre-commit hooks**: All checks pass
5. ✅ **Internal references**: Use SHA pins (managed by release process), not version tags

## Useful Commands

```bash
# Check all actions are documented
.github/scripts/check_readme.sh

# Validate pre-commit hooks
pre-commit run --all-files

# Test specific action locally
cd .github/actions/action-name && bats tests/

# Find all internal action references (should use SHA pins, not version tags)
grep -r "Alfresco/alfresco-build-tools/.github" .github/ --include="*.yml"

# Check for forbidden version tags in internal references (should return no results)
grep -r "Alfresco/alfresco-build-tools/.github.*@v[0-9]" .github/ --include="*.yml"

# Find all SHA-pinned internal references (the correct format)
grep -r "alfresco-build-tools.*@[0-9a-f]\{40\}" .github/ --include="*.yml"

# Check for undocumented actions
diff <(ls .github/actions) <(grep -o "### [^#]*" docs/README.md | sed 's/### //')
```

## Additional Resources

- [Security Guidelines](../docs/security.md)
- [Terraform Workflows](../docs/terraform.md)
- [Pre-commit Hooks Documentation](../docs/pre-commit-hooks.md)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Semantic Versioning](https://semver.org/)

When in doubt, follow the established patterns in the repository and prioritize backward compatibility and clear documentation.
