#!/usr/bin/env bash
set -euo pipefail

# Extract ticket IDs from a GitHub Release event payload JSON and output as one-line CSV.
#
# Usage:
#   extract-tickets-from-release-payload.sh [path_to_event_json]
#
# Environment variables:
#   TICKET_REGEX                  Regex for ticket IDs (default: Jira-like)
#   GITHUB_OUTPUT                 If set, write outputs there (GitHub Actions outputs file)
#   GITHUB_VERSION_PREFIX         Prefix to remove from GitHub tag (literal match)
#   JIRA_VERSION_PREFIX           Prefix to prepend to Jira version name
#
# Output keys:
#   tickets-csv=ABC-1,DEF-2        Comma-separated list of unique ticket IDs (empty if none found)
#   jira-version-name=v1.2.3       Normalized Jira version name derived from the GitHub tag (empty if tag_name missing)
#
# Exit codes:
#   0 success even if no tickets are found (writes/prints tickets-csv=)
#   1 error (missing payload, jq not available, invalid regex, etc.)

EVENT_PATH="${1:-${GITHUB_EVENT_PATH:-}}"
TICKET_REGEX="${TICKET_REGEX:-[A-Z][A-Z0-9]+-[0-9]+}"

if [[ -z "${EVENT_PATH}" || ! -f "${EVENT_PATH}" ]]; then
  echo "::error::Event payload not found. Provide a path or ensure GITHUB_EVENT_PATH is set."
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "::error::jq is required (available on GitHub-hosted runners)."
  exit 1
fi

write_output() {
  local key="$1"
  local value="$2"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    # GitHub Actions output file
    printf "%s=%s\n" "${key}" "${value}" >> "${GITHUB_OUTPUT}"
  else
    # CLI-friendly stdout
    printf "%s=%s\n" "${key}" "${value}"
  fi
}

RELEASE_BODY="$(jq -r '.release.body // ""' "${EVENT_PATH}")"
RELEASE_NAME="$(jq -r '.release.name // ""' "${EVENT_PATH}")"
TAG_NAME="$(jq -r '.release.tag_name // ""' "${EVENT_PATH}")"
HTML_URL="$(jq -r '.release.html_url // ""' "${EVENT_PATH}")"

# Remove GitHub version prefix if provided (literal match)
RAW_TAG_NAME="${TAG_NAME}"
NORMALIZED_TAG="${RAW_TAG_NAME}"

if [[ -n "${GITHUB_VERSION_PREFIX:-}" && "$NORMALIZED_TAG" == "$GITHUB_VERSION_PREFIX"* ]]; then
  NORMALIZED_TAG="${NORMALIZED_TAG:${#GITHUB_VERSION_PREFIX}}"
fi

# Add Jira version prefix if provided
JIRA_VERSION_NAME="${JIRA_VERSION_PREFIX:-}${NORMALIZED_TAG}"

# Expose Jira version name as output
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  write_output "jira-version-name" "${JIRA_VERSION_NAME}"
fi

BLOB=$(
  printf "%s\n%s\n%s\n%s\n" \
    "${RELEASE_NAME}" \
    "${TAG_NAME}" \
    "${HTML_URL}" \
    "${RELEASE_BODY}"
)

set +e
MATCHES="$(
  printf '%s\n' "${BLOB}" \
    | tr '\r' '\n' \
    | grep -oE "${TICKET_REGEX}" 2>grep_err.txt
)"
grep_status=$?
set -e

if [[ ${grep_status} -eq 2 ]]; then
  echo "::error::Invalid TICKET_REGEX '${TICKET_REGEX}':"
  cat grep_err.txt >&2
  exit 1
fi

if [[ -z "${MATCHES}" ]]; then
  write_output "tickets-csv" ""
  exit 0
fi

CSV="$(
  printf '%s\n' "${MATCHES}" \
    | sort -u \
    | paste -sd, -
)"

write_output "tickets-csv" "${CSV}"
