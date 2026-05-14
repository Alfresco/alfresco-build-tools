import shutil
from pathlib import Path

FIXTURES_DIR = Path(__file__).parent.parent / "fixtures" / "actions"
STUB_SHA = "a" * 40


def install_fixture_actions(root: Path, *names: str) -> None:
    """Copy named fixture actions into root/.github/actions/ for testing.

    Each name corresponds to a directory under fixtures/actions/ containing
    a pre-built action.yml with real (static) nesting references.

    Available fixtures and their nesting depth:
      leaf                   - depth 0 (no internal deps)
      wraps-leaf             - depth 1 (leaf)
      wraps-wraps-leaf       - depth 2 (wraps-leaf -> leaf)
      wraps-wraps-wraps-leaf - depth 3 (current repo max, allowed)
      too-deep               - depth 4 (exceeds max, triggers violation)
    """
    (root / ".github" / "actions").mkdir(parents=True, exist_ok=True)
    for name in names:
        shutil.copytree(FIXTURES_DIR / name, root / ".github" / "actions" / name)


def make_workflow(root: Path, name: str, uses: list[str] | None = None) -> Path:
    """Create a reusable workflow yml under root/.github/workflows/<name>.

    Only workflows with internal uses: references are included in the
    nesting analysis -- workflows without deps produce no graph node.
    """
    wf_dir = root / ".github" / "workflows"
    wf_dir.mkdir(parents=True, exist_ok=True)
    uses_lines = "".join(
        f"      - uses: Alfresco/alfresco-build-tools/.github/actions/{a}@{STUB_SHA}\n" for a in (uses or [])
    )
    path = wf_dir / name
    path.write_text("on:\n  workflow_call:\njobs:\n  job:\n    runs-on: ubuntu-latest\n    steps:\n" + uses_lines)
    return path
