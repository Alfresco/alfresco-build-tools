import json
from typing import Any
from urllib.parse import urlencode

import pytest
import responses

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

JIRA_URL = "https://example.atlassian.net"
JIRA_USER = "user@example.com"
JIRA_TOKEN = "token123"

ISSUE_KEY = "PROJ-123"
PROJECT_KEY = "PROJ"

VERSION_ID_1 = "10001"
VERSION_ID_2 = "10002"
VERSION_NAME_1 = "1.0.0"
VERSION_NAME_2 = "2.0.0"

VERSION_OBJ_1 = {"id": VERSION_ID_1, "name": VERSION_NAME_1}
VERSION_OBJ_2 = {"id": VERSION_ID_2, "name": VERSION_NAME_2}

# atlassian-python-api: get_project_versions() => /rest/api/2/project/{key}/versions
PROJECT_VERSIONS_URL = f"{JIRA_URL}/rest/api/2/project/{PROJECT_KEY}/versions"
ISSUE_URL = f"{JIRA_URL}/rest/api/3/issue/{ISSUE_KEY}"
ISSUE_FIXVERSIONS_URL = f"{ISSUE_URL}?{urlencode({'fields': 'fixVersions'})}"

OUTPUT_CHANGED = "changed"
OUTPUT_FIXVERSIONS = "fix-versions"


# -----------------------------
# Helpers
# -----------------------------
def _set_minimal_required_env(monkeypatch, *, version_id: str | None, version_name: str | None) -> None:
    monkeypatch.setenv(ENV_JIRA_URL, JIRA_URL)
    monkeypatch.setenv(ENV_JIRA_USER, JIRA_USER)
    monkeypatch.setenv(ENV_JIRA_TOKEN, JIRA_TOKEN)
    monkeypatch.setenv(ENV_JIRA_ISSUE_KEY, ISSUE_KEY)

    if version_id is None:
        monkeypatch.delenv(ENV_JIRA_VERSION_ID, raising=False)
    else:
        monkeypatch.setenv(ENV_JIRA_VERSION_ID, version_id)

    if version_name is None:
        monkeypatch.delenv(ENV_JIRA_VERSION_NAME, raising=False)
    else:
        monkeypatch.setenv(ENV_JIRA_VERSION_NAME, version_name)


def _register_project_versions(versions: list[dict[str, Any]]) -> None:
    responses.add(
        method=responses.GET,
        url=PROJECT_VERSIONS_URL,
        json=versions,
        status=200,
        content_type="application/json",
    )


def _register_issue_fix_versions(versions: list[dict[str, Any]]) -> None:
    responses.add(
        method=responses.GET,
        url=ISSUE_FIXVERSIONS_URL,
        json={"fields": {"fixVersions": versions}},
        status=200,
        content_type="application/json",
    )


def _register_issue_put(status: int = 204) -> None:
    # atlassian-python-api usually sends JSON; 204 is common for update.
    responses.add(
        method=responses.PUT,
        url=ISSUE_URL,
        status=status,
        content_type="application/json",
    )


def _last_request_json() -> dict[str, Any]:
    assert responses.calls, "Expected at least one HTTP call to be made."
    body = responses.calls[-1].request.body
    if body in (None, b"", ""):
        return {}
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    return json.loads(body)


def _request_json(call: responses.Call) -> dict:
    body = call.request.body
    if body is None or body == b"" or body == "":
        return {}
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    return json.loads(body)


# -----------------------------
# non-HTTP unit tests
# -----------------------------
def test_get_required_env_exits_when_missing(action_module, monkeypatch, capsys):
    monkeypatch.delenv(ENV_JIRA_URL, raising=False)

    with pytest.raises(SystemExit) as e:
        action_module.get_required_env(ENV_JIRA_URL)

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert f"Missing required environment variable: {ENV_JIRA_URL}" in err


@pytest.mark.parametrize("raw", ["", "  ", "yes", "0", "truth", "TRUEE"])
def test_parse_bool_exits_on_invalid(action_module, capsys, raw):
    with pytest.raises(SystemExit) as e:
        action_module.parse_bool(raw)

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Boolean value must be 'true' or 'false'" in err


@pytest.mark.parametrize("issue_key", ["PROJ123", "NO_DASH", ""])
def test_project_key_from_issue_key_exits_on_invalid(action_module, capsys, issue_key):
    with pytest.raises(SystemExit) as e:
        action_module.project_key_from_issue_key(issue_key)

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Invalid JIRA issue key format" in err


def test_resolve_version_by_name_found(action_module, monkeypatch):
    class JiraStub:
        @staticmethod
        def get_project_versions(_project_key: str):
            return [{"id": "1", "name": "A"}, {"id": "2", "name": "B"}]

    jira = JiraStub()

    result = action_module.resolve_version(jira, "PROJ", version_id=None, version_name="B")

    assert result == {"id": "2", "name": "B"}


def test_resolve_version_by_name_not_found(action_module):
    class JiraStub:
        @staticmethod
        def get_project_versions(_project_key: str):
            return [{"id": "1", "name": "A"}]

    jira = JiraStub()

    result = action_module.resolve_version(jira, "PROJ", version_id=None, version_name="B")

    assert result is None


def test_unique_versions_by_id_or_name_hits_continue_branches(action_module):
    versions = [
        {"id": "1", "name": "A"},
        {"id": "1", "name": "A-dup"},  # dup id -> continue (line 106)
        {"name": "B"},
        {"name": "B"},  # dup name without id -> continue (lines 109-110)
        {"id": "2", "name": "B"},  # different id, same name => kept (id wins uniqueness)
    ]

    result = action_module.unique_versions_by_id_or_name(versions)

    assert result == [
        {"id": "1", "name": "A"},
        {"name": "B"},
        {"id": "2", "name": "B"},
    ]


# -----------------------------
# HTTP-level unit tests
# -----------------------------
@responses.activate
def test_get_issue_fix_versions_hits_expected_endpoint(action_module):
    _register_issue_fix_versions([VERSION_OBJ_1])

    result = action_module.get_issue_fix_versions(
        action_module.Jira(url=JIRA_URL, username=JIRA_USER, password=JIRA_TOKEN, cloud=True), ISSUE_KEY
    )

    assert result == [VERSION_OBJ_1]
    assert len(responses.calls) == 1
    assert responses.calls[0].request.method == "GET"
    assert responses.calls[0].request.url == ISSUE_FIXVERSIONS_URL


@responses.activate
def test_update_issue_fix_versions_sends_expected_payload(action_module):
    _register_issue_put(status=204)

    jira = action_module.Jira(url=JIRA_URL, username=JIRA_USER, password=JIRA_TOKEN, cloud=True)

    action_module.update_issue_fix_versions(jira, ISSUE_KEY, [VERSION_OBJ_1, {"id": " 10002 ", "name": "x"}])

    assert len(responses.calls) == 1
    req = responses.calls[0].request
    assert req.method == "PUT"
    assert req.url == ISSUE_URL

    payload = _last_request_json()
    assert payload == {"fields": {"fixVersions": [{"id": "10001"}, {"id": "10002"}]}}


@responses.activate
def test_update_issue_fix_versions_exits_if_missing_id(action_module, capsys):
    jira = action_module.Jira(url=JIRA_URL, username=JIRA_USER, password=JIRA_TOKEN, cloud=True)

    with pytest.raises(SystemExit) as e:
        action_module.update_issue_fix_versions(jira, ISSUE_KEY, [{"name": "no-id"}])

    captured = capsys.readouterr()
    assert e.value.code == 1
    assert "Cannot update fixVersions" in captured.err
    assert len(responses.calls) == 0


def test_main_exits_when_both_version_id_and_name(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id="10001", version_name="1.0.0")

    with pytest.raises(SystemExit) as e:
        action_module.main()

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Provide either JIRA_VERSION_ID or JIRA_VERSION_NAME, not both" in err


# -----------------------------
# main() flow
# -----------------------------
def test_main_exits_when_neither_version_id_nor_name(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id=None, version_name=None)

    with pytest.raises(SystemExit) as e:
        action_module.main()

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Either JIRA_VERSION_ID or JIRA_VERSION_NAME must be provided" in err


def test_main_handles_unexpected_exception(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id="10001", version_name=None)

    def boom(*_args, **_kwargs):
        raise RuntimeError("boom")

    monkeypatch.setattr(action_module, "resolve_version", boom)

    with pytest.raises(SystemExit) as e:
        action_module.main()

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Unexpected error occurred" in err
    assert "boom" in err


# -----------------------------
# main() flow with responses
# -----------------------------
@responses.activate
def test_main_updates_issue_when_merge_true_and_version_missing(action_module, monkeypatch, tmp_path, capsys):
    _set_minimal_required_env(monkeypatch, version_id=VERSION_ID_2, version_name=None)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "true")

    out_file = tmp_path / "gh_out.txt"
    monkeypatch.setenv(ENV_GITHUB_OUTPUT, str(out_file))

    _register_project_versions([VERSION_OBJ_1, VERSION_OBJ_2])
    _register_issue_fix_versions([VERSION_OBJ_1])
    _register_issue_put(status=204)

    action_module.main()

    # Calls: project versions GET, issue GET, issue PUT
    assert [c.request.method for c in responses.calls] == ["GET", "GET", "PUT"]

    put_payload = _request_json(responses.calls[2])
    assert put_payload == {"fields": {"fixVersions": [{"id": VERSION_ID_1}, {"id": VERSION_ID_2}]}}

    captured = capsys.readouterr()
    assert "✅ Updated fixVersions" in captured.out

    outputs = out_file.read_text(encoding="utf-8").splitlines()
    assert f"{OUTPUT_CHANGED}=true" in outputs
    assert any(line.startswith(f"{OUTPUT_FIXVERSIONS}=") for line in outputs)


@responses.activate
def test_main_no_update_when_merge_true_and_version_already_present(action_module, monkeypatch, tmp_path, capsys):
    _set_minimal_required_env(monkeypatch, version_id=VERSION_ID_1, version_name=None)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "true")

    out_file = tmp_path / "gh_out.txt"
    monkeypatch.setenv(ENV_GITHUB_OUTPUT, str(out_file))

    _register_project_versions([VERSION_OBJ_1])
    _register_issue_fix_versions([VERSION_OBJ_1])

    # No PUT should happen
    action_module.main()

    assert [c.request.method for c in responses.calls] == ["GET", "GET"]

    captured = capsys.readouterr()
    assert "ℹ️ No change needed" in captured.out

    outputs = out_file.read_text(encoding="utf-8").splitlines()
    assert f"{OUTPUT_CHANGED}=false" in outputs
    assert any(line.startswith(f"{OUTPUT_FIXVERSIONS}=") for line in outputs)


@responses.activate
def test_main_replaces_versions_when_merge_false(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id=VERSION_ID_2, version_name=None)
    monkeypatch.setenv(ENV_MERGE_VERSIONS, "false")

    _register_project_versions([VERSION_OBJ_1, VERSION_OBJ_2])
    _register_issue_fix_versions([VERSION_OBJ_1])
    _register_issue_put(status=204)

    action_module.main()

    assert [c.request.method for c in responses.calls] == ["GET", "GET", "PUT"]

    put_payload = _request_json(responses.calls[2])
    assert put_payload == {"fields": {"fixVersions": [{"id": VERSION_ID_2}]}}

    captured = capsys.readouterr()
    assert "✅ Updated fixVersions" in captured.out


@responses.activate
def test_main_exits_when_version_does_not_exist_by_id(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id="99999", version_name=None)

    _register_project_versions([VERSION_OBJ_1])  # doesn't include 99999

    with pytest.raises(SystemExit) as e:
        action_module.main()

    captured = capsys.readouterr()
    assert e.value.code == 1
    assert "Fix version id '99999' does not exist in project" in captured.err

    # Only the project versions GET should happen
    assert [c.request.method for c in responses.calls] == ["GET"]


@responses.activate
def test_main_handles_http_error_from_jira(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id=VERSION_ID_1, version_name=None)

    # Force an HTTP error during project versions fetch
    responses.add(method=responses.GET, url=PROJECT_VERSIONS_URL, status=500)

    with pytest.raises(SystemExit) as e:
        action_module.main()

    captured = capsys.readouterr()
    assert e.value.code == 1
    assert "HTTP error occurred while calling Jira" in captured.err


@responses.activate
def test_main_exits_when_version_does_not_exist_by_name(action_module, monkeypatch, capsys):
    _set_minimal_required_env(monkeypatch, version_id=None, version_name="does-not-exist")

    responses.add(
        responses.GET,
        PROJECT_VERSIONS_URL,
        json=[{"id": "1", "name": "1.0.0"}],
        status=200,
    )

    with pytest.raises(SystemExit) as e:
        action_module.main()

    err = capsys.readouterr().err
    assert e.value.code == 1
    assert "Fix version 'does-not-exist' does not exist in project 'PROJ'" in err
