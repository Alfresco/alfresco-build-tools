#!/usr/bin/env bash
set -euo pipefail

# This script is meant to run in GitHub Actions.
# It writes to GITHUB_OUTPUT:
# - should_run: true/false
# - lock_acquired: true/false
# - lock_ref_path: e.g. git/refs/tags/ci-lock-python-tests-pr-123-run-456

LOCK_PREFIX="ci-lock-python-tests"

emit() {
  echo "should_run=$1" >> "$GITHUB_OUTPUT"
  echo "lock_acquired=$2" >> "$GITHUB_OUTPUT"
  echo "lock_ref_path=$3" >> "$GITHUB_OUTPUT"
}

if [[ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]]; then
  # Push => no lock; we still run (unit-only is enforced elsewhere).
  emit "true" "false" ""
  exit 0
fi

REPO="${GITHUB_REPOSITORY:?}"
PR_NUMBER="${PR_NUMBER:?}"           # passed from workflow: github.event.pull_request.number
HEAD_SHA="${HEAD_SHA:?}"             # passed from workflow: github.event.pull_request.head.sha
RUN_ID="${GITHUB_RUN_ID:?}"

# We put run_id in the ref name so we can detect staleness.
REF_NAME="refs/tags/${LOCK_PREFIX}-pr-${PR_NUMBER}-run-${RUN_ID}"
REF_DELETE_PATH="git/refs/tags/${LOCK_PREFIX}-pr-${PR_NUMBER}-run-${RUN_ID}"

# Find existing lock refs for this PR (if any)
MATCHING_PREFIX="tags/${LOCK_PREFIX}-pr-${PR_NUMBER}-run-"
existing_refs_json="$(gh api -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/git/matching-refs/${MATCHING_PREFIX}" || true)"

# If there is an existing lock, check if it is stale
existing_ref="$(echo "$existing_refs_json" | jq -r '.[0].ref // empty')"

if [[ -n "$existing_ref" ]]; then
  # Parse run_id from "...-run-<id>"
  existing_run_id="$(echo "$existing_ref" | sed -n 's/.*-run-\([0-9]\+\)$/\1/p' || true)"

  if [[ -n "$existing_run_id" ]]; then
    # Ask GitHub whether that run is still active
    run_json="$(gh api -H "Accept: application/vnd.github+json" \
      "/repos/${REPO}/actions/runs/${existing_run_id}" 2>/dev/null || true)"

    status="$(echo "$run_json" | jq -r '.status // empty')"

    if [[ "$status" == "queued" || "$status" == "in_progress" ]]; then
      echo "Lock held by active run_id=${existing_run_id} (${status}). Exiting."
      emit "false" "false" ""
      exit 0
    fi

    # If status is empty / completed / not found => stale lock, remove it.
    echo "Found stale lock ref: ${existing_ref} (run_id=${existing_run_id}, status=${status:-unknown})"
    stale_delete_path="$(echo "$existing_ref" | sed 's#^refs/##')"
    gh api -X DELETE -H "Accept: application/vnd.github+json" \
      "/repos/${REPO}/git/${stale_delete_path}" >/dev/null 2>&1 || true
  else
    # Can't parse run_id => be conservative: treat as held and exit.
    echo "Lock ref exists but run_id could not be parsed: ${existing_ref}. Exiting."
    emit "false" "false" ""
    exit 0
  fi
fi

# Try to create the lock atomically
if gh api -X POST -H "Accept: application/vnd.github+json" \
  "/repos/${REPO}/git/refs" \
  -f "ref=${REF_NAME}" \
  -f "sha=${HEAD_SHA}" >/dev/null 2>&1; then
  echo "Lock acquired: ${REF_NAME}"
  emit "true" "true" "${REF_DELETE_PATH}"
  exit 0
fi

# If create failed, someone else won the race.
echo "Failed to acquire lock (likely already exists). Exiting."
emit "false" "false" ""
