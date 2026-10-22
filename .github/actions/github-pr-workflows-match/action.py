import json
import os
import re
import subprocess
import sys
from typing import Any, Dict, List, Optional, Tuple

import yaml

WORKFLOWS_DIR = ".github/workflows"
# Past this many changed files GitHub runs path-filtered workflows unconditionally.
GITHUB_DIFF_FILE_LIMIT = 300


def pattern_to_regex(pattern: str) -> str:
    regex = ""
    i = 0
    while i < len(pattern):
        c = pattern[i]
        if c == "\\" and i + 1 < len(pattern):
            regex += re.escape(pattern[i + 1])
            i += 2
            continue
        if pattern.startswith("**/", i):
            regex += "(?:.*/)?"
            i += 3
            continue
        if pattern.startswith("**", i):
            regex += ".*"
            i += 2
            continue
        if c == "*":
            regex += "[^/]*"
        elif c in "?+" and i > 0:
            regex += c
        elif c == "[":
            end = pattern.find("]", i + 1)
            if end == -1:
                regex += re.escape(c)
            else:
                regex += pattern[i : end + 1]
                i = end
        else:
            regex += re.escape(c)
        i += 1
    return regex


def pattern_matches(pattern: str, value: str) -> bool:
    return re.fullmatch(pattern_to_regex(pattern), value) is not None


def filters_match(patterns: List[str], value: str) -> bool:
    matched = False
    for pattern in patterns:
        if pattern.startswith("!"):
            if pattern_matches(pattern[1:], value):
                matched = False
        elif pattern_matches(pattern, value):
            matched = True
    return matched


def as_list(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    return [str(v) for v in value]


def pull_request_trigger(workflow: Any) -> Optional[Dict[str, Any]]:
    if not isinstance(workflow, dict):
        return None
    # YAML 1.1 parses a bare `on` key as boolean True.
    triggers = workflow.get("on", workflow.get(True))
    if triggers == "pull_request":
        return {}
    if isinstance(triggers, list):
        return {} if "pull_request" in triggers else None
    if isinstance(triggers, dict) and "pull_request" in triggers:
        return triggers["pull_request"] or {}
    return None


def branch_matches(trigger: Dict[str, Any], branch: str) -> bool:
    if "branches" in trigger:
        return filters_match(as_list(trigger["branches"]), branch)
    if "branches-ignore" in trigger:
        return not filters_match(as_list(trigger["branches-ignore"]), branch)
    return True


def paths_match(trigger: Dict[str, Any], files: List[str]) -> bool:
    if "paths" in trigger:
        return any(filters_match(as_list(trigger["paths"]), f) for f in files)
    if "paths-ignore" in trigger:
        return any(not filters_match(as_list(trigger["paths-ignore"]), f) for f in files)
    return True


def evaluate(workflows: Dict[str, str], base_branch: str, changed_files: List[str]) -> Tuple[bool, List[str]]:
    if not changed_files:
        print("No changes between branches")
        return False, []

    targeting = 0
    matched = []
    for path, content in sorted(workflows.items()):
        try:
            trigger = pull_request_trigger(yaml.safe_load(content))
        except yaml.YAMLError as e:
            print(f"::warning::Cannot parse {path}, assuming it would run: {e}")
            matched.append(path)
            continue
        if trigger is None or not branch_matches(trigger, base_branch):
            continue
        targeting += 1
        if len(changed_files) > GITHUB_DIFF_FILE_LIMIT or paths_match(trigger, changed_files):
            print(f"{path}: would run")
            matched.append(path)
        else:
            print(f"{path}: skipped by path filters")

    if targeting == 0 and not matched:
        print(f"No pull_request workflow targets {base_branch}")
        return True, []
    return bool(matched), matched


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True, text=True).stdout


def read_workflows(ref: str) -> Dict[str, str]:
    files = git("ls-tree", "--name-only", ref, f"{WORKFLOWS_DIR}/").splitlines()
    return {path: git("show", f"{ref}:{path}") for path in files if path.endswith((".yml", ".yaml"))}


def get_required_env(var_name: str) -> str:
    value = os.getenv(var_name)

    if value is None or value.strip() == "":
        print(f"❌ Missing required environment variable: {var_name}", file=sys.stderr)
        sys.exit(1)

    return value


def main() -> None:
    base_branch = get_required_env("BASE_BRANCH")
    head_branch = get_required_env("HEAD_BRANCH")
    remote = get_required_env("REMOTE")
    base_ref = f"{remote}/{base_branch}"
    head_ref = f"{remote}/{head_branch}"

    # GitHub evaluates paths against the three-dot diff and reports both sides of a rename.
    changed_files = git("diff", "--name-only", "--no-renames", f"{base_ref}...{head_ref}").splitlines()
    triggered, matched = evaluate(read_workflows(head_ref), base_branch, changed_files)

    with open(get_required_env("GITHUB_OUTPUT"), "a", encoding="utf-8") as f:
        f.write(f"triggered={str(triggered).lower()}\n")
        f.write(f"workflows={json.dumps(matched)}\n")


if __name__ == "__main__":
    main()  # pragma: no cover
