import os
import sys
from typing import Optional, Dict, Any

from atlassian import Jira
from atlassian.errors import ApiError

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
  if not isinstance(project, dict):
    raise RuntimeError(f"Unexpected get_project response type: {project!r}")

  pid = str(project.get("id", "")).strip()
  if not pid:
    raise RuntimeError(f"Could not extract project id from get_project response: {project!r}")
  return pid


def create_version(
  jira: Jira, project_key: str, version_name: str, description: Optional[str]
) -> Dict[str, Any]:
  project_id = get_project_id(jira, project_key)

  created = jira.add_version(
    project_key=project_key,
    project_id=project_id,
    version=version_name,
    is_archived=False,
    is_released=False,
  )

  if not isinstance(created, dict):
    raise RuntimeError(f"Unexpected add_version response type: {created!r}")

  return created


def ensure_version(
  jira: Jira, project_key: str, version_name: str, description: Optional[str]
) -> str:
  version = get_version(jira, project_key, version_name)

  if version:
    print(f"Version {version['name']} found with id {version['id']}.")
  else:
    version = create_version(jira, project_key, version_name, description)

  return version['id']


def write_github_output(key: str, value: str) -> None:
  out_path = os.getenv("GITHUB_OUTPUT")

  if not out_path:
    return

  with open(out_path, "a", encoding="utf-8") as f:
    f.write(f"{key}={value}\n")


def print_api_error(err: ApiError) -> None:
  status = getattr(err, "status_code", "unknown")
  resp = getattr(err, "response", None)

  print("Jira API error", file=sys.stderr)
  print(f"status_code={status}", file=sys.stderr)

  if resp is not None:
    try:
      print("response=", resp.text, file=sys.stderr)
    except Exception:
      print("response=<unreadable>", file=sys.stderr)
  else:
    print(f"response={err}", file=sys.stderr)


def main() -> None:
  try:
    jira_url = get_required_env("JIRA_URL")
    jira_user = get_required_env("JIRA_USER")
    jira_token = get_required_env("JIRA_TOKEN")
    project_key = get_required_env("JIRA_PROJECT_KEY")
    version_name = get_required_env("JIRA_VERSION_NAME")
    description = os.getenv("JIRA_VERSION_DESCRIPTION")

    if description is not None:
      description = description.strip() or None
  except ValueError as e:
    print(f"❌ {e}", file=sys.stderr)
    sys.exit(1)

  jira = Jira(
    url=jira_url,
    username=jira_user,
    password=jira_token,
    cloud=True,
  )

  try:
    version_id = ensure_version(jira, project_key, version_name, description)

    print(version_id)  # last stdout line = id
    write_github_output("version_id", version_id)

  except ApiError as e:
    print_api_error(e)
    sys.exit(1)
  except Exception as e:
    print("❌ Unexpected error occurred.", file=sys.stderr)
    print(str(e), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
  main()
