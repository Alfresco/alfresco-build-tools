#!/bin/bash
set -eo pipefail

# Strip any URL prefix/suffix so "https://github.com/owner/repo.git", "owner/repo/"
# and "owner/repo" all resolve alike, then drop blanks and duplicates.
normalize_repos() {
  sed -e 's|^https\{0,1\}://[^/]*/||' -e 's|\.git$||' -e 's|/*$||' |
    awk 'NF && !seen[$0]++'
}

# Resolve the downstream repositories, either from the explicit input or from the
# updatebot config. Deriving them from the config is preferred: the propagation
# targets are declared there already, and a cleanup list maintained separately
# silently goes stale when a target is added.
if [ -n "${DOWNSTREAM_REPOS//[[:space:]]/}" ]; then
  resolved=$(printf '%s\n' "$DOWNSTREAM_REPOS" | tr ',[:space:]' '\n' | normalize_repos)
elif [ -f "$UPDATEBOT_CONFIG" ]; then
  resolved=$(yq -r '.spec.rules[].urls[]' "$UPDATEBOT_CONFIG" | normalize_repos)
else
  echo "::error::No downstream-repos given and $UPDATEBOT_CONFIG not found." \
    "Check out the repository first, set updatebot-config, or pass downstream-repos."
  exit 1
fi

# Fed by here-string rather than a pipe so the last entry is not lost when the
# input has no trailing newline, and with `if` rather than `&&` so a falsy test
# on the final iteration does not trip `set -e`.
repos=()
while IFS= read -r repo; do
  if [ -n "$repo" ]; then
    repos+=("$repo")
  fi
done <<< "$resolved"

if [ "${#repos[@]}" -eq 0 ]; then
  echo "::error::No downstream repositories resolved"
  exit 1
fi

source_label="${LABEL_PREFIX}${SOURCE_PR_NUMBER}"
source_repo_name="${SOURCE_REPO_NAME:-${GITHUB_REPOSITORY##*/}}"
if [ "$SOURCE_PR_STATE" = "MERGED" ]; then
  close_reason=merged
else
  close_reason=closed
fi

# Collected rather than fatal, so one unreachable repository doesn't leave the
# remaining ones uncleaned. The step still fails at the end.
failed=0
closed_count=0

for repo in "${repos[@]}"; do
  echo "Looking for open PRs labelled '$source_label' in $repo..."
  if ! pr_numbers=$(gh pr list \
    --repo "$repo" \
    --label "$source_label" \
    --state open \
    --json number \
    --jq '.[].number'); then
    echo "::warning::Failed to list open preview PRs in $repo"
    failed=1
    continue
  fi

  if [ -z "$pr_numbers" ]; then
    echo "No open preview PRs found in $repo"
    continue
  fi

  for pr in $pr_numbers; do
    echo "Closing PR #$pr in $repo"
    if ! gh pr close "$pr" \
      --repo "$repo" \
      --comment "Automatically closed: source PR #${SOURCE_PR_NUMBER} in ${source_repo_name} was ${close_reason}."; then
      echo "::warning::Failed to close PR #$pr in $repo"
      failed=1
    else
      closed_count=$((closed_count + 1))
    fi
  done
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    printf 'downstream-repos=%s\n' "${repos[*]}"
    printf 'closed-count=%s\n' "$closed_count"
  } >> "$GITHUB_OUTPUT"
fi

exit "$failed"
