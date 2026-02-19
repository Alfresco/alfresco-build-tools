import os
import sys
from typing import Any, Dict, Optional

from atlassian import Jira
from requests import HTTPError


def get_required_env(var_name: str) -> str:
    value = os.getenv(var_name)

    if value is None or value.strip() == "":
        print(f"❌ Missing required environment variable: {var_name}", file=sys.stderr)
        sys.exit(1)

    return value


def get_version(jira: Jira, project_key: str, version_name: str) -> Optional[Dict[str, Any]]:
    versions = jira.get_project_versions(project_key) or []

    for v in versions:
        if str(v.get("name", "")).strip() == version_name:
            return v

    return None


def get_project_id(jira: Jira, project_key: str) -> str:
    project = jira.get_project(project_key)

    return str(project["id"]).strip()


def create_version(jira: Jira, project_key: str, version_name: str, description: Optional[str]) -> Dict[str, Any]:
    project_id = get_project_id(jira, project_key)

    created = jira.add_version(
        project_key=project_key,
        project_id=project_id,
        version=version_name,
        is_archived=False,
        is_released=False,
    )

    # add_version() does not support description; use update_version() when needed.
    if description is not None:
        updated = jira.update_version(created["id"], description=description)
        # In case update_version returns a partial payload, keep created fields.
        if isinstance(updated, dict):
            created = {**created, **updated}

    print(f"Version {created['name']} created successfully with id {created['id']}.")

    return created


def ensure_version(jira: Jira, project_key: str, version_name: str, description: Optional[str]) -> str:
    version = get_version(jira, project_key, version_name)

    if version:
        print(f"Version {version['name']} found with id {version['id']}.")
    else:
        version = create_version(jira, project_key, version_name, description)

    return version["id"]


def write_github_output(key: str, value: str) -> None:
    out_path = os.getenv("GITHUB_OUTPUT")
    out_path = out_path.strip() if out_path else None

    if not out_path:
        return

    with open(out_path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def main() -> None:
    jira_url = get_required_env("JIRA_URL")
    jira_user = get_required_env("JIRA_USER")
    jira_token = get_required_env("JIRA_TOKEN")
    project_key = get_required_env("JIRA_PROJECT_KEY")
    version_name = get_required_env("JIRA_VERSION_NAME")
    description = os.getenv("JIRA_VERSION_DESCRIPTION")

    if description is not None:
        description = description.strip() or None

    jira = Jira(
        url=jira_url,
        username=jira_user,
        password=jira_token,
        cloud=True,
    )

    try:
        version_id = ensure_version(jira, project_key, version_name, description)

        print(f"version_id = {version_id}")
        write_github_output("version_id", version_id)
    except HTTPError as e:
        print("❌ HTTP error occurred.", file=sys.stderr)
        print(str(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()  # pragma: no cover
