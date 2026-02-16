import importlib.util
import json
from pathlib import Path

import pytest
import responses


BASE_URL = "https://example.atlassian.net"
PROJECT_KEY = "OPSEXP"
VERSIONS_URL = f"{BASE_URL}/rest/api/2/project/{PROJECT_KEY}/versions"
PROJECT_ID = "12345"
PROJECT_URL = f"{BASE_URL}/rest/api/2/project/{PROJECT_KEY}"
CREATE_VERSION_URL = f"{BASE_URL}/rest/api/2/version"
VERSION_ID = "10078"
VERSION_DESCRIPTION = "Major release with breaking changes"
UPDATE_VERSION_URL = f"{BASE_URL}/rest/api/2/version/{VERSION_ID}"


@pytest.fixture
def action_module():
  def find_github_root(start: Path) -> Path:
    p = start.resolve()
    for parent in [p] + list(p.parents):
      if parent.name == ".github":
        return parent
    raise RuntimeError(f"Could not find .github root from {start}")

  github_root = find_github_root(Path(__file__))
  action_path = github_root / "actions" / "jira-get-or-create-release" / "action.py"

  if not action_path.exists():
    raise FileNotFoundError(f"action.py not found at: {action_path}")

  spec = importlib.util.spec_from_file_location("jira_get_or_create_release", action_path)
  module = importlib.util.module_from_spec(spec)
  assert spec.loader is not None
  spec.loader.exec_module(module)

  return module


@pytest.fixture
def jira():
  atlassian = pytest.importorskip("atlassian")
  return atlassian.Jira(
    url=BASE_URL,
    username="user",
    password="token",
    cloud=True,
  )


def test_get_required_env_returns_value(monkeypatch, action_module):
  monkeypatch.setenv("MY_VAR", "hello")

  assert action_module.get_required_env("MY_VAR") == "hello"


def test_get_required_env_allows_whitespace_around_value(monkeypatch, action_module):
  monkeypatch.setenv("MY_VAR", "  hello  ")

  assert action_module.get_required_env("MY_VAR") == "  hello  "


@pytest.mark.parametrize("value", [None, "", "   ", "\n\t"])
def test_get_required_env_exits_on_missing_or_blank(monkeypatch, capsys, value, action_module):
  var = "MISSING_VAR"
  if value is None:
    monkeypatch.delenv(var, raising=False)
  else:
    monkeypatch.setenv(var, value)

  with pytest.raises(SystemExit) as exc:
    action_module.get_required_env(var)

  assert exc.value.code == 1
  captured = capsys.readouterr()
  assert "Missing required environment variable" in captured.err
  assert var in captured.err


@responses.activate
def test_get_version_returns_matching_version(jira, action_module):
  wanted = "FF Test"
  responses.add(
    responses.GET,
    VERSIONS_URL,
    json=[
      {"id": "10001", "name": "1.0.0"},
      {"id": "10002", "name": wanted},
      {"id": "10003", "name": "2.0.0"},
    ],
    status=200,
  )

  v = action_module.get_version(jira, PROJECT_KEY, wanted)

  assert v is not None
  assert v["id"] == "10002"
  assert v["name"] == wanted
  assert len(responses.calls) == 1
  assert responses.calls[0].request.method == "GET"
  assert responses.calls[0].request.url == VERSIONS_URL


@responses.activate
def test_get_version_returns_none_when_not_found(jira, action_module):
  responses.add(
    responses.GET,
    VERSIONS_URL,
    json=[
      {"id": "10001", "name": "1.0.0"},
      {"id": "10003", "name": "2.0.0"},
    ],
    status=200,
  )

  assert action_module.get_version(jira, PROJECT_KEY, "FF Test") is None

  assert len(responses.calls) == 1
  assert responses.calls[0].request.url == VERSIONS_URL


@responses.activate
def test_get_version_strips_name_from_api_payload(jira, action_module):
  responses.add(
    responses.GET,
    VERSIONS_URL,
    json=[
      {"id": "10002", "name": "  FF Test  "},
    ],
    status=200,
  )

  v = action_module.get_version(jira, PROJECT_KEY, "FF Test")

  assert v is not None
  assert v["id"] == "10002"
  assert len(responses.calls) == 1
  assert responses.calls[0].request.url == VERSIONS_URL


def test_get_version_does_not_strip_version_name_argument(action_module):
  class FakeJira:
    @staticmethod
    def get_project_versions(_project_key):
      return [{"id": "10002", "name": "FF Test"}]

  assert action_module.get_version(FakeJira(), PROJECT_KEY, "  FF Test  ") is None


def test_get_version_propagates_exception_from_jira_client(action_module):
  class Boom(Exception):
    pass

  class FakeJira:
    @staticmethod
    def get_project_versions(_project_key):
      raise Boom("jira versions endpoint failed")

  with pytest.raises(Boom, match="jira versions endpoint failed"):
    action_module.get_version(FakeJira(), "OPSEXP", "1.0.0")


def test_get_project_id_returns_stripped_string_id(action_module):
  class FakeJira:
    @staticmethod
    def get_project(_project_key):
      return {"id": f"  {PROJECT_ID}  "}

  assert action_module.get_project_id(FakeJira(), PROJECT_KEY) == PROJECT_ID


def test_get_project_id_converts_int_id_to_string(action_module):
  class FakeJira:
    @staticmethod
    def get_project(_project_key):
      return {"id": int(PROJECT_ID)}

  assert action_module.get_project_id(FakeJira(), PROJECT_KEY) == PROJECT_ID


def test_get_project_id_raises_keyerror_when_id_missing(action_module):
  class FakeJira:
    @staticmethod
    def get_project(_project_key):
      return {"key": PROJECT_KEY}

  with pytest.raises(KeyError):
    action_module.get_project_id(FakeJira(), PROJECT_KEY)


def test_get_project_id_propagates_exception_from_jira_client(action_module):
  class Boom(Exception):
    pass

  class FakeJira:
    @staticmethod
    def get_project(_project_key):
      raise Boom("jira is down")

  with pytest.raises(Boom, match="jira is down"):
    action_module.get_project_id(FakeJira(), PROJECT_KEY)


@responses.activate
def test_create_version_without_description_does_not_send_description(jira, action_module):
  # Arrange
  responses.add(
    responses.GET,
    PROJECT_URL,
    json={"id": PROJECT_ID},
    status=200,
  )

  responses.add(
    responses.POST,
    CREATE_VERSION_URL,
    json={"id": "10077", "name": "1.2.3"},
    status=201,
  )

  # Act
  created = action_module.create_version(jira, PROJECT_KEY, "1.2.3", description=None)

  # Assert
  assert created["id"] == "10077"
  assert created["name"] == "1.2.3"
  assert len(responses.calls) == 2

  body = responses.calls[1].request.body
  if isinstance(body, bytes):
    body = body.decode("utf-8")
  payload = json.loads(body)

  assert payload["name"] == "1.2.3"
  assert str(payload["projectId"]) == PROJECT_ID
  assert payload["released"] is False
  assert payload["archived"] is False
  assert "description" not in payload


@responses.activate
def test_create_version_with_description_updates_version_after_create(jira, action_module):
  responses.add(
    responses.GET,
    PROJECT_URL,
    json={"id": PROJECT_ID},
    status=200,
  )
  responses.add(
    responses.POST,
    CREATE_VERSION_URL,
    json={"id": VERSION_ID, "name": "2.0.0"},
    status=201,
  )
  responses.add(
    responses.PUT,
    UPDATE_VERSION_URL,
    json={"id": VERSION_ID, "name": "2.0.0", "description": VERSION_DESCRIPTION},
    status=200,
  )

  created = action_module.create_version(
    jira,
    PROJECT_KEY,
    "2.0.0",
    description=VERSION_DESCRIPTION,
  )

  # Assert function result includes description (merged from update response)
  assert created["id"] == VERSION_ID
  assert created["name"] == "2.0.0"
  assert created["description"] == VERSION_DESCRIPTION

  # Assert HTTP calls: GET project, POST create, PUT update
  assert len(responses.calls) == 3
  assert responses.calls[0].request.method == "GET"
  assert responses.calls[0].request.url == PROJECT_URL
  assert responses.calls[1].request.method == "POST"
  assert responses.calls[1].request.url == CREATE_VERSION_URL

  # POST payload must NOT include description
  body = responses.calls[1].request.body
  if isinstance(body, bytes):
    body = body.decode("utf-8")
  payload = json.loads(body)
  assert payload["name"] == "2.0.0"
  assert str(payload["projectId"]) == PROJECT_ID
  assert payload["released"] is False
  assert payload["archived"] is False
  assert "description" not in payload
  assert responses.calls[2].request.method == "PUT"
  assert responses.calls[2].request.url == UPDATE_VERSION_URL

  # PUT payload must include description
  body = responses.calls[2].request.body
  if isinstance(body, bytes):
    body = body.decode("utf-8")
  payload = json.loads(body)
  assert payload["description"] == VERSION_DESCRIPTION
