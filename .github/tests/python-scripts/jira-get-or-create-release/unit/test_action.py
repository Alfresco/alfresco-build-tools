import json

import pytest
import responses
from requests import HTTPError

BASE_URL = "https://example.atlassian.net"
PROJECT_KEY = "OPSEXP"
VERSIONS_URL = f"{BASE_URL}/rest/api/2/project/{PROJECT_KEY}/versions"
PROJECT_ID = "12345"
PROJECT_URL = f"{BASE_URL}/rest/api/2/project/{PROJECT_KEY}"
CREATE_VERSION_URL = f"{BASE_URL}/rest/api/2/version"
VERSION_ID = "10078"
VERSION_NAME = "3.0.0"
VERSION_DESCRIPTION = "Major release with breaking changes"
UPDATE_VERSION_URL = f"{BASE_URL}/rest/api/2/version/{VERSION_ID}"


@pytest.fixture
def jira():
    atlassian = pytest.importorskip("atlassian")
    return atlassian.Jira(
        url=BASE_URL,
        username="user",
        password="token",
        cloud=True,
    )


@pytest.fixture
def required_env(monkeypatch):
    def _apply(**overrides):
        env = {
            "JIRA_URL": BASE_URL,
            "JIRA_USER": "user",
            "JIRA_TOKEN": "token",
            "JIRA_PROJECT_KEY": "PRJ",
            "JIRA_VERSION_NAME": VERSION_NAME,
        }
        env.update(overrides)

        for k, v in env.items():
            monkeypatch.setenv(k, v)

    return _apply


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
    responses.add(responses.GET, PROJECT_URL, json={"id": PROJECT_ID}, status=200)
    responses.add(responses.POST, CREATE_VERSION_URL, json={"id": "10077", "name": VERSION_NAME}, status=201)

    created = action_module.create_version(jira, PROJECT_KEY, VERSION_NAME, description=None)

    assert created["id"] == "10077"
    assert created["name"] == VERSION_NAME
    assert len(responses.calls) == 2

    body = responses.calls[1].request.body
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    payload = json.loads(body)

    assert payload["name"] == VERSION_NAME
    assert str(payload["projectId"]) == PROJECT_ID
    assert payload["released"] is False
    assert payload["archived"] is False
    assert "description" not in payload


@responses.activate
def test_create_version_with_description_updates_version_after_create(jira, action_module):
    responses.add(responses.GET, PROJECT_URL, json={"id": PROJECT_ID}, status=200)
    responses.add(responses.POST, CREATE_VERSION_URL, json={"id": VERSION_ID, "name": VERSION_NAME}, status=201)
    responses.add(
        responses.PUT,
        UPDATE_VERSION_URL,
        json={"id": VERSION_ID, "name": VERSION_NAME, "description": VERSION_DESCRIPTION},
        status=200,
    )

    created = action_module.create_version(jira, PROJECT_KEY, VERSION_NAME, description=VERSION_DESCRIPTION)

    # Assert function result includes description (merged from update response)
    assert created["id"] == VERSION_ID
    assert created["name"] == VERSION_NAME
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
    assert payload["name"] == VERSION_NAME
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


@responses.activate
def test_ensure_version_returns_existing_without_creating(jira, action_module, capsys):
    responses.add(responses.GET, VERSIONS_URL, json=[{"id": VERSION_ID, "name": VERSION_NAME}], status=200)

    vid = action_module.ensure_version(jira, PROJECT_KEY, VERSION_NAME, description="ignored")
    assert vid == VERSION_ID
    assert len(responses.calls) == 1

    out = capsys.readouterr().out
    assert f"Version {VERSION_NAME} found with id {VERSION_ID}." in out


@pytest.mark.parametrize(
    "versions_list, description, expect_update",
    [
        # missing version; no description
        ([{"id": "10001", "name": "1.0.0"}], None, False),
        # missing version; description provided
        ([], VERSION_DESCRIPTION, True),
    ],
)
@responses.activate
def test_ensure_version_creates_when_missing_parametric(
    jira, capsys, action_module, versions_list, description, expect_update
):
    responses.add(responses.GET, VERSIONS_URL, json=versions_list, status=200)
    responses.add(responses.GET, PROJECT_URL, json={"id": "12345"}, status=200)
    responses.add(
        responses.POST,
        CREATE_VERSION_URL,
        json={"id": VERSION_ID, "name": VERSION_NAME},
        status=201,
    )
    if expect_update:
        responses.add(
            responses.PUT,
            UPDATE_VERSION_URL,
            json={"id": VERSION_ID, "name": VERSION_NAME, "description": VERSION_DESCRIPTION},
            status=200,
        )

    version_id = action_module.ensure_version(
        jira,
        PROJECT_KEY,
        VERSION_NAME,
        description=description,
    )

    assert version_id == VERSION_ID
    out = capsys.readouterr().out
    assert f"Version {VERSION_NAME} created successfully with id {VERSION_ID}." in out

    # HTTP calls: GET versions, GET project, POST create (+ optional PUT update)
    expected_calls = 4 if expect_update else 3
    assert len(responses.calls) == expected_calls
    assert responses.calls[0].request.method == "GET"
    assert responses.calls[0].request.url == VERSIONS_URL
    assert responses.calls[1].request.method == "GET"
    assert responses.calls[1].request.url == PROJECT_URL
    assert responses.calls[2].request.method == "POST"
    assert responses.calls[2].request.url == CREATE_VERSION_URL

    # Validate POST payload (never includes description)
    body = responses.calls[2].request.body
    if isinstance(body, bytes):
        body = body.decode("utf-8")
    payload = json.loads(body)

    assert payload["name"] == VERSION_NAME
    assert str(payload["projectId"]) == "12345"
    assert payload["released"] is False
    assert payload["archived"] is False
    assert "description" not in payload

    if expect_update:
        assert responses.calls[3].request.method == "PUT"
        assert responses.calls[3].request.url == UPDATE_VERSION_URL

        body = responses.calls[3].request.body
        if isinstance(body, bytes):
            body = body.decode("utf-8")
        payload = json.loads(body)
        assert payload["description"] == VERSION_DESCRIPTION


def test_write_github_output_noop_when_env_missing(monkeypatch, tmp_path, action_module):
    monkeypatch.delenv("GITHUB_OUTPUT", raising=False)
    out_file = tmp_path / "github_output.txt"

    action_module.write_github_output("version_id", VERSION_ID)

    assert not out_file.exists()


@pytest.mark.parametrize("value", ["", "   "])
def test_write_github_output_noop_when_env_blank(monkeypatch, tmp_path, action_module, value):
    monkeypatch.setenv("GITHUB_OUTPUT", value)

    action_module.write_github_output("version_id", VERSION_ID)


def test_write_github_output_writes_key_value_line(monkeypatch, tmp_path, action_module):
    out_file = tmp_path / "github_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))

    action_module.write_github_output("version_id", VERSION_ID)

    assert out_file.read_text(encoding="utf-8") == f"version_id={VERSION_ID}\n"


def test_write_github_output_appends_multiple_lines(monkeypatch, tmp_path, action_module):
    out_file = tmp_path / "github_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))

    action_module.write_github_output("version_id", VERSION_ID)
    action_module.write_github_output("version_name", VERSION_NAME)

    assert out_file.read_text(encoding="utf-8") == f"version_id={VERSION_ID}\nversion_name={VERSION_NAME}\n"


def test_main_happy_path_writes_github_output(monkeypatch, tmp_path, capsys, action_module, required_env):
    out_file = tmp_path / "github_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    required_env(JIRA_VERSION_DESCRIPTION="  hello  ")
    fake_jira = object()

    def fake_jira_ctor(*, url, username, password, cloud):
        assert url == BASE_URL
        assert username == "user"
        assert password == "token"
        assert cloud is True
        return fake_jira

    captured = {}

    def fake_ensure_version(jira, project_key, version_name, description):
        captured["args"] = (jira, project_key, version_name, description)
        return VERSION_ID

    monkeypatch.setattr(action_module, "Jira", fake_jira_ctor)
    monkeypatch.setattr(action_module, "ensure_version", fake_ensure_version)

    action_module.main()

    assert captured["args"] == (fake_jira, "PRJ", VERSION_NAME, "hello")
    out = capsys.readouterr().out
    assert f"version_id = {VERSION_ID}" in out
    assert out_file.read_text(encoding="utf-8") == f"version_id={VERSION_ID}\n"


@pytest.mark.parametrize("desc", [None, "", "   ", "\n\t  "])
def test_main_strips_description_to_none(monkeypatch, tmp_path, capsys, action_module, desc, required_env):
    out_file = tmp_path / "github_output.txt"
    monkeypatch.setenv("GITHUB_OUTPUT", str(out_file))
    required_env()
    if desc is None:
        monkeypatch.delenv("JIRA_VERSION_DESCRIPTION", raising=False)
    else:
        monkeypatch.setenv("JIRA_VERSION_DESCRIPTION", desc)
    fake_jira = object()
    monkeypatch.setattr(action_module, "Jira", lambda **_: fake_jira)
    captured = {}

    def fake_ensure_version(_jira, _project_key, _version_name, description):
        captured["description"] = description
        return "111"

    monkeypatch.setattr(action_module, "ensure_version", fake_ensure_version)

    action_module.main()

    assert captured["description"] is None

    assert out_file.read_text(encoding="utf-8") == "version_id=111\n"
    out = capsys.readouterr().out
    assert "version_id = 111" in out


def test_main_exits_1_when_missing_required_env(monkeypatch, capsys, action_module, required_env):
    monkeypatch.delenv("JIRA_URL", raising=False)

    with pytest.raises(SystemExit) as exc:
        action_module.main()

    assert exc.value.code == 1
    err = capsys.readouterr().err
    assert "Missing required environment variable: JIRA_URL" in err


def test_main_exits_1_on_http_error_from_ensure_version(monkeypatch, capsys, action_module, required_env):
    required_env(JIRA_VERSION_DESCRIPTION="desc")
    monkeypatch.setattr(action_module, "Jira", lambda **_: object())

    def boom(*_args, **_kwargs):
        raise HTTPError("boom")

    monkeypatch.setattr(action_module, "ensure_version", boom)

    with pytest.raises(SystemExit) as exc:
        action_module.main()

    assert exc.value.code == 1
    err = capsys.readouterr().err
    assert "HTTP error occurred." in err
    assert "boom" in err
