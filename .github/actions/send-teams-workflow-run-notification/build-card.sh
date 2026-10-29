#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

# Every fact on the card comes from the workflow_run event.
if [ "${GITHUB_EVENT_NAME:-}" != "workflow_run" ]; then
  echo "::error::send-teams-workflow-run-notification only works on a workflow_run event, found '${GITHUB_EVENT_NAME:-none}'"
  exit 1
fi

# Any other code is a caller wiring mistake; fail rather than send a card that explains nothing.
case "${REASON_CODE:-}" in
  attempts-exhausted)
    HEADLINE="Automated retries were exhausted." ;;
  non-retryable)
    HEADLINE="A job that must not be re-run automatically failed, so no retry was attempted." ;;
  nothing-to-retry)
    HEADLINE="The run failed without any job reporting a failure, so a retry would change nothing." ;;
  "")
    HEADLINE=""
    if [ -z "${MESSAGE:-}" ]; then
      echo "::error::reason-code or message is required, so the card says why the run needs attention"
      exit 1
    fi ;;
  *)
    echo "::error::reason-code must be 'attempts-exhausted', 'non-retryable', 'nothing-to-retry' or empty, found '${REASON_CODE}'"
    exit 1 ;;
esac

if ! [[ "${ATTEMPT:-}" =~ ^[0-9]+$ ]] || [ "$ATTEMPT" -lt 1 ]; then
  echo "::error::attempt must be a positive whole number, found '${ATTEMPT:-}'"
  exit 1
fi

# A manual re-run bumps run_attempt too, so the card reports the number rather than
# claiming how many of the attempts were automated.
if [[ "${MAX_ATTEMPTS:-}" =~ ^[0-9]+$ ]] && [ "$MAX_ATTEMPTS" -ge 1 ]; then
  ATTEMPTS="$ATTEMPT of $MAX_ATTEMPTS"
else
  ATTEMPTS="$ATTEMPT"
fi

while IFS= read -r FACT; do
  if [ -n "${FACT//[[:space:]]/}" ] && [[ "$FACT" != *"|"* ]]; then
    echo "::error::facts entry '$FACT' must be in the format \"title|value\""
    exit 1
  fi
done <<<"${FACTS:-}"

BODY=$(jq -n -c -f "$(dirname "$0")/card.jq" \
  --arg title "${TITLE:-}" \
  --arg subtitle "${SUBTITLE:-}" \
  --arg headline "$HEADLINE" \
  --arg message "${MESSAGE:-}" \
  --arg repository "${REPOSITORY:-}" \
  --arg branch "${BRANCH:-}" \
  --arg workflow "${WORKFLOW:-}" \
  --arg attempts "$ATTEMPTS" \
  --arg facts "${FACTS:-}" \
  --arg failed_jobs "${FAILED_JOBS:-}" \
  --arg footer "${FOOTER:-}")

echo "body=$BODY" >> "$GITHUB_OUTPUT"
