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


def create_version(
  jira: Jira, project_key: str, version_name: str, description: Optional[str]
) -> Dict[str, Any]:
  payload: Dict[str, Any] = {"project": project_key, "name": version_name}

  if description:
    payload["description"] = description

  created = jira.create_version(data=payload)

  if not isinstance(created, dict):
    raise RuntimeError(f"Unexpected create_version response type: {created!r}")

  return created


def ensure_version(
  jira: Jira, project_key: str, version_name: str, description: Optional[str]
) -> str:
  """
  Ensures the version exists.
  Returns (version_id, existed).
  """
  existing = get_version(jira, project_key, version_name)

  if existing:
    vid = str(existing.get("id", "")).strip()

    if not vid:
      raise RuntimeError("Version exists but missing id in Jira response.")

    return vid

  created = create_version(jira, project_key, version_name, description)
  vid = str(created.get("id", "")).strip()

  if not vid:
    raise RuntimeError(f"Version created but missing id. Response: {created!r}")

  return vid


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
    version_id, existed = ensure_version(jira, project_key, version_name, description)

    if existed:
      print("Nothing to do, release already exists.")
    print(version_id)  # last stdout line = id
    write_github_output("version_id", version_id)

  except ApiError as e:
    print_api_error(e)
    sys.exit(1)
  except Exception as e:
    print("❌ Unknown error occurred.", file=sys.stderr)
    print(str(e), file=sys.stderr)
    sys.exit(1)


if __name__ == "__main__":
  main()
