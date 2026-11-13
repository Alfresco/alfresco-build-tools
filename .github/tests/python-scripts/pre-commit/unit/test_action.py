import textwrap

import pytest

SHA = "3e8a8703264a2f4a69428a0aa4dcb512790b2c8c"
SHA_2 = "39478bf2c099a58683d3f1aedf675105318b078d"


@pytest.fixture
def write_config(tmp_path):
    def _write(content: str):
        path = tmp_path / ".pre-commit-config.yaml"
        path.write_text(textwrap.dedent(content))
        return str(path)

    return _write


def test_all_remote_repos_frozen_passes(action_module, write_config, capsys):
    config = write_config(f"""
        repos:
          - repo: https://github.com/pre-commit/pre-commit-hooks
            rev: {SHA}  # frozen: v6.0.0
            hooks: [{{id: check-yaml}}]
          - repo: https://github.com/sirosen/check-jsonschema
            rev: {SHA_2}  # frozen: 0.39.0
            hooks: [{{id: check-dependabot}}]
        """)

    assert action_module.main(config) == 0
    assert "::error" not in capsys.readouterr().out


def test_local_and_meta_repos_are_ignored(action_module, write_config):
    config = write_config("""
        repos:
          - repo: local
            hooks: [{id: x, name: x, entry: echo, language: system}]
          - repo: meta
            hooks: [{id: check-hooks-apply}]
        """)

    assert action_module.main(config) == 0


def test_tag_rev_fails_and_names_repo(action_module, write_config, capsys):
    config = write_config("""
        repos:
          - repo: https://github.com/pre-commit/pre-commit-hooks
            rev: v6.0.0
            hooks: [{id: check-yaml}]
        """)

    assert action_module.main(config) == 1
    out = capsys.readouterr().out
    assert "::error" in out
    assert "https://github.com/pre-commit/pre-commit-hooks" in out
    assert "v6.0.0" in out
    assert "pre-commit autoupdate --freeze" in out


@pytest.mark.parametrize(
    "rev",
    [SHA[:7], SHA.upper(), "master", SHA + "0", "abcdefg" + SHA[7:]],
)
def test_non_sha_revs_fail(action_module, write_config, rev):
    config = write_config(f"""
        repos:
          - repo: https://github.com/example/hooks
            rev: {rev}
            hooks: [{{id: x}}]
        """)

    assert action_module.main(config) == 1


def test_only_unfrozen_repos_are_reported(action_module, write_config, capsys):
    config = write_config(f"""
        repos:
          - repo: https://github.com/example/frozen
            rev: {SHA}
            hooks: [{{id: x}}]
          - repo: https://github.com/example/unfrozen-a
            rev: v1.0.0
            hooks: [{{id: x}}]
          - repo: https://github.com/example/unfrozen-b
            rev: v2.0.0
            hooks: [{{id: x}}]
        """)

    assert action_module.main(config) == 1
    out = capsys.readouterr().out
    assert "unfrozen-a" in out
    assert "unfrozen-b" in out
    assert "example/frozen" not in out


def test_missing_config_fails(action_module, tmp_path, capsys):
    assert action_module.main(str(tmp_path / "nope.yaml")) == 1
    assert "::error" in capsys.readouterr().out


@pytest.mark.parametrize("content", ["repos: []\n", "{}\n", ""])
def test_no_repos_passes(action_module, write_config, content):
    assert action_module.main(write_config(content)) == 0


def test_repo_without_rev_fails(action_module, write_config):
    config = write_config("""
        repos:
          - repo: https://github.com/example/hooks
            hooks: [{id: x}]
        """)

    assert action_module.main(config) == 1
