import importlib.util
from pathlib import Path

import pytest

ACTION_FILE = "action.py"


@pytest.fixture
def action_module(request):
    config = request.config
    python_paths = config.getini("pythonpath") or []
    if not python_paths:
        raise RuntimeError("No pythonpath configured in pytest ini options.")

    root = Path(str(config.rootpath)).resolve()

    # Resolve all pythonpath (relative -> rootdir)
    resolved_dirs: list[Path] = []
    for p in python_paths:
        pp = Path(p)
        if not pp.is_absolute():
            pp = (root / pp).resolve()
        else:
            pp = pp.resolve()
        resolved_dirs.append(pp)

    # Select the path containing ACTION_FILE
    candidates = [d for d in resolved_dirs if d.is_dir() and (d / ACTION_FILE).exists()]
    if len(candidates) == 0:
        raise FileNotFoundError(
            f"Could not find {ACTION_FILE} in any pythonpath entry. "
            f"pythonpath={python_paths}, resolved={resolved_dirs}"
        )
    if len(candidates) > 1:
        raise RuntimeError(
            f"Multiple pythonpath entries contain {ACTION_FILE}; can't decide which one to load: "
            + ", ".join(str(c) for c in candidates)
        )

    action_path = candidates[0] / ACTION_FILE

    module_name = config.getoption("cov_source")[0]
    spec = importlib.util.spec_from_file_location(module_name, action_path)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module
