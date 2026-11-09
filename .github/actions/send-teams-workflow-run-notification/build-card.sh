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

# A bullet list with one bullet per job
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

# One entry per line, so the rest of the script never has to think about the comma form.
csv_lines() { printf '%s\n' "${1:-}" | tr ',' '\n' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; /^$/d'; }

# An entry carrying an email is somebody Teams can mention, a bare one is shown as written.
# That is the same rule the mention list downstream already goes by.
CC_TEXT=""
CC_USERS=""
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
while IFS= read -r ENTRY; do
  SHOWN="$ENTRY"
  if [[ "$ENTRY" == *"|"* ]]; then
    NAME="${ENTRY%|*}"
    ID="${ENTRY#*|}"
    if [ -n "$NAME" ] && [ -n "$ID" ]; then
      CC_TEXT="${CC_TEXT}${CC_TEXT:+, }<at>${NAME}</at>"
      CC_USERS="${CC_USERS}${ENTRY}"$'\n'
      continue
    fi
    # Fallback to plaintext if not `name|id`
    echo "::warning::cc entry '$ENTRY' is not \"display name|email\", showing it as plain text"
    SHOWN="${NAME:-$ID}"
  fi
  [ -n "$SHOWN" ] || continue
  # Escaped like the job names for markdown
  SHOWN_MD=$(printf '%s' "$SHOWN" | sed -E 's/\\/\\\\/g; s/[][*`_]/\\&/g')
  # Only a handle has a profile to point at, so a bare display name is left as text.
  if [[ "$SHOWN" =~ ^@[A-Za-z0-9-]+$ ]]; then
    SHOWN_MD="[${SHOWN_MD}](${SERVER}/${SHOWN#@})"
  fi
  CC_TEXT="${CC_TEXT}${CC_TEXT:+, }${SHOWN_MD}"
# Remove duplicate entries
done < <(csv_lines "${CC:-}" | awk '!seen[$0]++')

[ -z "$CC_TEXT" ] || CC_TEXT="cc: $CC_TEXT"

# Everyone mentioned on the cc line needs an entity too, or Teams renders the <at> as text.
MENTIONS=$(printf '%s\n%s' "$(csv_lines "${MENTION_USERS:-}")" "$CC_USERS" \
  | sed '/^$/d' | awk '!seen[$0]++' | paste -sd, -)

EXTRA=$(jq -n -c \
  --arg attempts "$ATTEMPTS" \
  --arg cc "$CC_TEXT" \
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
   + (if $cc == "" then []
      else [{type: "TextBlock", spacing: "medium", wrap: true, text: $cc}] end)
   + (if $footer == "" then []
      else [{type: "TextBlock", spacing: "medium", wrap: true, isSubtle: true, text: $footer}] end)')

{
  echo "title=$CARD_TITLE"
  delim="EOF_${RANDOM}${RANDOM}"
  echo "message<<${delim}"
  printf '%s\n' "$BODY"
  echo "$delim"
  echo "extra-body=$EXTRA"
  echo "mention-users=$MENTIONS"
} >> "$GITHUB_OUTPUT"
