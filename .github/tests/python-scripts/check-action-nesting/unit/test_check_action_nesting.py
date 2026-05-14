from unit.conftest import install_fixture_actions, make_workflow

import check_action_nesting  # noqa: F401 - ensure module is importable
from check_action_nesting import collect_nodes, main, max_depth

# ---------------------------------------------------------------------------
# collect_nodes
# ---------------------------------------------------------------------------


def test_collect_nodes_leaf_action_has_empty_deps(tmp_path):
    install_fixture_actions(tmp_path, "leaf")
    deps = collect_nodes(tmp_path)
    assert deps["leaf"] == set()


def test_collect_nodes_action_with_internal_ref(tmp_path):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf")
    deps = collect_nodes(tmp_path)
    assert deps["wraps-leaf"] == {"leaf"}
    assert deps["leaf"] == set()


def test_collect_nodes_folded_scalar_uses_is_detected(tmp_path):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf-folded")
    deps = collect_nodes(tmp_path)
    assert deps["wraps-leaf-folded"] == {"leaf"}


def test_collect_nodes_sub_directory_action_keyed_by_full_path(tmp_path):
    install_fixture_actions(tmp_path, "nested-group/child", "wraps-nested-child")
    deps = collect_nodes(tmp_path)
    assert "nested-group/child" in deps
    assert deps["wraps-nested-child"] == {"nested-group/child"}


def test_collect_nodes_sub_directory_chain_depth_counted_correctly(tmp_path):
    install_fixture_actions(tmp_path, "nested-group/child", "wraps-nested-child")
    deps = collect_nodes(tmp_path)
    cache: dict = {}
    assert max_depth("wraps-nested-child", deps, cache) == 1


def test_collect_nodes_workflow_without_internal_refs_is_excluded(tmp_path):
    make_workflow(tmp_path, "no-internal.yml", uses=[])
    deps = collect_nodes(tmp_path)
    assert not any(k.startswith("workflow:") for k in deps)


def test_collect_nodes_workflow_with_internal_refs_is_included(tmp_path):
    install_fixture_actions(tmp_path, "leaf")
    make_workflow(tmp_path, "my-wf.yml", uses=["leaf"])
    deps = collect_nodes(tmp_path)
    assert "workflow:my-wf.yml" in deps
    assert deps["workflow:my-wf.yml"] == {"leaf"}


# ---------------------------------------------------------------------------
# max_depth
# ---------------------------------------------------------------------------


def test_max_depth_leaf_returns_zero():
    deps = {"leaf": set()}
    assert max_depth("leaf", deps, {}) == 0


def test_max_depth_single_hop_returns_one():
    deps = {"wraps-leaf": {"leaf"}, "leaf": set()}
    assert max_depth("wraps-leaf", deps, {}) == 1


def test_max_depth_chain_of_three_returns_two():
    deps = {"a": {"b"}, "b": {"c"}, "c": set()}
    assert max_depth("a", deps, {}) == 2


def test_max_depth_chain_of_four_returns_three():
    deps = {"a": {"b"}, "b": {"c"}, "c": {"d"}, "d": set()}
    assert max_depth("a", deps, {}) == 3


def test_max_depth_uses_longest_branch():
    # a -> b (depth 0) and a -> c -> d (depth 1), so a = 2
    deps = {"a": {"b", "c"}, "b": set(), "c": {"d"}, "d": set()}
    assert max_depth("a", deps, {}) == 2


def test_max_depth_uses_cache():
    deps = {"a": {"b"}, "b": set()}
    cache = {}
    max_depth("a", deps, cache)
    assert "a" in cache and "b" in cache


def test_max_depth_unknown_node_returns_zero():
    assert max_depth("unknown", {}, {}) == 0


# ---------------------------------------------------------------------------
# main (integration via tmp_path + fixture actions)
# ---------------------------------------------------------------------------


def test_main_passes_at_max_depth(tmp_path, monkeypatch):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf", "wraps-wraps-leaf", "wraps-wraps-wraps-leaf")
    monkeypatch.setattr("sys.argv", ["check_action_nesting.py", "--root", str(tmp_path), "--max-depth", "3"])
    assert main() == 0


def test_main_fails_when_depth_exceeds_limit(tmp_path, monkeypatch, capsys):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf", "wraps-wraps-leaf", "wraps-wraps-wraps-leaf", "too-deep")
    monkeypatch.setattr("sys.argv", ["check_action_nesting.py", "--root", str(tmp_path), "--max-depth", "3"])
    assert main() == 1
    out = capsys.readouterr().out
    assert "ERROR" in out
    assert "depth=4" in out
    assert "too-deep" in out


def test_main_passes_with_higher_max_depth(tmp_path, monkeypatch):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf", "wraps-wraps-leaf", "wraps-wraps-wraps-leaf", "too-deep")
    monkeypatch.setattr("sys.argv", ["check_action_nesting.py", "--root", str(tmp_path), "--max-depth", "4"])
    assert main() == 0


def test_main_empty_repo_passes(tmp_path, monkeypatch):
    (tmp_path / ".github" / "actions").mkdir(parents=True)
    monkeypatch.setattr("sys.argv", ["check_action_nesting.py", "--root", str(tmp_path)])
    assert main() == 0


def test_main_output_lists_all_violations(tmp_path, monkeypatch, capsys):
    install_fixture_actions(tmp_path, "leaf", "wraps-leaf", "wraps-wraps-leaf", "wraps-wraps-wraps-leaf", "too-deep")
    # Also add a second violating action by copying too-deep under a different name
    import shutil

    shutil.copytree(
        tmp_path / ".github" / "actions" / "too-deep",
        tmp_path / ".github" / "actions" / "also-too-deep",
    )
    monkeypatch.setattr("sys.argv", ["check_action_nesting.py", "--root", str(tmp_path), "--max-depth", "3"])
    assert main() == 1
    out = capsys.readouterr().out
    assert "too-deep" in out
    assert "also-too-deep" in out
