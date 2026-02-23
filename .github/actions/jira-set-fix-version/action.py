import os
import sys
from typing import Any, Dict, List, Optional, Tuple

from atlassian import Jira
from requests import HTTPError

OUTPUT_CHANGED = "changed"
OUTPUT_FIXVERSIONS = "fix-versions"
# Optional output to help debug multi-issue runs
OUTPUT_FIXVERSIONS_BY_ISSUE = "fix-versions-by-issue"


def get_required_env(var_name: str) -> str:
    value = os.getenv(var_name)

    if value is None or value.strip() == "":
        print(f"❌ Missing required environment variable: {var_name}", file=sys.stderr)
        sys.exit(1)

    return value


def get_optional_env(var_name: str) -> Optional[str]:
    v = os.getenv(var_name)
    if v is None:
        return None
    return v.strip() or None


def parse_bool(value: str) -> bool:
    v = value.strip().lower()

    if v not in {"true", "false"}:
        print("❌ Boolean value must be 'true' or 'false'", file=sys.stderr)
        sys.exit(1)

    return v == "true"


def project_key_from_issue_key(issue_key: str) -> str:
    if "-" not in issue_key:
        print(
            f"❌ Invalid JIRA issue key format: '{issue_key}'. Expected something like 'PROJ-123'.",
            file=sys.stderr,
        )
        sys.exit(1)

    return issue_key.split("-", 1)[0].strip()


def parse_issue_keys(raw: str) -> List[str]:
    """
    Accept comma-separated issue keys.
    Spaces are ignored.

    Examples:
      "PROJ-1"
      "PROJ-1,PROJ-2"
      "PROJ-1, PROJ-2 ,PROJ-3"
    """
    if not raw or not raw.strip():
        return []

    normalized = raw.replace(" ", "").strip()
    parts = normalized.split(",")

    # Reject empty segments (e.g., trailing comma or double commas)
    if any(not p for p in parts):
        print(
            "❌ Invalid JIRA_ISSUE_KEYS format. Use comma-separated values like: PROJ-1,PROJ-2",
            file=sys.stderr,
        )
        sys.exit(1)

    return parts


def resolve_version(
    jira: Jira,
    project_key: str,
    version_id: Optional[str],
    version_name: Optional[str],
) -> Optional[Dict[str, Any]]:
    """
    Resolve a Jira version from the project's versions list using either:
    - version_id (preferred)
    - version_name (fallback)

    Only one should be provided.
    """
    versions = jira.get_project_versions(project_key) or []

    if version_id:
        for v in versions:
            if str(v.get("id", "")).strip() == version_id:
                return v
        return None

    for v in versions:
        if str(v.get("name", "")).strip() == version_name:
            return v

    return None


def write_github_output(key: str, value: str) -> None:
    out_path = os.getenv("GITHUB_OUTPUT")
    out_path = out_path.strip() if out_path else None

    if not out_path:
        return

    # NOTE: This simple format assumes value has no newlines.
    with open(out_path, "a", encoding="utf-8") as f:
        f.write(f"{key}={value}\n")


def unique_versions_by_id_or_name(versions: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """
    Remove duplicates while keeping stable order.
    Prefer 'id' for uniqueness, fallback to 'name'.
    """
    seen_ids = set()
    seen_names = set()
    out: List[Dict[str, Any]] = []

    for v in versions:
        vid = str(v.get("id", "")).strip()
        vname = str(v.get("name", "")).strip()

        if vid:
            if vid in seen_ids:
                continue
            seen_ids.add(vid)
        else:
            if vname and vname in seen_names:
                continue

        if vname:
            seen_names.add(vname)

        out.append(v)

    return out


def get_issue_fix_versions(jira: Jira, issue_key: str) -> List[Dict[str, Any]]:
    # Cloud uses API v3. This endpoint returns fixVersions as a list of objects.
    issue = jira.get(f"rest/api/3/issue/{issue_key}", params={"fields": "fixVersions"}) or {}
    fields = issue.get("fields") or {}
    return fields.get("fixVersions") or []


def update_issue_fix_versions(jira: Jira, issue_key: str, versions: List[Dict[str, Any]]) -> None:
    # Jira expects array of objects, typically with id.
    missing_ids = [v for v in versions if not str(v.get("id", "")).strip()]
    if missing_ids:
        print("❌ Cannot update fixVersions: at least one version is missing an 'id'.", file=sys.stderr)
        sys.exit(1)

    payload = {"fields": {"fixVersions": [{"id": str(v["id"]).strip()} for v in versions]}}
    jira.put(f"rest/api/3/issue/{issue_key}", data=payload)


def versions_equal(a: List[Dict[str, Any]], b: List[Dict[str, Any]]) -> bool:
    """
    Compare versions lists ignoring order differences due to API.
    Use id if available, else name.
    """

    def key(v: Dict[str, Any]) -> Tuple[str, str]:
        return str(v.get("id", "")).strip(), str(v.get("name", "")).strip()

    return sorted([key(v) for v in a]) == sorted([key(v) for v in b])


def main() -> None:
    jira_url = get_required_env("JIRA_URL")
    jira_user = get_required_env("JIRA_USER")
    jira_token = get_required_env("JIRA_TOKEN")

    # Simplified contract: only JIRA_ISSUE_KEYS
    issue_keys_raw = get_required_env("JIRA_ISSUE_KEYS")
    issue_keys = parse_issue_keys(issue_keys_raw)

    if not issue_keys:
        print("❌ No issue keys provided (JIRA_ISSUE_KEYS).", file=sys.stderr)
        sys.exit(1)

    version_name = get_optional_env("JIRA_VERSION_NAME")
    version_id = get_optional_env("JIRA_VERSION_ID")

    if version_id and version_name:
        print("❌ Provide either JIRA_VERSION_ID or JIRA_VERSION_NAME, not both.", file=sys.stderr)
        sys.exit(1)

    if not version_id and not version_name:
        print("❌ Either JIRA_VERSION_ID or JIRA_VERSION_NAME must be provided.", file=sys.stderr)
        sys.exit(1)

    merge_versions = parse_bool(os.getenv("MERGE_VERSIONS", "true"))

    # Same-project assumption: derive project from the first issue
    project_key = project_key_from_issue_key(issue_keys[0])

    jira = Jira(
        url=jira_url,
        username=jira_user,
        password=jira_token,
        cloud=True,
    )

    try:
        # Resolve once per project
        version = resolve_version(jira, project_key, version_id=version_id, version_name=version_name)
        if not version:
            if version_id:
                print(
                    f"❌ Fix version id '{version_id}' does not exist in project '{project_key}'.",
                    file=sys.stderr,
                )
            else:
                print(
                    f"❌ Fix version '{version_name}' does not exist in project '{project_key}'.",
                    file=sys.stderr,
                )
            sys.exit(1)

        version_id_norm = str(version.get("id", "")).strip()
        version_name_norm = str(version.get("name", "")).strip()

        changed_any = False
        union_names: List[str] = []
        by_issue_parts: List[str] = []

        for issue_key in issue_keys:
            # Safety guard: ensure all issues belong to the same project
            if project_key_from_issue_key(issue_key) != project_key:
                print(
                    f"❌ Issue '{issue_key}' is not in project '{project_key}'. "
                    f"All issues must be in the same Jira project for this action.",
                    file=sys.stderr,
                )
                sys.exit(1)

            current = unique_versions_by_id_or_name(get_issue_fix_versions(jira, issue_key))

            already_present = any(
                (version_id_norm and str(v.get("id", "")).strip() == version_id_norm)
                or (version_name_norm and str(v.get("name", "")).strip() == version_name_norm)
                for v in current
            )

            if merge_versions:
                target = list(current)
                if not already_present:
                    target.append(version)
            else:
                target = [version]

            target = unique_versions_by_id_or_name(target)

            changed = not versions_equal(current, target)
            if changed:
                update_issue_fix_versions(jira, issue_key, target)
                changed_any = True

            target_names_list = [str(v.get("name", "")).strip() for v in target if str(v.get("name", "")).strip()]
            for n in target_names_list:
                if n and n not in union_names:
                    union_names.append(n)

            target_names = ",".join(target_names_list)
            by_issue_parts.append(f"{issue_key}:{target_names}")

            if changed:
                print(f"✅ Updated fixVersions for {issue_key}: {target_names}")
            else:
                print(f"ℹ️ No change needed for {issue_key}. fixVersions already up-to-date: {target_names}")

        write_github_output(OUTPUT_CHANGED, "true" if changed_any else "false")
        write_github_output(OUTPUT_FIXVERSIONS, ",".join(union_names))
        write_github_output(OUTPUT_FIXVERSIONS_BY_ISSUE, "|".join(by_issue_parts))

    except HTTPError as e:
        print("❌ HTTP error occurred while calling Jira.", file=sys.stderr)
        print(str(e), file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print("❌ Unexpected error occurred.", file=sys.stderr)
        print(str(e), file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()  # pragma: no cover
