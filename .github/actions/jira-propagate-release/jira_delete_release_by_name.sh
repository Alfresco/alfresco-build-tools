#!/usr/bin/env bash
set -euo pipefail

# --- Config ---
JIRA_DOMAIN="hyland.atlassian.net"
PROJECT_KEY="OPSEXP"

# --- Env vars ---
JIRA_API_USER="${JIRA_API_USER:-alfresco-build@hyland.com}"
JIRA_API_TOKEN="${JIRA_API_TOKEN:-}"

# --- Input ---
VERSION_NAME="${1:-}"

if [[ -z "${VERSION_NAME}" ]]; then
  echo "Usage: $0 \"<release-name>\"" >&2
  exit 2
fi

if [[ -z "${JIRA_API_TOKEN}" ]]; then
  echo "Error: JIRA_API_TOKEN environment variable is not set." >&2
  echo "Example: export JIRA_API_TOKEN='ATATT...'" >&2
  exit 3
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required (install jq)." >&2
  exit 4
fi

BASE_URL="https://${JIRA_DOMAIN}"
AUTH="${JIRA_API_USER}:${JIRA_API_TOKEN}"

echo "Using Jira API user: ${JIRA_API_USER}"
echo "Looking up version '${VERSION_NAME}' in project ${PROJECT_KEY}..."

versions_json="$(curl -sS -u "${AUTH}" \
  -H "Accept: application/json" \
  "${BASE_URL}/rest/api/3/project/${PROJECT_KEY}/versions")"

# Detect API errors
if echo "$versions_json" | jq -e '.errorMessages? // empty | length > 0' >/dev/null 2>&1; then
  echo "Jira API error:" >&2
  echo "$versions_json" | jq -r '.errorMessages[]?' >&2
  exit 5
fi

matches="$(echo "$versions_json" | jq --arg name "$VERSION_NAME" -c '[.[] | select(.name == $name)]')"
count="$(echo "$matches" | jq 'length')"

if [[ "$count" -eq 0 ]]; then
  echo "No version found with exact name: '${VERSION_NAME}'" >&2
  exit 6
fi

echo "Found ${count} match(es):"
echo "$matches" | jq -r '.[] | "- id=\(.id)  name=\(.name)  released=\(.released // false)  archived=\(.archived // false)"'

if [[ "$count" -gt 1 ]]; then
  echo >&2
  echo "Refusing to delete: multiple versions share the same name." >&2
  exit 7
fi

version_id="$(echo "$matches" | jq -r '.[0].id')"

echo
read -r -p "Delete version id=${version_id} (name='${VERSION_NAME}')? [y/N] " ans
case "${ans}" in
  y|Y|yes|YES) ;;
  *) echo "Aborted."; exit 0 ;;
esac

echo "Deleting version id=${version_id}..."
http_code="$(curl -sS -o /dev/null -w "%{http_code}" \
  -X DELETE -u "${AUTH}" \
  -H "Accept: application/json" \
  "${BASE_URL}/rest/api/3/version/${version_id}")"

if [[ "$http_code" == "204" ]]; then
  echo "✅ Deleted successfully (HTTP ${http_code})."
  exit 0
fi

echo "❌ Delete failed (HTTP ${http_code})." >&2
exit 8
