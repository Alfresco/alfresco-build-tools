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

# Writes every output and ends the run. Only an escalation carries a code, because
# only a caller that has to word its own message needs to tell the cases apart.
decide() {
  local decision="$1" code="$2" text="$3"
  emit decision "$decision"
  emit reason-code "$code"
  emit reason-text "$text"
  emit attempt "$RUN_ATTEMPT"
  emit max-attempts "$MAX_ATTEMPTS"
  # Only an escalation has anything to compare, so a stale event or a plain retry skips the lookup.
  if [ "$decision" = "escalate" ]; then
    resolve_anchor
  fi
  emit last-successful-sha "$ANCHOR"
  local delim="EOF_${RANDOM}${RANDOM}"
  {
    echo "failed-jobs<<${delim}"
    [ -n "$FAILED" ] && printf '%s\n' "$FAILED"
    echo "$delim"
  } >> "$GITHUB_OUTPUT"
  echo "$text"
  # Every outcome lands in the job summary, so a decision not to retry is still visible.
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    echo "**$decision**: $text" >> "$GITHUB_STEP_SUMMARY"
  fi
  exit 0
}

# Returns 2 on an HTTP 404 so callers can tell "it is not there" from "the API call failed",
# which otherwise both look like an empty answer. A transient 5xx is not an answer either,
# so give the API a few tries before believing it.
api() {
  local stderr status out attempt=1
  stderr=$(mktemp)
  while :; do
    if out=$(gh api "$@" 2>"$stderr"); then
      rm -f "$stderr"
      printf '%s' "$out"
      return 0
    fi
    if [ "$attempt" -lt "${API_MAX_ATTEMPTS:-3}" ] && grep -qE 'HTTP 5[0-9][0-9]|Server Error' "$stderr"; then
      sleep $(( attempt * ${API_RETRY_DELAY:-2} ))
      attempt=$(( attempt + 1 ))
      continue
    fi
    status=1
    if grep -q 'HTTP 404' "$stderr"; then
      status=2
    fi
    cat "$stderr" >&2
    rm -f "$stderr"
    return "$status"
  done
}

# The newest green run of this workflow on this branch, which is where a caller starts working
# out what went into the release that is now stuck. Best effort: empty is a usable answer.
ANCHOR=""
resolve_anchor() {
  if [ -z "${WORKFLOW_ID:-}" ]; then
    echo "::warning::The event carries no workflow id, so last-successful-sha is empty"
    return 0
  fi
  ANCHOR=$(api "repos/$REPOSITORY/actions/workflows/$WORKFLOW_ID/runs?branch=${HEAD_BRANCH}&status=success&per_page=100" \
    --jq "[.workflow_runs[] | select(.run_number < ${RUN_NUMBER:-0}) | .head_sha] | first // empty") || ANCHOR=""
  # A branch releasing for the first time has no earlier success, which is not an error.
  [ -n "$ANCHOR" ] || echo "::warning::No earlier successful run of this workflow on $HEAD_BRANCH, so last-successful-sha is empty"
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

# gh run rerun acts on the run's latest attempt, so an event for an older attempt must not decide.
LIVE=$(api "repos/$REPOSITORY/actions/runs/$RUN_ID" --jq '"\(.run_attempt) \(.status)"') || {
  echo "::error::Could not read run $RUN_ID of $REPOSITORY"
  exit 1
}
read -r LIVE_ATTEMPT LIVE_STATUS <<<"$LIVE"
if [ "$LIVE_ATTEMPT" != "$RUN_ATTEMPT" ]; then
  decide none "" "Run $RUN_ID is already on attempt $LIVE_ATTEMPT, so this event for attempt $RUN_ATTEMPT is stale."
fi
if [ "$LIVE_STATUS" != "completed" ]; then
  decide none "" "Run $RUN_ID is $LIVE_STATUS again, so another retry is already under way."
fi

FAILED=$(api "repos/$REPOSITORY/actions/runs/$RUN_ID/attempts/$RUN_ATTEMPT/jobs" --paginate \
  --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name') || {
  echo "::error::Could not list the jobs of attempt $RUN_ATTEMPT of run $RUN_ID"
  exit 1
}

if [ -z "$FAILED" ]; then
  decide escalate nothing-to-retry "$REPOSITORY run $RUN_ID failed without any job reporting a failure, so re-running it would change nothing."
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
  decide escalate non-retryable "Not retrying $REPOSITORY run $RUN_ID: $BLOCKED_LIST must not be re-run automatically."
fi

# git/ref/heads is exact, where commits/<branch> would also match a tag of the same name.
STATUS=0
TIP=$(api "repos/$REPOSITORY/git/ref/heads/$HEAD_BRANCH" --jq '.object.sha') || STATUS=$?
if [ "$STATUS" -eq 2 ]; then
  decide none "" "Branch $HEAD_BRANCH no longer exists, so run $RUN_ID has nothing left to release."
elif [ "$STATUS" -ne 0 ]; then
  echo "::error::Could not read branch $HEAD_BRANCH of $REPOSITORY"
  exit 1
fi
if [ "$TIP" != "$HEAD_SHA" ]; then
  decide none "" "Branch $HEAD_BRANCH moved to $TIP since $HEAD_SHA was built, so a newer run supersedes this one."
fi

if [ "$RUN_ATTEMPT" -ge "$MAX_ATTEMPTS" ]; then
  decide escalate attempts-exhausted "$REPOSITORY run $RUN_ID still failing after attempt $RUN_ATTEMPT of $MAX_ATTEMPTS, the retry budget is spent."
fi

decide retry "" "Attempt $RUN_ATTEMPT of $MAX_ATTEMPTS failed on retryable jobs only, re-running them."
