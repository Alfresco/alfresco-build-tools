import importlib.util
from pathlib import Path

import pytest
import responses


@pytest.fixture
def action_module():
    def find_github_root(start: Path) -> Path:
        p = start.resolve()
        for parent in [p] + list(p.parents):
            if parent.name == ".github":
                return parent
        raise RuntimeError(f"Could not find .github root from {start}")

    github_root = find_github_root(Path(__file__))
    action_path = github_root / "actions" / "slack-file-upload" / "action.py"

    if not action_path.exists():
        raise FileNotFoundError(f"action.py not found at: {action_path}")

    spec = importlib.util.spec_from_file_location("slack-file-upload", action_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)

    return module


@responses.activate
def test_dummy():
    print("hey !")
