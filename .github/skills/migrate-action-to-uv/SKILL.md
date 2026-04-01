---
name: migrate-action-to-uv
description: "Migrate a composite GitHub Action from requirements.txt + pip to uv. Use when: converting action.yml that uses pip install and requirements.txt to use uv with pyproject.toml; modernizing python dependency management in GitHub Actions; replacing setup-python + pip cache + pip install steps with setup-uv; migrating python scripts to run via uv run --frozen --project."
---

# Migrate Composite Action from requirements.txt to uv

## When to Use

- An `action.yml` installs Python deps from a `requirements.txt` via `pip install`
- You want reproducible, fast installs using `uv` with a lockfile
- Python scripts in the action need to run via `uv run --frozen --project`

## Migration Steps

### 1. Replace `requirements.txt` with `pyproject.toml` + `uv.lock`

Create `pyproject.toml` next to `action.yml`:

```toml
[project]
name = "my-action"
version = "0.1.0"
description = "Short description of the action."
requires-python = ">=3.11"
dependencies = [
    "some-package>=1.2.3",
]

[tool.uv]
required-version = "==0.9.28"  # pin to a specific uv version for reproducibility
```

Generate the lockfile (run locally):

```bash
cd .github/actions/my-action
uv lock
```

Delete `requirements.txt` after verifying the lockfile is correct.

### 2. Update `action.yml` steps

**Before (pip pattern):**

```yaml
- name: Setup Python
  uses: actions/setup-python@<sha> # vX.Y.Z
  id: setup-python
  with:
    python-version: ${{ inputs.python-version }}

- name: Workaround for hashFiles not working outside current workspace
  shell: bash
  run: cp ${{ github.action_path }}/requirements.txt requirements-copy.txt

- uses: actions/cache@<sha> # vX.Y.Z
  with:
    path: ~/.cache/pip
    key: ${{ runner.os }}-pip-${{ hashFiles('requirements-copy.txt') }}

- name: Install requirements via pip
  shell: bash
  run: ${{ steps.setup-python.outputs.python-path }} -m pip install -r ${{ github.action_path }}/requirements.txt

- name: Run script
  shell: bash
  run: ${{ steps.setup-python.outputs.python-path }} ${{ github.action_path }}/script.py
```

**After (uv pattern):**

```yaml
- name: Set up Python ${{ inputs.python-version }}
  uses: actions/setup-python@<sha> # vX.Y.Z
  with:
    python-version: ${{ inputs.python-version }}

- name: Install uv
  uses: astral-sh/setup-uv@<sha> # vX.Y.Z
  with:
    working-directory: ${{ github.action_path }}

- name: Cache pre-commit  # rename to match your action's purpose
  uses: actions/cache@<sha> # vX.Y.Z
  with:
    path: ~/.cache/uv
    key: uv-${{ env.pythonLocation }}|${{ hashFiles(format('{0}/uv.lock', github.action_path)) }}

- name: Run script
  shell: bash
  run: uv run --frozen --project ${{ github.action_path }} python ${{ github.action_path }}/script.py
```

### 3. Key rules for `uv run --frozen --project`

| Flag               | Purpose                                                             |
| ------------------ | ------------------------------------------------------------------- |
| `--frozen`         | Use the lockfile exactly as-is; fail if it's outdated               |
| `--project <path>` | Point uv to the directory containing `pyproject.toml` and `uv.lock` |

Always use `github.action_path` for both `--project` and the script path so the action works when called from any repository.

### 4. Pin `astral-sh/setup-uv` to a SHA

External actions must use SHA pins for security per repository policy:

```yaml
- uses: astral-sh/setup-uv@cec208311dfd045dd5311c1add060b2062131d57 # v8.0.0
```

Find the latest SHA at the [astral-sh/setup-uv releases page](https://github.com/astral-sh/setup-uv/releases).

### 5. Remove the `hashFiles` workaround

The old pattern copied `requirements.txt` into the workspace root because `hashFiles()` only works within the workspace. With `uv`, reference the lockfile path directly via `github.action_path` in the cache key — or drop the cache step entirely since `uv` is already fast without it.

### 6. Commit generated files

Track both `pyproject.toml` and `uv.lock` in version control. Do **not** add `.venv/` — add it to `.gitignore`.

### 7. Update `.github/dependabot.yml`

Dependabot tracks Python deps per package ecosystem. After migration:

1. **Remove** the action's directory from the `pip` ecosystem block:

```yaml
# Before
- package-ecosystem: "pip"
  directories:
    - "/.github/actions/my-action"   # <-- remove this line
    - "/.github/actions/other-action"
```

1. **Add** the action's directory to the `uv` ecosystem block (create the block if it doesn't exist yet):

```yaml
- package-ecosystem: "uv"
  directories:
    - "/.github/actions/pre-commit"
    - "/.github/actions/my-action"   # <-- add this line
  schedule:
    interval: "weekly"
  labels:
    - "dependencies"
    - "python"
  cooldown:
    default-days: 7
  commit-message:
    prefix: "feat(deps)"
    prefix-development: "chore(deps)"
```

If the action's directory was the last entry in the `pip` block, remove the entire `pip` ecosystem entry.

## Example: `slack-file-upload` migrated

```yaml
- name: Set up Python ${{ inputs.python-version }}
  uses: actions/setup-python@<sha> # v6.2.0
  with:
    python-version: ${{ inputs.python-version }}

- name: Install uv
  uses: astral-sh/setup-uv@<sha> # vX.Y.Z
  with:
    working-directory: ${{ github.action_path }}

- name: Upload file to Slack
  shell: bash
  env:
    SLACK_BOT_TOKEN: ${{ inputs.slack-token }}
    SLACK_CHANNEL_ID: ${{ inputs.slack-channel-id }}
  run: uv run --frozen --project ${{ github.action_path }} python ${{ github.action_path }}/slack_file_upload.py "${{ inputs.file-path }}" "${{ inputs.file-title }}"
```

## Reference: Fully Migrated Action (pre-commit)

See [`.github/actions/pre-commit/action.yml`](../../actions/pre-commit/action.yml) and its [`pyproject.toml`](../../actions/pre-commit/pyproject.toml) as a complete real-world example in this repository.
