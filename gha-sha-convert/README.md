# GitHub Actions SHA Converter

A pre-commit hook that automatically converts GitHub Actions references to use SHA-pinned versions for improved supply chain security while preserving semantic version comments.

## Overview

This tool helps secure your GitHub workflows by:

- Converting action references from tags/branches to SHA hashes
- Preserving semantic version information in comments
- Providing supply chain security against tag manipulation
- Supporting both manual execution and pre-commit integration

## Features

- **Automatic SHA Conversion**: Converts `uses: actions/checkout@v3` to `uses: actions/checkout@a12b3c4d...ef56 # v3.1.0`
- **Semantic Version Preservation**: Maintains version information in comments for readability
- **Smart Caching**: Reduces API calls by caching SHA lookups
- **Force Mode**: Option to re-process already converted actions
- **Discovery Mode**: Scan files without making API calls or changes
- **Dry Run Mode**: Make API calls but don't modify files
- **First-Party Exclusion**: Option to exclude trusted actions (actions/, microsoft/, etc.)
- **Flexible Path Support**: Process specific paths or directories
- **Comprehensive Error Handling**: Graceful handling of API errors and rate limits
- **Pre-commit Integration**: Works seamlessly with pre-commit hooks

## Installation

### As a Pre-commit Hook

Add to your `.pre-commit-config.yaml`:

```yaml
repos:
  - repo: local
    hooks:
      - id: gha-sha-convert
        name: GitHub Actions SHA Converter
        description: Convert GitHub Actions to use SHA-pinned versions
        entry: python3 alfresco-build-tools/gha-sha-convert/gha_sha_convert.py
        language: system
        files: ^\.github/(workflows|actions)/.*\.(yml|yaml)$
        pass_filenames: true
```

### Standalone Installation

```bash
cd gha-sha-convert
pip install -e .
```

## Usage

### As Pre-commit Hook

```bash
# Install pre-commit
pip install pre-commit

# Install the hooks
pre-commit install

# Run on all files
pre-commit run gha-sha-convert --all-files
```

### Manual Execution

```bash
# Process all workflow files in current directory
python3 gha_sha_convert.py

# Process specific files
python3 gha_sha_convert.py .github/workflows/ci.yml

# Force re-processing of already converted actions
python3 gha_sha_convert.py --force

# Discovery mode - scan without making changes
python3 gha_sha_convert.py --discovery

# Dry run mode - show what would be changed
python3 gha_sha_convert.py --dry-run --token YOUR_TOKEN

# Exclude first-party actions from conversion
python3 gha_sha_convert.py --exclude-first-party

# Process specific directory paths
python3 gha_sha_convert.py --path .github/workflows --path .github/actions

# Use custom token
python3 gha_sha_convert.py --token YOUR_GITHUB_TOKEN
```

## Configuration

### Environment Variables

- `GITHUB_TOKEN`: GitHub personal access token for API access (required for conversions)

### Command Line Options

- `--force`: Force re-processing of already converted actions
- `--token TOKEN`: Specify GitHub token directly (alternative to environment variable)
- `--path PATH`: Specify custom search paths (can be used multiple times)
- `--discovery`: Discovery mode - scan files without making API calls or changes
- `--dry-run`: Dry run mode - make API calls but don't modify files (requires token)
- `--exclude-first-party`: Exclude first-party actions from conversion (actions/, microsoft/, azure/, etc.)

### GitHub Token Setup

1. Go to GitHub Settings → Developer settings → Personal access tokens
2. Create a new token with `public_repo` scope (or `repo` for private repositories)
3. Set the token as an environment variable:

```bash
export GITHUB_TOKEN=your_token_here
```

## Example Transformations

### Before

```yaml
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3.1.0
      - uses: docker/build-push-action@v2.10.0
```

### After

```yaml
name: CI
on: [push]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@24cb9080177805b6db47b1a7d4d8b7bb6d8feca6 # v3.1.0
      - uses: actions/setup-node@46071b5c7a2e0c34e49c3cb8a0e792e86e18d5e4 # v3.1.0
      - uses: docker/build-push-action@ac9327eae2b366085ac7f6a2d02df8aa8ead720a # v2.10.0
```

## How It Works

1. **File Discovery**: Scans `.github/workflows/` and `.github/actions/` for YAML files
2. **Reference Extraction**: Uses regex to find all `uses:` statements with action references
3. **SHA Resolution**: Calls GitHub API to resolve tags/branches to SHA hashes
4. **Version Detection**: Finds the best semantic version for the SHA from available tags
5. **Content Replacement**: Updates files with SHA-pinned references and version comments

## Security Benefits

- **Tag Immutability**: SHA hashes cannot be changed, preventing tag manipulation attacks
- **Supply Chain Protection**: Ensures you're always using the exact code you tested with
- **Audit Trail**: Version comments maintain readability and upgrade path visibility
- **Dependency Transparency**: Clear visibility into which exact versions are being used

## Development

### Running Tests

```bash
cd gha-sha-convert
python3 -m pytest test_gha_sha_convert.py -v
```

### Test Coverage

```bash
pip install coverage
coverage run -m pytest test_gha_sha_convert.py
coverage report
coverage html
```

## Troubleshooting

### Common Issues

1. **Rate Limit Exceeded**:
   - Ensure you have a valid `GITHUB_TOKEN` set
   - Consider running on smaller batches of files

2. **Tag Not Found**:
   - Some actions may use non-standard versioning
   - Check the action's repository for available tags

3. **Permission Denied**:
   - Ensure your GitHub token has appropriate permissions
   - For private repositories, use `repo` scope instead of `public_repo`

### Debug Mode

For debugging, you can add print statements or use Python's logging module:

```python
import logging
logging.basicConfig(level=logging.DEBUG)
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

This project is part of the Alfresco Build Tools and follows the same licensing terms.
