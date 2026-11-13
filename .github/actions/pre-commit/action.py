import re
import sys
from pathlib import Path

import yaml

SHA_RE = re.compile(r"^[0-9a-f]{40}$")
SKIPPED_REPOS = {"local", "meta"}


def main(config_path: str = ".pre-commit-config.yaml") -> int:
    path = Path(config_path)
    if not path.is_file():
        print(f"::error::{config_path} not found")
        return 1

    config = yaml.safe_load(path.read_text()) or {}
    unfrozen = [
        (repo.get("repo"), repo.get("rev"))
        for repo in config.get("repos") or []
        if repo.get("repo") not in SKIPPED_REPOS and not SHA_RE.match(str(repo.get("rev") or ""))
    ]

    for url, rev in unfrozen:
        print(f"::error file={config_path}::{url} rev '{rev}' is not frozen to a commit SHA")

    if unfrozen:
        print('Run "pre-commit autoupdate --freeze" to pin every hook to a commit SHA.')
        return 1

    print("All pre-commit hook revisions are frozen to commit SHAs.")
    return 0


if __name__ == "__main__":
    sys.exit(main(*sys.argv[1:]))
