# GitHub Actions Ensure SHA Pinned Actions

A GitHub Action that ensures all GitHub Actions in your workflows use SHA-pinned versions instead of tag references for enhanced supply chain security.

## Features

- **SHA Pinning**: Converts tag references (e.g., `v1.0.0`) to SHA hashes with semantic version comments
- **Allowlist Support**: Skip specific actions from conversion using flexible pattern matching
- **First-party Exclusion**: Option to exclude actions from trusted organizations (actions/, microsoft/, etc.)
- **Dry Run Mode**: Preview changes without modifying files
- **Discovery Mode**: Fast scanning without API calls
- **Comprehensive Output**: Detailed statistics and reporting

## Usage

### Basic Usage

```yaml
name: Ensure SHA Pinned Actions
on: [push, pull_request]

jobs:
  security:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Ensure SHA pinned actions
        uses: Alfresco/alfresco-build-tools/.github/actions/github-actions-ensure-sha-pinned-actions@v1.0.0
```

### With Allowlist

```yaml
- name: Ensure SHA pinned actions
  uses: Alfresco/alfresco-build-tools/.github/actions/github-actions-ensure-sha-pinned-actions@v1.0.0
  with:
    allowlist: |
      actions/*
      microsoft/*
      Alfresco/alfresco-build-tools/*
```

### Advanced Configuration

```yaml
- name: Ensure SHA pinned actions
  uses: Alfresco/alfresco-build-tools/.github/actions/github-actions-ensure-sha-pinned-actions@v1.0.0
  with:
    allowlist: |
      actions/checkout@*
      actions/setup-*
      microsoft/*
    exclude-first-party: 'true'
    dry-run: 'true'
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `allowlist` | List of action patterns to exclude from SHA pinning (one per line) | No | `''` |
| `exclude-first-party` | Whether to exclude first-party actions (actions/, microsoft/, etc.) | No | `'false'` |
| `dry-run` | Only report what would be changed without making modifications | No | `'false'` |
| `discovery` | Only discover and list actions without making API calls | No | `'false'` |
| `github-token` | GitHub token for API access | No | `${{ github.token }}` |
| `path` | Path to search for workflows and actions | No | `'.'` |

## Outputs

| Output | Description |
|--------|-------------|
| `actions-found` | Number of action references found |
| `actions-converted` | Number of actions converted to SHA format |
| `files-modified` | Number of files that were modified |

## Allowlist Patterns

The allowlist supports several pattern formats:

### Wildcard Patterns

- `actions/*` - All actions from the `actions` organization
- `*/*` - All actions (not recommended)
- `owner/repo/*` - All actions from a specific repository

### Exact Patterns

- `actions/checkout@v4` - Specific action and version
- `owner/repo` - Specific repository

### Organization Patterns

- `microsoft/*` - All Microsoft actions
- `Alfresco/*` - All Alfresco actions

### Comments and Empty Lines

Lines starting with `#` are treated as comments and ignored. Empty lines are also ignored.

## Example Conversions

| Before | After |
|--------|--------|
| `uses: actions/checkout@v4` | `uses: actions/checkout@abc123...def789 # v4.1.7` |
| `uses: actions/setup-node@v3.1.0` | `uses: actions/setup-node@def456...abc123 # v3.1.0` |

## Security Benefits

- **Supply Chain Security**: Prevents malicious updates to existing tags
- **Reproducible Builds**: Ensures exact same action code is used across runs
- **Audit Trail**: Clear visibility of which action versions are being used
- **Version Comments**: Maintains human-readable version information

## Comparison with Other Tools

This action replaces external tools like `zgosalvez/github-actions-ensure-sha-pinned-actions` with:

- Native integration with your repository
- Enhanced allowlist functionality with pattern matching
- Better error handling and reporting
- Consistent behavior with your other security tools

## Local Development

You can also use the underlying Python script directly:

```bash
# Discovery mode (no API calls)
python3 gha-sha-convert/gha_sha_convert.py --discovery --path .github/workflows/

# Dry run mode (shows what would change)
python3 gha-sha-convert/gha_sha_convert.py --dry-run --path .github/workflows/

# With allowlist file
python3 gha-sha-convert/gha_sha_convert.py --allowlist allowlist.txt --path .github/workflows/
```

## Contributing

This action is part of the Alfresco Build Tools collection. Please submit issues and pull requests to the main repository.
