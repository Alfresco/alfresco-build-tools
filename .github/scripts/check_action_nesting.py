#!/usr/bin/env python3
"""
Check that no composite action or reusable workflow exceeds the maximum allowed
nesting depth for internal Alfresco/alfresco-build-tools action references.

Nesting depth is defined as the longest chain of internal `uses:` hops starting
from a given action/workflow. Leaf actions (no internal deps) have depth 0.

Exit 1 if any node exceeds --max-depth (default: 3).
"""

import argparse
import sys
from pathlib import Path

import yaml

INTERNAL_PREFIX = "Alfresco/alfresco-build-tools/.github/actions/"
_VISITING = object()  # sentinel: node is on the current DFS stack (cycle guard)


def _extract_uses_values(data) -> list[str]:
    """Recursively walk a parsed YAML structure and collect all `uses:` values."""
    results = []
    if isinstance(data, dict):
        if "uses" in data and isinstance(data["uses"], str):
            results.append(data["uses"])
        for value in data.values():
            results.extend(_extract_uses_values(value))
    elif isinstance(data, list):
        for item in data:
            results.extend(_extract_uses_values(item))
    return results


def _internal_deps(path: Path) -> set[str]:
    """Return the set of internal action names referenced by a YAML file."""
    try:
        data = yaml.safe_load(path.read_text())
    except yaml.YAMLError:
        return set()
    deps = set()
    for ref in _extract_uses_values(data):
        if ref.startswith(INTERNAL_PREFIX):
            action_name = ref[len(INTERNAL_PREFIX) :].split("@")[0].strip("/")
            deps.add(action_name)
    return deps


def collect_nodes(root: Path) -> dict[str, set[str]]:
    """Return a dict mapping node-name → set of internal action names it calls."""
    deps: dict[str, set[str]] = {}
    actions_root = root / ".github" / "actions"

    for action_yml in [*actions_root.rglob("action.yml"), *actions_root.rglob("action.yaml")]:
        name = str(action_yml.parent.relative_to(actions_root))
        deps[name] = _internal_deps(action_yml)

    for wf_yml in [*(root / ".github" / "workflows").glob("*.yml"), *(root / ".github" / "workflows").glob("*.yaml")]:
        calls = _internal_deps(wf_yml)
        if calls:
            deps[f"workflow:{wf_yml.name}"] = calls

    return deps


def max_depth(node: str, deps: dict[str, set[str]], cache: dict) -> int:
    if node in cache:
        if cache[node] is _VISITING:
            raise ValueError(f"Cycle detected involving '{node}'")
        return cache[node]  # type: ignore[return-value]
    cache[node] = _VISITING
    children = deps.get(node, set())
    result = 0 if not children else 1 + max(max_depth(c, deps, cache) for c in children)
    cache[node] = result
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--max-depth",
        type=int,
        default=3,
        help="Maximum allowed nesting depth (default: 3)",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path("."),
        help="Repository root (default: current directory)",
    )
    args = parser.parse_args()

    deps = collect_nodes(args.root)
    cache: dict = {}
    violations: list[tuple[int, str]] = []
    cycles: list[str] = []

    for node in deps:
        try:
            depth = max_depth(node, deps, cache)
        except ValueError as exc:
            cycles.append(str(exc))
            continue
        if depth > args.max_depth:
            violations.append((depth, node))

    if cycles:
        for msg in cycles:
            print(f"ERROR: {msg}")
        return 1

    if violations:
        violations.sort(reverse=True)
        print(f"ERROR: The following actions/workflows exceed the maximum nesting depth of {args.max_depth}:")
        for depth, node in violations:
            print(f"  depth={depth}  {node}")
        print(f"\nThe two-pass SHA-pin release process guarantees consistency up to depth {args.max_depth}.")
        print("Refactor the action chain or raise --max-depth if intentional.")
        return 1

    print(f"OK: all action nesting depths are within the allowed maximum of {args.max_depth}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
