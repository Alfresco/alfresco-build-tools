import os
from pathlib import Path
from typing import Any

import pytest

pytestmark = pytest.mark.integration

# -----------------------------
# Global reusable constants
# -----------------------------
ENV_JIRA_URL = "JIRA_URL"
ENV_JIRA_USER = "JIRA_USER"
ENV_JIRA_TOKEN = "JIRA_TOKEN"

ENV_JIRA_ISSUE_KEY = "JIRA_ISSUE_KEY"
ENV_JIRA_VERSION_ID = "JIRA_VERSION_ID"
ENV_JIRA_VERSION_NAME = "JIRA_VERSION_NAME"
ENV_MERGE_VERSIONS = "MERGE_VERSIONS"
ENV_GITHUB_OUTPUT = "GITHUB_OUTPUT"

OUTPUT_CHANGED = "changed"
OUTPUT_FIX_VERSIONS = "fix-versions"

INTEGRATION_ISSUE_KEY = "OPSEXP-3863"


# -----------------------------
# Helpers
# -----------------------------
def _require_env_or_skip(var_name: str) -> str:
    v = os.getenv(var_name)
    if v is None or v.strip() == "":
        pytest.skip(f"Integration test requires env var {var_name}.")
    return v.strip()


def _read_github_output(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        out[k.strip()] = v.strip()
    return out


def _normalize_versions(versions: list[dict[str, Any]]) -> list[dict[str, str]]:
    # compare only the minimal stable keys
    out: list[dict[str, str]] = []
    for v in versions:
        out.append(
            {
                "id": str(v.get("id", "")).strip(),
                "name": str(v.get("name", "")).strip(),
            }
        )
    return out


def _filter_versions_with_id(versions: list[dict[str, Any]]) -> list[dict[str, Any]]:
    # Keep only versions that can be used for update (must have an id)
    filtered: list[dict[str, Any]] = []
    for v in versions or []:
        vid = str(v.get("id", "")).strip()
        if not vid:
            continue
        filtered.append(v)
    return filtered


def _pick_two_distinct_versions_or_skip(versions: list[dict[str, Any]]) -> tuple[dict[str, Any], dict[str, Any]]:
    versions = _filter_versions_with_id(versions)
    if len(versions) < 2:
        pytest.skip("Need at least 2 project versions with ids to run integration tests deterministically.")
    return versions[0], versions[1]


def _set_env_for_main(monkeypatch, *, jira_url: str, jira_user: str, jira_token: str, issue_key: str) -> None:
    monkeypatch.setenv(ENV_JIRA_URL, jira_url)
    monkeypatch.setenv(ENV_JIRA_USER, jira_user)
    monkeypatch.setenv(ENV_JIRA_TOKEN, jira_token)
    monkeypatch.setenv(ENV_JIRA_ISSUE_KEY, issue_key)


# -----------------------------
# Fixtures
# -----------------------------
@pytest.fixture(scope="session")
def jira_creds() -> tuple[str, str, str]:
    jira_url = _require_env_or_skip(ENV_JIRA_URL)
    jira_user = _require_env_or_skip(ENV_JIRA_USER)
    jira_token = _require_env_or_skip(ENV_JIRA_TOKEN)
    return jira_url, jira_user, jira_token


@pytest.fixture
def jira_client(action_module, jira_creds):
    jira_url, jira_user, jira_token = jira_creds
    return action_module.Jira(url=jira_url, username=jira_user, password=jira_token, cloud=True)


@pytest.fixture
def issue_key() -> str:
    return INTEGRATION_ISSUE_KEY


@pytest.fixture
def project_key(action_module, issue_key: str) -> str:
    return action_module.project_key_from_issue_key(issue_key)


@pytest.fixture
def project_versions(jira_client, project_key: str) -> list[dict[str, Any]]:
    versions = jira_client.get_project_versions(project_key) or []
    versions = _filter_versions_with_id(versions)
    if not versions:
        pytest.skip(f"No usable versions (with id) in Jira project '{project_key}'.")
    return versions


@pytest.fixture
def snapshot_restore_fix_versions(action_module, jira_client, issue_key: str):
    # snapshot
    before = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))

    yield before

    # restore (best-effort but expected to succeed)
    action_module.update_issue_fix_versions(jira_client, issue_key, before)


# -----------------------------
# Integration tests
# -----------------------------
def test_integration_merge_true_adds_missing_version_from_known_initial_state(
    action_module,
    monkeypatch,
    tmp_path,
    jira_creds,
    jira_client,
    issue_key,
    project_versions,
    snapshot_restore_fix_versions,
):
    jira_url, jira_user, jira_token = jira_creds
    v1, v2 = _pick_two_distinct_versions_or_skip(project_versions)

    out_file = tmp_path / "gh_out.txt"

    # Given: controlled initial state = [v1]
    initial = [v1]
    action_module.update_issue_fix_versions(jira_client, issue_key, initial)

    current = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert action_module.versions_equal(current, initial)

    _set_env_for_main(monkeypatch, jira_url=jira_url, jira_user=jira_user, jira_token=jira_token, issue_key=issue_key)
    monkeypatch.setenv(ENV_JIRA_VERSION_ID, str(v2["id"]).strip())
    monkeypatch.delenv(ENV_JIRA_VERSION_NAME, raising=False)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "true")
    monkeypatch.setenv(ENV_GITHUB_OUTPUT, str(out_file))

    # When
    action_module.main()

    # Then: v2 is added alongside v1
    after = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    after_norm = _normalize_versions(after)

    expected = action_module.unique_versions_by_id_or_name([v1, v2])
    expected_norm = _normalize_versions(expected)

    assert action_module.versions_equal(after, expected)
    assert sorted(after_norm, key=lambda x: x["id"]) == sorted(expected_norm, key=lambda x: x["id"])

    out = _read_github_output(out_file)
    assert out.get(OUTPUT_CHANGED) == "true"
    assert OUTPUT_FIX_VERSIONS in out


def test_integration_merge_false_replaces_versions_from_known_initial_state(
    action_module,
    monkeypatch,
    tmp_path,
    jira_creds,
    jira_client,
    issue_key,
    project_versions,
    snapshot_restore_fix_versions,
):
    jira_url, jira_user, jira_token = jira_creds
    v1, v2 = _pick_two_distinct_versions_or_skip(project_versions)

    out_file = tmp_path / "gh_out.txt"

    # Given: controlled initial state = [v1, v2]
    initial = [v1, v2]
    action_module.update_issue_fix_versions(jira_client, issue_key, initial)

    current = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert action_module.versions_equal(current, initial)

    _set_env_for_main(monkeypatch, jira_url=jira_url, jira_user=jira_user, jira_token=jira_token, issue_key=issue_key)
    monkeypatch.setenv(ENV_JIRA_VERSION_ID, str(v1["id"]).strip())
    monkeypatch.delenv(ENV_JIRA_VERSION_NAME, raising=False)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "false")
    monkeypatch.setenv(ENV_GITHUB_OUTPUT, str(out_file))

    # When
    action_module.main()

    # Then: replaced with only [v1]
    after = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    expected = action_module.unique_versions_by_id_or_name([v1])

    assert action_module.versions_equal(after, expected)

    out = _read_github_output(out_file)
    # could be false only if the initial state already exactly matched [v1], but we set [v1, v2], so it should be true
    assert out.get(OUTPUT_CHANGED) == "true"
    assert OUTPUT_FIX_VERSIONS in out


def test_integration_merge_true_no_change_when_version_already_present_from_known_initial_state(
    action_module,
    monkeypatch,
    tmp_path,
    jira_creds,
    jira_client,
    issue_key,
    project_versions,
    snapshot_restore_fix_versions,
):
    jira_url, jira_user, jira_token = jira_creds
    v1, _v2 = _pick_two_distinct_versions_or_skip(project_versions)

    out_file = tmp_path / "gh_out.txt"

    # Given: controlled initial state = [v1]
    initial = [v1]
    action_module.update_issue_fix_versions(jira_client, issue_key, initial)

    current = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert action_module.versions_equal(current, initial)

    _set_env_for_main(monkeypatch, jira_url=jira_url, jira_user=jira_user, jira_token=jira_token, issue_key=issue_key)
    monkeypatch.setenv(ENV_JIRA_VERSION_ID, str(v1["id"]).strip())
    monkeypatch.delenv(ENV_JIRA_VERSION_NAME, raising=False)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "true")
    monkeypatch.setenv(ENV_GITHUB_OUTPUT, str(out_file))

    # When
    action_module.main()

    # Then: unchanged
    after = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert action_module.versions_equal(after, initial)

    out = _read_github_output(out_file)
    assert out.get(OUTPUT_CHANGED) == "false"
    assert OUTPUT_FIX_VERSIONS in out


def test_integration_merge_true_from_empty_initial_state_adds_version(
    action_module,
    monkeypatch,
    tmp_path,
    jira_creds,
    jira_client,
    issue_key,
    project_versions,
    snapshot_restore_fix_versions,
):
    jira_url, jira_user, jira_token = jira_creds
    v1 = next((v for v in project_versions if str(v.get("id", "")).strip()), None)
    if v1 is None:
        pytest.skip("No project version with a usable id.")

    out_file = tmp_path / "gh_out.txt"

    # Given: controlled initial state = []
    action_module.update_issue_fix_versions(jira_client, issue_key, [])

    current = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert current == []

    monkeypatch.setenv("JIRA_URL", jira_url)
    monkeypatch.setenv("JIRA_USER", jira_user)
    monkeypatch.setenv("JIRA_TOKEN", jira_token)
    monkeypatch.setenv("JIRA_ISSUE_KEY", issue_key)

    monkeypatch.setenv("JIRA_VERSION_ID", str(v1["id"]).strip())
    monkeypatch.delenv("JIRA_VERSION_NAME", raising=False)
    monkeypatch.setenv("MERGE_VERSIONS", "true")
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))

    # When
    action_module.main()

    # Then: now has [v1]
    after = action_module.unique_versions_by_id_or_name(action_module.get_issue_fix_versions(jira_client, issue_key))
    assert action_module.versions_equal(after, [v1])

    out = _read_github_output(out_file)
    assert out.get(OUTPUT_CHANGED) == "true"
    assert OUTPUT_FIX_VERSIONS in out
