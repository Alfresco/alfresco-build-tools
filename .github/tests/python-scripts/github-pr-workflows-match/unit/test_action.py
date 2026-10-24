import json
import subprocess
from pathlib import Path

import pytest
import yaml

WORKFLOWS_DIR = ".github/workflows"

TERRAFORM_WORKFLOW = """
name: terraform
on:
  pull_request:
    branches:
      - develop
      - rancher-prod
    paths:
      - eks/**
      - .terraform-version
  push:
    branches:
      - develop
"""


@pytest.mark.parametrize(
    "pattern, value, expected",
    [
        ("main", "main", True),
        ("main", "main2", False),
        ("feature/*", "feature/foo", True),
        ("feature/*", "feature/foo/bar", False),
        ("feature/**", "feature/foo/bar", True),
        ("*.md", "README.md", True),
        ("*.md", "docs/README.md", False),
        ("**.md", "docs/README.md", True),
        ("**/README.md", "README.md", True),
        ("**/README.md", "a/b/README.md", True),
        ("docs/**/*.md", "docs/README.md", True),
        ("v2?", "v", True),
        ("v2?", "v2", True),
        ("v2+", "v222", True),
        ("v2+", "v", False),
        ("release-[0-9]", "release-7", True),
        ("release-[0-9]", "release-x", False),
        ("release-[0", "release-[0", True),
        ("a.b", "axb", False),
        ("file\\*", "file*", True),
        ("file\\*", "files", False),
    ],
)
def test_pattern_matches(action_module, pattern, value, expected):
    assert action_module.pattern_matches(pattern, value) is expected


@pytest.mark.parametrize(
    "patterns, value, expected",
    [
        (["releases/**", "!releases/**-alpha"], "releases/1.0", True),
        (["releases/**", "!releases/**-alpha"], "releases/1.0-alpha", False),
        (["releases/**", "!releases/**-alpha", "releases/beta-alpha"], "releases/beta-alpha", True),
        (["!main"], "main", False),
        ([], "main", False),
    ],
)
def test_filters_match_last_matching_pattern_wins(action_module, patterns, value, expected):
    assert action_module.filters_match(patterns, value) is expected


@pytest.mark.parametrize(
    "workflow, expected",
    [
        ("on: pull_request", {}),
        ("on: [push, pull_request]", {}),
        ("on: push", None),
        ("on:\n  pull_request:\n", {}),
        ("on:\n  pull_request:\n    paths: [src/**]\n", {"paths": ["src/**"]}),
        ("true:\n  pull_request:\n    branches: [main]\n", {"branches": ["main"]}),
        ("name: no trigger", None),
        ("[]", None),
    ],
)
def test_pull_request_trigger(action_module, workflow, expected):
    assert action_module.pull_request_trigger(yaml.safe_load(workflow)) == expected


@pytest.mark.parametrize(
    "trigger, branch, expected",
    [
        ({}, "main", True),
        ({"branches": ["main"]}, "main", True),
        ({"branches": ["main"]}, "develop", False),
        ({"branches": "main"}, "main", True),
        ({"branches": None}, "main", False),
        ({"branches-ignore": ["main"]}, "main", False),
        ({"branches-ignore": ["main"]}, "develop", True),
    ],
)
def test_branch_matches(action_module, trigger, branch, expected):
    assert action_module.branch_matches(trigger, branch) is expected


@pytest.mark.parametrize(
    "trigger, files, expected",
    [
        ({}, ["README.md"], True),
        ({"paths": ["eks/**"]}, ["README.md", "eks/main.tf"], True),
        ({"paths": ["eks/**"]}, ["README.md"], False),
        ({"paths": ["eks/**", "!eks/**.md"]}, ["eks/README.md"], False),
        ({"paths-ignore": ["docs/**"]}, ["docs/a.md"], False),
        ({"paths-ignore": ["docs/**"]}, ["docs/a.md", "src/a.py"], True),
    ],
)
def test_paths_match(action_module, trigger, files, expected):
    assert action_module.paths_match(trigger, files) is expected


def test_evaluate_matches_workflow_on_branch_and_paths(action_module):
    workflows = {f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW}

    assert action_module.evaluate(workflows, "rancher-prod", ["eks/main.tf"]) == (
        True,
        [f"{WORKFLOWS_DIR}/terraform.yml"],
    )


def test_evaluate_skips_when_paths_do_not_match(action_module):
    workflows = {f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW}

    assert action_module.evaluate(workflows, "rancher-prod", ["README.md"]) == (False, [])


def test_evaluate_is_branch_aware(action_module):
    workflows = {
        f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW,
        f"{WORKFLOWS_DIR}/docs.yml": "on:\n  pull_request:\n    branches: [atlas]\n    paths: [docs/**]\n",
    }

    assert action_module.evaluate(workflows, "rancher-prod", ["docs/a.md"]) == (False, [])
    assert action_module.evaluate(workflows, "atlas", ["docs/a.md"]) == (True, [f"{WORKFLOWS_DIR}/docs.yml"])


def test_evaluate_triggers_when_no_workflow_targets_branch(action_module):
    workflows = {
        f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW,
        f"{WORKFLOWS_DIR}/push.yml": "on: push\n",
    }

    assert action_module.evaluate(workflows, "atlas", ["README.md"]) == (True, [])


def test_evaluate_counts_invalid_workflow_as_matching(action_module, capsys):
    workflows = {
        f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW,
        f"{WORKFLOWS_DIR}/broken.yml": "on: [pull_request\n",
    }

    assert action_module.evaluate(workflows, "rancher-prod", ["README.md"]) == (
        True,
        [f"{WORKFLOWS_DIR}/broken.yml"],
    )
    assert "::warning::" in capsys.readouterr().out


def test_evaluate_returns_false_on_empty_diff(action_module):
    workflows = {f"{WORKFLOWS_DIR}/ci.yml": "on: pull_request\n"}

    assert action_module.evaluate(workflows, "main", []) == (False, [])


def test_evaluate_triggers_path_filtered_workflows_past_github_file_limit(action_module):
    workflows = {f"{WORKFLOWS_DIR}/terraform.yml": TERRAFORM_WORKFLOW}
    files = [f"docs/{i}.md" for i in range(301)]

    assert action_module.evaluate(workflows, "rancher-prod", files) == (
        True,
        [f"{WORKFLOWS_DIR}/terraform.yml"],
    )


def _git(cwd: Path, *args: str) -> str:
    return subprocess.run(["git", *args], cwd=cwd, check=True, capture_output=True, text=True).stdout


def _commit(repo: Path, path: str, content: str) -> None:
    file = repo / path
    file.parent.mkdir(parents=True, exist_ok=True)
    file.write_text(content)
    _git(repo, "add", path)
    _git(repo, "commit", "-q", "-m", f"update {path}")


@pytest.mark.parametrize("value", [None, "", "   "])
def test_get_required_env_exits_on_missing_or_blank(monkeypatch, action_module, value):
    if value is None:
        monkeypatch.delenv("MY_VAR", raising=False)
    else:
        monkeypatch.setenv("MY_VAR", value)

    with pytest.raises(SystemExit) as exc:
        action_module.get_required_env("MY_VAR")

    assert exc.value.code == 1


@pytest.fixture
def promotion_clone(tmp_path):
    def _make(source_changes: dict[str, str]) -> Path:
        upstream = tmp_path / "upstream"
        upstream.mkdir()
        _git(upstream, "init", "-q", "-b", "rancher-prod")
        _git(upstream, "config", "user.email", "test@example.com")
        _git(upstream, "config", "user.name", "test")
        _commit(upstream, f"{WORKFLOWS_DIR}/terraform.yml", TERRAFORM_WORKFLOW)
        _commit(upstream, f"{WORKFLOWS_DIR}/README.md", "not a workflow")
        _git(upstream, "switch", "-q", "-c", "develop")
        for path, content in source_changes.items():
            _commit(upstream, path, content)

        clone = tmp_path / "clone"
        _git(tmp_path, "clone", "-q", "-b", "rancher-prod", str(upstream), str(clone))
        return clone

    return _make


@pytest.mark.parametrize(
    "source_changes, triggered, matched",
    [
        ({"README.md": "docs"}, "false", []),
        ({"eks/main.tf": "resource"}, "true", [f"{WORKFLOWS_DIR}/terraform.yml"]),
        ({f"{WORKFLOWS_DIR}/lint.yml": "on: pull_request\n"}, "true", [f"{WORKFLOWS_DIR}/lint.yml"]),
    ],
)
def test_main_writes_outputs(action_module, promotion_clone, monkeypatch, tmp_path, source_changes, triggered, matched):
    clone = promotion_clone(source_changes)
    output = tmp_path / "github_output"
    monkeypatch.chdir(clone)
    monkeypatch.setenv("BASE_BRANCH", "rancher-prod")
    monkeypatch.setenv("HEAD_BRANCH", "develop")
    monkeypatch.setenv("REMOTE", "origin")
    monkeypatch.setenv("GITHUB_OUTPUT", str(output))

    action_module.main()

    lines = output.read_text().splitlines()
    assert f"triggered={triggered}" in lines
    assert f"workflows={json.dumps(matched)}" in lines
