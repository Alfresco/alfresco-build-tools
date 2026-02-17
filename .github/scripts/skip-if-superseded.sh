#!/usr/bin/env bash
set -euo pipefail

# Only relevant for pull_request events
if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  echo "Not a PR event → continue."
  exit 0
fi

PR_NUMBER="${GITHUB_REF_NAME:-}"
WORKFLOW_NAME="${GITHUB_WORKFLOW:-}"
CURRENT_RUN_ID="${GITHUB_RUN_ID:-}"

echo "Checking for newer runs..."
echo "Workflow: $WORKFLOW_NAME"
echo "Current run_id: $CURRENT_RUN_ID"

# Fetch recent workflow runs for this repo
response=$(curl -s \
  -H "Authorization: Bearer $GITHUB_TOKEN" \
  -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runs?event=pull_request&per_page=20")

# Extract newest run ID for same workflow
NEWEST_RUN_ID=$(echo "$response" | jq -r \
  --arg wf "$WORKFLOW_NAME" \
  --argjson pr "${GITHUB_EVENT_PULL_REQUEST_NUMBER}" \
  '
  .workflow_runs
  | map(select(.name == $wf))
  | map(select(.pull_requests[]?.number == $pr))
  | max_by(.run_number).id // empty
  ')

echo "Newest run_id for this PR/workflow: $NEWEST_RUN_ID"

if [[ -n "$NEWEST_RUN_ID" && "$NEWEST_RUN_ID" != "$CURRENT_RUN_ID" ]]; then
  echo "A newer run exists. Exiting early to avoid duplicate execution."
  exit 0
fi

echo "This is the newest run → continue."
