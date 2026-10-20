#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

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
  exit 0
}

CONFIG=$(gh api "repos/$REPOSITORY/contents/$CONFIG_PATH" -H "Accept: application/vnd.github.raw" 2>/dev/null) || CONFIG=""
if [ -z "$CONFIG" ]; then
  decide none "No $CONFIG_PATH on the default branch, so auto-retry is not configured for $REPOSITORY."
fi

# yq only converts to JSON; jq does the reading, because a hyphenated key is awkward to address in yq.
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

FAILED=$(gh api "repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate \
  --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name') || {
  echo "::error::Could not list the jobs of attempt $RUN_ATTEMPT of run $RUN_ID"
  exit 1
}

if [ -z "$FAILED" ]; then
  decide none "Run $RUN_ID failed without any job reporting a failure, so there is nothing to re-run."
fi

# -F -x so a job matches a denylist entry only on the whole name, never as a substring.
BLOCKED=$(grep -Fx -f <(printf '%s\n' "$DENY") <<<"$FAILED") || BLOCKED=""
if [ -n "$BLOCKED" ]; then
  decide escalate "Not retrying $REPOSITORY run $RUN_ID: $(printf '%s' "$BLOCKED" | paste -sd, - | sed 's/,/, /g') must not be re-run automatically."
fi

TIP=$(gh api "repos/$REPOSITORY/commits/$HEAD_BRANCH" --jq '.sha' 2>/dev/null) || TIP=""
if [ -z "$TIP" ]; then
  decide none "Branch $HEAD_BRANCH no longer exists, so run $RUN_ID has nothing left to release."
fi
if [ "$TIP" != "$HEAD_SHA" ]; then
  decide none "Branch $HEAD_BRANCH moved to $TIP since $HEAD_SHA was built, so a newer run supersedes this one."
fi

if [ "$RUN_ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
  decide escalate "$REPOSITORY run $RUN_ID still failing after attempt $RUN_ATTEMPT of $MAX_ATTEMPTS, the retry budget is spent."
fi

decide retry "Attempt $RUN_ATTEMPT of $MAX_ATTEMPTS failed on retryable jobs only, re-running them."
