#!/bin/bash
set -euo pipefail

MIN_CHARS="${MIN_CHARS:-15}"
MIN_WORDS="${MIN_WORDS:-3}"
SKIP_AUTHORS="${SKIP_AUTHORS:-}"
SKIP_BRANCHES="${SKIP_BRANCHES:-}"
PR_BODY="${PR_BODY:-}"
PR_AUTHOR="${PR_AUTHOR:-}"
PR_DRAFT="${PR_DRAFT:-}"
PR_BRANCH="${PR_BRANCH:-}"

if [ "${PR_DRAFT}" = "true" ]; then
  echo "Skipping draft PR."
  exit 0
fi

skip=false
case "${PR_AUTHOR}" in
  *"[bot]") skip=true ;;
esac

# Disable pathname expansion so skip-authors / skip-branches patterns
# (e.g. alfresco-build*, dependabot/*) are matched literally by case and
# are not expanded against the workspace.
set -f
for pattern in ${SKIP_AUTHORS}; do
  # shellcheck disable=SC2254
  case "${PR_AUTHOR}" in
    ${pattern}) skip=true ;;
  esac
done
for pattern in ${SKIP_BRANCHES}; do
  # shellcheck disable=SC2254
  case "${PR_BRANCH}" in
    ${pattern}) skip=true ;;
  esac
done
set +f

if [ "${skip}" = "true" ]; then
  echo "Skipping automated PR (author=${PR_AUTHOR}, branch=${PR_BRANCH})."
  exit 0
fi

if ! printf '%s' "${MIN_CHARS}" | grep -Eq '^[0-9]+$'; then
  echo "::error title=Invalid min-chars::min-chars must be a non-negative integer, got '${MIN_CHARS}'."
  exit 1
fi
if ! printf '%s' "${MIN_WORDS}" | grep -Eq '^[0-9]+$'; then
  echo "::error title=Invalid min-words::min-words must be a non-negative integer, got '${MIN_WORDS}'."
  exit 1
fi

# Remove PR-template HTML comments first.
body=$(printf '%s' "${PR_BODY}" | perl -0777 -pe 's/<!--.*?-->//gs')

# Any non-whitespace content at all? Distinguishes empty from link-only.
raw=$(printf '%s' "${body}" | tr -d '[:space:]')

# Meaningful prose: keep Markdown link text but drop the URL target,
# drop autolinks and bare URLs, drop Jira ticket keys (e.g. AAE-1234),
# then collapse whitespace and trim.
meaningful=$(printf '%s' "${body}" | perl -0777 -pe '
  s/\[([^\]]*)\]\([^)]*\)/$1/g;
  s/<https?:\/\/[^>]*>//g;
  s{https?://\S+}{}g;
  s/\b[A-Z][A-Z0-9]+-\d+\b//g;
  s/[[:space:]]+/ /g;
  s/^\s+//;
  s/\s+$//;
')

chars=$(printf '%s' "${meaningful}" | wc -m | tr -d ' ')
words=$(printf '%s' "${meaningful}" | wc -w | tr -d ' ')
echo "Meaningful description: ${chars} characters (min ${MIN_CHARS}), ${words} words (min ${MIN_WORDS})."

if [ -z "${meaningful}" ]; then
  if [ -n "${raw}" ]; then
    echo "::error title=PR description is only a link::A bare Jira ticket reference or URL is not a description. Add a sentence describing what changed and why."
  else
    echo "::error title=PR description is empty::Add a description of what changed and why."
  fi
  exit 1
fi

if [ "${chars}" -lt "${MIN_CHARS}" ]; then
  echo "::error title=PR description too short::The description has ${chars} meaningful characters (links and ticket references are excluded); at least ${MIN_CHARS} are required. Describe what changed and why."
  exit 1
fi

if [ "${words}" -lt "${MIN_WORDS}" ]; then
  echo "::error title=PR description too short::The description has ${words} meaningful words (links and ticket references are excluded); at least ${MIN_WORDS} are required. Describe what changed and why."
  exit 1
fi
