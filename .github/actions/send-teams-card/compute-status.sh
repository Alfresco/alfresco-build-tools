#!/usr/bin/env bash
set -euo pipefail

conclusions=$(gh api --paginate \
  "repos/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}/jobs?per_page=100" \
  --jq '.jobs[].steps[] | select(.status == "completed") | .conclusion')

if grep -qx failure <<<"$conclusions"; then
  status="failure"
elif grep -qx cancelled <<<"$conclusions"; then
  status="cancelled"
else
  status="success"
fi

echo "status=${status}"
