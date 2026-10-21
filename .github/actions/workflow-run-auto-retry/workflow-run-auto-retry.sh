#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

if [ "${GITHUB_EVENT_NAME:-}" != "workflow_run" ]; then
  echo "::error::This action only works on a workflow_run event, not on ${GITHUB_EVENT_NAME:-an unknown event}"
  exit 1
fi

MAX_ATTEMPTS=""
FAILED=""

emit() {
  echo "$1=$2" >> "$GITHUB_OUTPUT"
}

decide() {
  emit decision "$1"
  emit reason "$2"
  emit attempt "$RUN_ATTEMPT"
  emit max-attempts "$MAX_ATTEMPTS"
  local delim="EOF_${RANDOM}${RANDOM}"
  {
    echo "failed-jobs<<${delim}"
    [ -n "$FAILED" ] && printf '%s\n' "$FAILED"
    echo "$delim"
  } >> "$GITHUB_OUTPUT"
  echo "$2"
  # Every outcome lands in the job summary, so a decision not to retry is still visible.
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "**$1**: $2" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
}

# Returns 2 on an HTTP 404 so callers can tell "it is not there" from "the API call failed",
# which otherwise both look like an empty answer and stall the release silently.
api() {
  local stderr status out
  stderr=$(mktemp)
  if out=$(gh api "$@" 2>"$stderr"); then
    rm -f "$stderr"
    printf '%s' "$out"
    return 0
  fi
  status=1
  grep -q 'HTTP 404' "$stderr" && status=2
  cat "$stderr" >&2
  rm -f "$stderr"
  return "$status"
}

STATUS=0
CONFIG=$(api "repos/$REPOSITORY/contents/$CONFIG_PATH" -H "Accept: application/vnd.github.raw") || STATUS=$?
if [ "$STATUS" -eq 2 ]; then
  # A token without contents:read gets 403 here, not 404, so a 404 really is a missing file.
  decide none "No $CONFIG_PATH on the default branch, so auto-retry is not configured for $REPOSITORY."
elif [ "$STATUS" -ne 0 ]; then
  echo "::error::Could not read $CONFIG_PATH from $REPOSITORY"
  exit 1
fi

CONFIG_JSON=$(yq -o=json '.' <<<"$CONFIG")

MAX_ATTEMPTS=$(jq -r '."max-attempts" // 3' <<<"$CONFIG_JSON")
if ! [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$MAX_ATTEMPTS" -lt 1 ]; then
  echo "::error::max-attempts in $CONFIG_PATH must be a positive whole number, found '$MAX_ATTEMPTS'"
  exit 1
fi

DENY=$(jq -r '."non-retryable-jobs"[]? // empty' <<<"$CONFIG_JSON")
if [ -z "$DENY" ]; then
  echo "::error::$CONFIG_PATH must list at least one entry under non-retryable-jobs"
  exit 1
fi

FAILED=$(api "repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate \
  --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name') || {
  echo "::error::Could not list the jobs of attempt $RUN_ATTEMPT of run $RUN_ID"
  exit 1
}

if [ -z "$FAILED" ]; then
  decide escalate "$REPOSITORY run $RUN_ID failed without any job reporting a failure, so re-running it would change nothing."
fi

# -F -x so a job matches a denylist entry only on the whole name, never as a substring.
BLOCKED=$(grep -Fx -f <(printf '%s\n' "$DENY") <<<"$FAILED") || BLOCKED=""
if [ -n "$BLOCKED" ]; then
  # jq quotes each name, so a job name that itself contains a comma stays readable.
  BLOCKED_LIST=$(printf '%s\n' "$BLOCKED" | jq -Rrs 'rtrimstr("\n") | split("\n") | map(tojson) | join(", ")')
  decide escalate "Not retrying $REPOSITORY run $RUN_ID: $BLOCKED_LIST must not be re-run automatically."
fi

# git/ref/heads is exact, where commits/<branch> would also match a tag of the same name.
# Reading the config above proved contents:read works, so a 404 here is a real deletion.
STATUS=0
TIP=$(api "repos/$REPOSITORY/git/ref/heads/$HEAD_BRANCH" --jq '.object.sha') || STATUS=$?
if [ "$STATUS" -eq 2 ]; then
  decide none "Branch $HEAD_BRANCH no longer exists, so run $RUN_ID has nothing left to release."
elif [ "$STATUS" -ne 0 ]; then
  echo "::error::Could not read branch $HEAD_BRANCH of $REPOSITORY"
  exit 1
fi
if [ "$TIP" != "$HEAD_SHA" ]; then
  decide none "Branch $HEAD_BRANCH moved to $TIP since $HEAD_SHA was built, so a newer run supersedes this one."
fi

if [ "$RUN_ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
  decide escalate "$REPOSITORY run $RUN_ID still failing after attempt $RUN_ATTEMPT of $MAX_ATTEMPTS, the retry budget is spent."
fi

decide retry "Attempt $RUN_ATTEMPT of $MAX_ATTEMPTS failed on retryable jobs only, re-running them."
