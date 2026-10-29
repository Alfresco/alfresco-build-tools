#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"

# Every fact on the card describes the run that failed, so without that event there is nothing to report.
if [ "${GITHUB_EVENT_NAME:-}" != "workflow_run" ]; then
  echo "::error::send-teams-workflow-run-notification only works on a workflow_run event, found '${GITHUB_EVENT_NAME:-none}'"
  exit 1
fi

# The code supplies the first sentence. A caller not using workflow-run-auto-retry
# leaves it empty and words the whole message itself.
case "${REASON_CODE:-}" in
  attempts-exhausted)  HEADLINE="Automated retries were exhausted." ;;
  non-retryable)       HEADLINE="A job that must not be re-run automatically failed, so no retry was attempted." ;;
  nothing-to-retry)    HEADLINE="The run failed without any job reporting a failure, so a retry would change nothing." ;;
  "")
    HEADLINE=""
    if [ -z "${MESSAGE:-}" ]; then
      echo "::error::reason-code or message is required, so the card says why the run needs attention"
      exit 1
    fi ;;
  *) echo "::error::reason-code must be 'attempts-exhausted', 'non-retryable', 'nothing-to-retry' or empty, found '${REASON_CODE}'"; exit 1 ;;
esac

# The event always carries this, so an unusable value means the caller rewired it by hand.
if ! [[ "${ATTEMPT:-}" =~ ^[0-9]+$ ]] || [ "$ATTEMPT" -lt 1 ]; then
  echo "::error::attempt must be a positive whole number, found '${ATTEMPT:-}'"
  exit 1
fi

CARD_TITLE="🔴 ${TITLE:-Workflow run failed}"
[ -n "${BRANCH:-}" ] && CARD_TITLE="$CARD_TITLE on \`${BRANCH}\`"

BODY=$(printf '%s %s' "$HEADLINE" "${MESSAGE:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
# The subtitle reads as a first line above the explanation rather than a separate block.
[ -n "${SUBTITLE:-}" ] && BODY="${SUBTITLE}

${BODY}"

ATTEMPTS="$ATTEMPT"
if [[ "${MAX_ATTEMPTS:-}" =~ ^[0-9]+$ ]] && [ "$MAX_ATTEMPTS" -ge 1 ]; then
  ATTEMPTS="$ATTEMPT of $MAX_ATTEMPTS"
fi

# One bullet per job so the list stays readable past the two or three a FactSet row can hold.
JOBS=$(printf '%s\n' "${FAILED_JOBS:-}" \
  | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d; s/\\/\\\\/g; s/[][*`_]/\\&/g; s/^/- /')
[ -n "$JOBS" ] || JOBS="- none reported"

# Caught here rather than in jq so the caller is told which line is wrong.
while IFS= read -r FACT; do
  if [ -n "${FACT//[[:space:]]/}" ] && [[ "$FACT" != *"|"* ]]; then
    echo "::error::facts entry '$FACT' must be in the format \"title|value\""
    exit 1
  fi
done <<<"${FACTS:-}"

EXTRA=$(jq -n -c \
  --arg attempts "$ATTEMPTS" \
  --arg facts "${FACTS:-}" \
  --arg jobs "$JOBS" \
  --arg footer "${FOOTER:-}" \
  'def trim: gsub("^\\s+|\\s+$"; "");
   # A value keeps any further separators, so "repo, share|community" stays intact.
   ($facts | split("\n") | map(trim) | map(select(. != ""))
     | map(split("|") | {title: (.[0] | trim), value: (.[1:] | join("|") | trim)})) as $extra_facts
   | [{type: "FactSet", spacing: "medium", facts: ([{title: "Attempt", value: $attempts}] + $extra_facts)},
      {type: "Container", spacing: "medium", items: [
         {type: "TextBlock", text: "Failed jobs", weight: "bolder", spacing: "none"},
         {type: "TextBlock", wrap: true, spacing: "small", text: $jobs}]}]
   + (if $footer == "" then []
      else [{type: "TextBlock", spacing: "medium", wrap: true, isSubtle: true, text: $footer}] end)')

{
  echo "title=$CARD_TITLE"
  delim="EOF_${RANDOM}${RANDOM}"
  echo "message<<${delim}"
  printf '%s\n' "$BODY"
  echo "$delim"
  echo "extra-body=$EXTRA"
} >> "$GITHUB_OUTPUT"
