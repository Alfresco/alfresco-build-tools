# Python scripts testing

This document describes how Python scripts used in GitHub Actions must be tested.
It defines conventions for unit tests, integration tests, and pollution tests.

Actions are expected to have a main script called `action.py`.
If you choose a different entry point, you must adapt the test fixtures accordingly.

## CI Behavior

The CI pipeline:

- Always runs unit tests.
- Runs integration tests only when explicitly requested via PR labels.
- Centralizes test results for all actions in the workflow summary.
- Integration and pollution tests are opt-in to avoid unnecessary execution time and external side effects.

### Test Execution Matrix

| Test Type   | When It Runs                         | Purpose                          |
|-------------|--------------------------------------|----------------------------------|
| Unit        | Always                               | Validate internal logic          |
| Integration | With `test/python-integration` label | Validate remote behavior         |
| Pollution   | With both integration labels         | Validate irreversible operations |

### Automatic dependency updates

Test dependencies are automatically updated via Dependabot using a shared configuration across all test projects.

Each GitHub Action maintains its own Dependabot configuration, as some actions are not yet covered by automated tests.

## Unit tests

- They are always run.
- The target coverage is 100%.
- With modern tooling, generating comprehensive tests is both feasible and encouraged.
- They can be run locally using:

```bash
python -m pytest
```

## Integration tests

- They are run when the `test/python-integration` label is added to the PR.
- They should cover all the positive use cases.
- They are meant to verify the action does what it is supposed to do on a remote system
- Test resources should be dedicated to each action. Please do not reuse resources across actions. For instance, if a JIRA ticket is created manually because an action is meant to update it then the ticket should only be used by the action tests, not from another one.
- If resources are created dynamically, please try to randomize their naming to avoid conflict.
- Integration test files should include `integration` marker at the top of the file like:

```python
import pytest

pytestmark = pytest.mark.integration
```

- They can be run locally using (without pollution):

```bash
python -m pytest -m "integration and not integration_pollution"
```

- Or with pollution:

```bash
python -m pytest -m integration
```

### Integration tests with potential pollution

- They are run when the `test/python-integration/pollution` label is added to the PR.
- They are part of integration tests and won't be triggered unless the PR has both `test/python-integration label` and `test/python-integration/pollution`.
- Pollution tests are tests creating resources that cannot be deleted. For instance:
  - creating a JIRA ticket is pollution because it can be closed but not deleted. Only admins can do that.
  - creating a JIRA version/release is not pollution because it can be deleted afterwards.
- Pollution tests can be flagged using the Python marker `integration_pollution`:

```python
@pytest.mark.integration_pollution
def test_integration_pollution():
    print("Hello from integration pollution!")
```

- They can be run locally using:

```bash
python -m pytest -m integration_pollution
```

### Running all the tests

```bash
python -m pytest -m "integration or not integration"
```

## Common fixtures

Common fixtures are available in [shared/fixtures](shared/fixtures.py). They are meant to be imported into the conftest.py file of each action where you can of course add specific action fixtures:

- `action_script_path` resolves the path of the action.py of the action based on what is in the pyproject.toml file of the action.
- `action_module` gives direct access to the action code. For instance the following accesses directly the method `get_required_env` in the action.py file.

```python
def test_get_required_env_use_case(action_module):
    action_module.get_required_env("BLAH")
```

***Please avoid redefining fixtures that already exist in `shared/fixtures.py` unless strictly necessary.***

## Setting up an action and tests

### Action side

**actions reside in `.github/actions`**

```bash
jira-get-or-create-release/
├── action.py
├── action.yml
└── requirements.txt
```

***Dependencies must be pinned (exact versions) to ensure deterministic behavior.***

### Tests side

**Python tests reside in `.github/tests/python-scripts`**

```bash
jira-get-or-create-release/
├── conftest.py
├── dev-requirements.txt
├── integration
│   └── test_action.py
├── pyproject.toml
└── unit
    └── test_action.py
```

***Each action must have its own isolated test folder.***

### Project file

- The project file is mandatory and specific to each action tests
- It can be copy/pasted as-is, only updating the `pythonpath` to point to the appropriate action source folder.
- Update the `--cov=` target to match the action module name.
- Here is an example file:

```properties
[tool.pytest.ini_options]
testpaths = ["unit", "integration"]
python_files = ["test_*.py"]
pythonpath = ["..", "../../../actions/jira-get-or-create-release"]
markers = [
  "integration: integration tests (require external systems, may be slower)",
  "integration_pollution: integration tests with irreversible side effects (e.g. creating Jira tickets that cannot be deleted)",
]
addopts = '''
    -vvv
    -ra
    --tb=long
    --showlocals
    --strict-markers
    --import-mode=importlib
    --color=yes
    --random-order
    -o junit_family=xunit2
    -o junit_logging=all
    --junit-xml=report.xml
    --cov=jira_get_or_create_release
    --cov-report=term-missing
    --cov-report=xml
    -m "not integration and not integration_pollution"
'''
```

### Development dependencies

- `dev-requirements.txt` is the file for development dependencies.
- Please do not put formatting/linting dependencies, those should be added to the [pre-commit configuration](../../../.pre-commit-config.yaml) and its configuration to the [root pyproject.toml file](../../../pyproject.toml).

**⚠️ IMPORTANT:** Dependencies must be pinned to avoid unexpected test behavior changes.

### Minimal content of conftest.py

```Python
from shared.fixtures import *  # noqa: F401,F403
```

Developers are welcome to enrich the shared fixtures file when they see that a test behavior is reusable across actions.
The same goes for helper fixtures.

### Unit test file

There are no restriction for unit tests, it is recommended to use mocking libraries like:

- responses for HTTP calls
- moto for AWS API calls
- any other test library you might find useful to mock external system/API

These ensure better coverage and allow catching more issues when upgrading Python packages or Python version.

### Integration test file

Please find below an example integration tests file including a pollution test.

```Python
import pytest

pytestmark = pytest.mark.integration  # this is mandatory to control the test suite execution


@pytest.mark.integration_pollution
def test_integration_pollution():
    print("Hello from integration pollution!")


def test_integration():
    print("Hello from integration!")
```

If there are no integration tests then the integration folder does not even have to be created.
