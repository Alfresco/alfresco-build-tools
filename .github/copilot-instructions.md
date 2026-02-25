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

**MANDATORY: Always update `docs/README.md` when adding or modifying GitHub Actions.**

This is required for ANY change to actions, including:

- New actions or workflows
- Modified inputs/outputs in existing actions
- Changed action behavior or functionality
- Updated usage patterns or examples

**Before opening a PR, you MUST:**

1. Update `docs/README.md` with the changes
2. Run `./check_readme.sh` to validate all actions are documented
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
./check_readme.sh
```

## Action Development Guidelines

### File Structure

- Each action must be in `.github/actions/action-name/`
- Must contain `action.yml` file with proper metadata
- Include `README.md` for complex actions
- Follow existing action patterns for consistency

### Internal vs External Action References (CRITICAL)

**For reusable workflows and composite actions referencing actions within this repository:**

- **MUST** use version tags: `Alfresco/alfresco-build-tools/.github/actions/action-name@v15.5.0`
- **NEVER** use SHA pins: `Alfresco/alfresco-build-tools/.github/actions/action-name@abc123def456`
- This ensures the `release.sh` script can automatically update all internal references during releases

**Examples:**

✅ **Correct (version tag):**

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@v15.5.0
```

❌ **Incorrect (SHA pin):**

```yaml
- uses: Alfresco/alfresco-build-tools/.github/actions/setup-java-build@abc123def456
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
- The `release.sh` script automatically updates all internal version references that use version tags
- **CRITICAL**: Internal references must use version tags (not SHA pins) for automatic updates to work

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
- **CRITICAL**: Never use SHA pins for internal action references (`Alfresco/alfresco-build-tools/.github/...`) - always use version tags to ensure automatic release updates work
- **Don't** use `latest` tags for external actions - always pin versions
- **Avoid** hardcoding repository-specific values in reusable actions
- **Don't** merge PRs without updating documentation
- **Never** commit secrets or sensitive information
- **Avoid** breaking backward compatibility without major version bump

## Pull Request Checklist

Before opening or reviewing a PR, verify:

1. ✅ **Documentation updated**: `docs/README.md` reflects all action changes
2. ✅ **Validation passed**: `./check_readme.sh` runs successfully
3. ✅ **Version label**: Appropriate `release/patch|minor|major` label added
4. ✅ **Pre-commit hooks**: All checks pass
5. ✅ **Internal references**: Use version tags, not SHA pins

**When reviewing PRs that modify actions, ALWAYS check if `docs/README.md` was updated.**

## Useful Commands

```bash
# Check all actions are documented
./check_readme.sh

# Validate pre-commit hooks
pre-commit run --all-files

# Test specific action locally
cd .github/actions/action-name && bats tests/

# Find all internal action references (should use version tags)
grep -r "Alfresco/alfresco-build-tools/.github" .github/

# Check for forbidden SHA pins in internal references (should return no results)
grep -r "Alfresco/alfresco-build-tools/.github.*@[a-f0-9]\{7,\}" .github/

# Find all version tag references for release updating
grep -r "alfresco-build-tools.*@v" .github/

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
