#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

# Every fact on the card describes the run that failed, so without that event there is nothing to report.
if [ "${GITHUB_EVENT_NAME:-}" != "workflow_run" ]; then
  echo "::error::workflow-run-escalation-notification only works on a workflow_run event, found '${GITHUB_EVENT_NAME:-none}'"
  exit 1
fi

# Only the three escalating codes make sense here. Anything else is a wiring mistake
# in the caller, and failing loudly beats sending a card that explains nothing.
case "${REASON_CODE:-}" in
  attempts-exhausted)
    HEADLINE="Automated retries were exhausted." ;;
  non-retryable)
    HEADLINE="A job that must not be re-run automatically failed, so no retry was attempted." ;;
  nothing-to-retry)
    HEADLINE="The run failed without any job reporting a failure, so a retry would change nothing." ;;
  *)
    echo "::error::reason-code must be 'attempts-exhausted', 'non-retryable' or 'nothing-to-retry', found '${REASON_CODE:-}'"
    exit 1 ;;
esac

if ! [[ "${ATTEMPT:-}" =~ ^[0-9]+$ ]] || [ "$ATTEMPT" -lt 1 ]; then
  echo "::error::attempt must be a positive whole number, found '${ATTEMPT:-}'"
  exit 1
fi

RETRIES=$((ATTEMPT - 1))
case "$RETRIES" in
  0) ATTEMPTS="1 total (no automated retries)" ;;
  1) ATTEMPTS="$ATTEMPT total (1 original + 1 automated retry)" ;;
  *) ATTEMPTS="$ATTEMPT total (1 original + $RETRIES automated retries)" ;;
esac

# One bullet per job so the list stays readable past the two or three a FactSet row can hold.
JOBS=$(printf '%s\n' "${FAILED_JOBS:-}" | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d; s/^/- /')
[ -n "$JOBS" ] || JOBS="- none reported"

# These defaults live here rather than in action.yml so there is one copy to keep right.
BODY=$(jq -n -c \
  --arg heading "${HEADING:-Release chain blocked}" \
  --arg position "${POSITION:-}" \
  --arg message "$(printf '%s %s' "$HEADLINE" "${DOWNSTREAM:-}" | sed 's/[[:space:]]*$//')" \
  --arg repository "${REPOSITORY:-}" \
  --arg branch "${BRANCH:-}" \
  --arg workflow "${WORKFLOW:-}" \
  --arg attempts "$ATTEMPTS" \
  --arg upstream "${UPSTREAM_VERSION:-Unknown}" \
  --arg jobs "$JOBS" \
  --arg cc "${CC:-}" \
  '[
    {type: "ColumnSet", columns: [
      {type: "Column", width: "auto", items: [
        {type: "TextBlock", text: "🔴", size: "large", spacing: "none"}]},
      {type: "Column", width: "stretch", items: (
        [{type: "TextBlock", text: $heading, size: "large", weight: "bolder", wrap: true, spacing: "none"}]
        + (if $position == "" then []
           else [{type: "TextBlock", text: $position, isSubtle: true, wrap: true, spacing: "none"}] end))}]},
    {type: "TextBlock", spacing: "medium", wrap: true, text: $message},
    {type: "FactSet", spacing: "medium", facts: [
      {title: "Repository", value: $repository},
      {title: "Branch", value: $branch},
      {title: "Workflow", value: $workflow},
      {title: "Attempts", value: $attempts},
      {title: "Upstream version", value: $upstream}]},
    {type: "Container", spacing: "medium", items: [
      {type: "TextBlock", text: "Failed jobs", weight: "bolder", spacing: "none"},
      {type: "TextBlock", wrap: true, spacing: "small", text: $jobs}]}
  ]
  + (if $cc == "" then []
     else [{type: "TextBlock", spacing: "medium", wrap: true, isSubtle: true, text: $cc}] end)')

echo "body=$BODY" >> "$GITHUB_OUTPUT"
