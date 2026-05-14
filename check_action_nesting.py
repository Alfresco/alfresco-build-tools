#!/usr/bin/env python3
"""
Check that no composite action or reusable workflow exceeds the maximum allowed
nesting depth for internal Alfresco/alfresco-build-tools action references.

Nesting depth is defined as the longest chain of internal `uses:` hops starting
from a given action/workflow. Leaf actions (no internal calls) have depth 0.

Exit 1 if any node exceeds --max-depth (default: 3).
"""

import argparse
import re
import sys
from pathlib import Path

INTERNAL_REF = re.compile(r"uses:\s+Alfresco/alfresco-build-tools/\.github/actions/([^@\s]+)")


def collect_nodes(root: Path) -> dict[str, set[str]]:
    """Return a dict mapping node-name → set of internal action names it calls."""
    deps: dict[str, set[str]] = {}

    # Composite actions
    for action_yml in (root / ".github" / "actions").rglob("action.yml"):
        name = action_yml.parent.name
        content = action_yml.read_text()
        deps[name] = {m.group(1).strip("/") for m in INTERNAL_REF.finditer(content)}

    # Reusable workflows
    for wf_yml in (root / ".github" / "workflows").glob("*.yml"):
        content = wf_yml.read_text()
        calls = {m.group(1).strip("/") for m in INTERNAL_REF.finditer(content)}
        if calls:
            node_name = f"workflow:{wf_yml.name}"
            deps[node_name] = calls

    return deps


def max_depth(node: str, deps: dict[str, set[str]], cache: dict[str, int]) -> int:
    if node in cache:
        return cache[node]
    cache[node] = -1  # cycle guard
    children = deps.get(node, set())
    if not children:
        result = 0
    else:
        result = 1 + max(max_depth(c, deps, cache) for c in children)
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
    cache: dict[str, int] = {}
    violations: list[tuple[int, str]] = []

    for node in deps:
        depth = max_depth(node, deps, cache)
        if depth > args.max_depth:
            violations.append((depth, node))

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
