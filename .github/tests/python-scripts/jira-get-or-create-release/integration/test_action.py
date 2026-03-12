import os
import uuid

import pytest
import requests
from requests import HTTPError

pytestmark = pytest.mark.integration

# Project key is fixed for integration tests.
# Credentials (URL, user, token) are injected via CI environment.
JIRA_PROJECT_KEY = "OPSEXP"  # Adjust to your dedicated CI test project


def delete_version(jira_url: str, user: str, token: str, version_id: str) -> None:
    """Delete a Jira version (best-effort cleanup)."""
    url = jira_url.rstrip("/") + f"/rest/api/2/version/{version_id}"
    r = requests.delete(url, auth=(user, token), timeout=30)
    if r.status_code not in (204, 404):
        r.raise_for_status()


def get_version(jira_url: str, user: str, token: str, version_id: str) -> dict:
    """Fetch a Jira version as JSON."""
    url = jira_url.rstrip("/") + f"/rest/api/2/version/{version_id}"
    r = requests.get(url, auth=(user, token), timeout=30)
    r.raise_for_status()
    return r.json()


def run_action_main(
    action_module,
    *,
    jira_url: str,
    jira_user: str,
    jira_token: str,
    project_key: str,
    version_name: str,
    description: str | None,
    tmp_path,
    monkeypatch: pytest.MonkeyPatch,
) -> str:
    """
    Execute action.main() in-process and return the version_id written to GITHUB_OUTPUT.
    This yields readable Python tracebacks instead of cryptic subprocess failures.
    """
    out_file = tmp_path / "github_output.txt"
    monkeypatch.setenv("JIRA_URL", jira_url)
    monkeypatch.setenv("JIRA_USER", jira_user)
    monkeypatch.setenv("JIRA_TOKEN", jira_token)
    monkeypatch.setenv("JIRA_PROJECT_KEY", project_key)
    monkeypatch.setenv("JIRA_VERSION_NAME", version_name)
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    if description is not None:
        monkeypatch.setenv("JIRA_VERSION_DESCRIPTION", description)
    else:
        monkeypatch.delenv("JIRA_VERSION_DESCRIPTION", raising=False)

    action_module.main()

    content = out_file.read_text(encoding="utf-8") if out_file.exists() else ""
    for line in content.splitlines():
        if line.startswith("version_id="):
            version_id = line.split("=", 1)[1].strip()
            assert version_id, f"Empty version_id in GITHUB_OUTPUT:\n{content}"
            return version_id

    raise AssertionError(f"version_id not found in GITHUB_OUTPUT:\n{content}")


@pytest.fixture
def jira_env():
    """
    Retrieve Jira credentials from the CI environment.
    Tests are expected to fail if variables are missing.
    """
    return {
        "jira_url": os.environ["JIRA_URL"],
        "jira_user": os.environ["JIRA_USER"],
        "jira_token": os.environ["JIRA_TOKEN"],
    }


@pytest.fixture
def unique_version_name() -> str:
    """Generate a unique version name safe for parallel execution."""
    return f"Test-{uuid.uuid4().hex[:12]}"


@pytest.fixture
def created_version_ids(jira_env):
    """
    Track created versions and ensure cleanup after each test.
    Cleanup is best-effort to avoid masking test failures.
    """
    created: list[str] = []
    yield created
    for vid in created:
        try:
            delete_version(
                jira_env["jira_url"],
                jira_env["jira_user"],
                jira_env["jira_token"],
                vid,
            )
        except (KeyError, HTTPError):
            pass


def test_create_without_description(
    jira_env,
    unique_version_name,
    created_version_ids,
    tmp_path,
    action_module,
    monkeypatch,
):
    version_name = unique_version_name

    version_id = run_action_main(
        action_module,
        jira_url=jira_env["jira_url"],
        jira_user=jira_env["jira_user"],
        jira_token=jira_env["jira_token"],
        project_key=JIRA_PROJECT_KEY,
        version_name=version_name,
        description=None,
        tmp_path=tmp_path,
        monkeypatch=monkeypatch,
    )
    created_version_ids.append(version_id)

    version = get_version(
        jira_env["jira_url"],
        jira_env["jira_user"],
        jira_env["jira_token"],
        version_id,
    )
    assert version.get("id") == version_id
    assert (version.get("name") or "").strip() == version_name
    assert (version.get("description") or "").strip() == ""


def test_create_with_description(
    jira_env,
    unique_version_name,
    created_version_ids,
    tmp_path,
    action_module,
    monkeypatch,
):
    version_name = unique_version_name
    description = "created by integration test"

    version_id = run_action_main(
        action_module,
        jira_url=jira_env["jira_url"],
        jira_user=jira_env["jira_user"],
        jira_token=jira_env["jira_token"],
        project_key=JIRA_PROJECT_KEY,
        version_name=version_name,
        description=description,
        tmp_path=tmp_path,
        monkeypatch=monkeypatch,
    )
    created_version_ids.append(version_id)

    version = get_version(
        jira_env["jira_url"],
        jira_env["jira_user"],
        jira_env["jira_token"],
        version_id,
    )
    assert version.get("id") == version_id
    assert (version.get("name") or "").strip() == version_name
    assert (version.get("description") or "").strip() == description


def test_create_twice_returns_same_version_id(
    jira_env,
    unique_version_name,
    created_version_ids,
    tmp_path,
    action_module,
    monkeypatch,
):
    version_name = unique_version_name

    version_id_1 = run_action_main(
        action_module,
        jira_url=jira_env["jira_url"],
        jira_user=jira_env["jira_user"],
        jira_token=jira_env["jira_token"],
        project_key=JIRA_PROJECT_KEY,
        version_name=version_name,
        description=None,
        tmp_path=tmp_path,
        monkeypatch=monkeypatch,
    )
    version_id_2 = run_action_main(
        action_module,
        jira_url=jira_env["jira_url"],
        jira_user=jira_env["jira_user"],
        jira_token=jira_env["jira_token"],
        project_key=JIRA_PROJECT_KEY,
        version_name=version_name,
        description=None,
        tmp_path=tmp_path,
        monkeypatch=monkeypatch,
    )
    created_version_ids.append(version_id_1)

    assert version_id_2 == version_id_1

    version = get_version(
        jira_env["jira_url"],
        jira_env["jira_user"],
        jira_env["jira_token"],
        version_id_1,
    )
    assert (version.get("name") or "").strip() == version_name
