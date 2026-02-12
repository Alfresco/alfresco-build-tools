import os
import sys


def get_required_env(var_name: str) -> str:
  value = os.getenv(var_name)

  if value is None or value.strip() == "":
    print(f"❌ Missing required environment variable: {var_name}", file=sys.stderr)
    sys.exit(1)

  return value


jira_user = get_required_env("JIRA_USER")
jira_token = get_required_env("JIRA_TOKEN")

print(f"{jira_user = }")
