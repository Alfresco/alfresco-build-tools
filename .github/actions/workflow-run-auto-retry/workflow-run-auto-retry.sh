#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

if [ "${GITHUB_EVENT_NAME:-}" != "workflow_run" ]; then
  echo "::error::This action only works on a workflow_run event, not on ${GITHUB_EVENT_NAME:-an unknown event}"
  exit 1
fi

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

MAX_ATTEMPTS="${MAX_ATTEMPTS:-}"
[ -n "$MAX_ATTEMPTS" ] || MAX_ATTEMPTS=3
if ! [[ "$MAX_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$MAX_ATTEMPTS" -lt 1 ]; then
  echo "::error::max-attempts must be a positive whole number, found '$MAX_ATTEMPTS'"
  exit 1
fi

# One job name per line, with blank lines and stray indentation from the YAML block ignored.
# Leaving it empty means nothing is off limits, which is what a pull request watcher wants.
DENY=$(printf '%s\n' "${NON_RETRYABLE_JOBS:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | sed '/^$/d')

FAILED=$(api "repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate \
  --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name') || {
  echo "::error::Could not list the jobs of attempt $RUN_ATTEMPT of run $RUN_ID"
  exit 1
}

if [ -z "$FAILED" ]; then
  decide escalate "$REPOSITORY run $RUN_ID failed without any job reporting a failure, so re-running it would change nothing."
fi

# -F -x so a job matches a denylist entry only on the whole name, never as a substring.
# An empty denylist is skipped, because an empty pattern line would match every job.
BLOCKED=""
if [ -n "$DENY" ]; then
  BLOCKED=$(grep -Fx -f <(printf '%s\n' "$DENY") <<<"$FAILED") || BLOCKED=""
fi
if [ -n "$BLOCKED" ]; then
  # jq quotes each name, so a job name that itself contains a comma stays readable.
  BLOCKED_LIST=$(printf '%s\n' "$BLOCKED" | jq -Rrs 'rtrimstr("\n") | split("\n") | map(tojson) | join(", ")')
  decide escalate "Not retrying $REPOSITORY run $RUN_ID: $BLOCKED_LIST must not be re-run automatically."
fi

# git/ref/heads is exact, where commits/<branch> would also match a tag of the same name.
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
