# GitHub Copilot Instructions for alfresco-build-tools

This repository contains shared/reusable CI configurations for GitHub Actions serving the Alfresco organization and broader community.

## Primary Development Guidelines

### Version Management (CRITICAL)
**Always bump the version in `version.txt` for every PR that contains functional changes** (not documentation-only changes):

- **Patch version bump (x.y.Z)**: Bug fixes in existing actions
- **Minor version bump (x.Y.z)**: New actions or backward-compatible improvements  
- **Major version bump (X.y.z)**: Breaking changes requiring users to update their workflows

```bash
# Example: Update version.txt from v9.0.0 to v9.1.0 for a new action
echo "v9.1.0" > version.txt
```

### Documentation Requirements

1. **Always update `docs/README.md`** when adding or modifying GitHub Actions:
   - Add new action to table of contents
   - Include usage example with proper YAML syntax
   - Document all input parameters and outputs
   - Follow existing documentation patterns

2. **Action Documentation Pattern**:
```markdown
### action-name

Brief description of what the action does.

```yaml
      - uses: Alfresco/alfresco-build-tools/.github/actions/action-name@ref
        with:
          parameter: value
```

Additional notes or configuration details.
```

3. **Run validation script** to ensure all actions are documented:
```bash
./check_readme.sh
```

## Action Development Guidelines

### File Structure
- Each action must be in `.github/actions/action-name/`
- Must contain `action.yml` file with proper metadata
- Include `README.md` for complex actions
- Follow existing action patterns for consistency

### Security Best Practices
- Pin action versions to specific SHA commits in examples
- Avoid exposing secrets in logs
- Use `secrets.BOT_GITHUB_TOKEN` for authenticated operations
- Validate inputs and sanitize user-provided data

### Testing Requirements
- Add tests to `.github/tests/` for new actions when applicable
- Test actions locally using the `test/local-actions` label
- Ensure actions work on both `ubuntu-latest` and `ubuntu-24.04-arm` runners
- Validate backward compatibility for existing actions

### Dependencies Management
- Use Dependabot configuration in `.github/dependabot.yml`
- Pin external action versions to specific releases
- Update dependencies regularly but test thoroughly
- Prefer official actions over community alternatives when available

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
- The version in `version.txt` determines the release tag
- Release notes are auto-generated from PR titles and descriptions
- The `release.sh` script updates all version references

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
- **Don't** use `latest` tags for external actions - always pin versions
- **Avoid** hardcoding repository-specific values in reusable actions
- **Don't** merge PRs without updating documentation
- **Never** commit secrets or sensitive information
- **Avoid** breaking backward compatibility without major version bump

## Useful Commands

```bash
# Check all actions are documented
./check_readme.sh

# Validate pre-commit hooks
pre-commit run --all-files

# Test specific action locally
cd .github/actions/action-name && bats tests/

# Find all action references to update
grep -r "alfresco-build-tools.*@v" .github/

# Check for undocumented actions
diff <(ls .github/actions) <(grep -o "### [^#]*" docs/README.md | sed 's/### //')
```

## Additional Resources

- [Security Guidelines](security.md)
- [Terraform Workflows](terraform.md)  
- [Pre-commit Hooks Documentation](pre-commit-hooks.md)
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [Semantic Versioning](https://semver.org/)

When in doubt, follow the established patterns in the repository and prioritize backward compatibility and clear documentation.