#!/bin/bash
set -eo pipefail

# The branch name is read from the event payload and only ever compared or passed
# as data, never interpolated into a command: it is controlled by the PR author.

trim() {
  local value=$1
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

write_labels_output() {
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    printf 'labels=%s\n' "$(jq -cn '$ARGS.positional' --args "$@")" >> "$GITHUB_OUTPUT"
  fi
}

if [ "${GITHUB_EVENT_NAME:-}" != "pull_request" ]; then
  echo "::error::This action only supports the pull_request event, got '${GITHUB_EVENT_NAME:-}'"
  exit 1
fi

event_path=${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is not set}
pr_number=$(jq -r '.pull_request.number // empty' "$event_path")
branch=$(jq -r '.pull_request.head.ref // empty' "$event_path")
head_repo=$(jq -r '.pull_request.head.repo.full_name // empty' "$event_path")
author=$(jq -r '.pull_request.user.login // empty' "$event_path")

if ! [[ "$pr_number" =~ ^[0-9]+$ ]] || [ -z "$branch" ]; then
  echo "::error::Pull request number or branch name missing from the event payload"
  exit 1
fi

# Validate the whole mapping before deciding whether to skip, so a broken
# configuration is reported on every pull request rather than only on some.
prefixes=()
mapped_labels=()
line_number=0
while IFS= read -r line || [ -n "$line" ]; do
  line_number=$((line_number + 1))
  line=$(trim "$line")
  if [ -z "$line" ] || [[ "$line" == \#* ]]; then
    continue
  fi
  if [[ "$line" != *:* ]]; then
    echo "::error::Invalid mapping on line $line_number, expected '<branch-prefix>: <label>': $line"
    exit 1
  fi
  prefix=$(trim "${line%%:*}")
  label=$(trim "${line#*:}")
  if [ -z "$prefix" ] || [ -z "$label" ]; then
    echo "::error::Invalid mapping on line $line_number, prefix and label are required: $line"
    exit 1
  fi
  prefixes+=("$prefix")
  mapped_labels+=("$label")
done <<< "${MAPPING:-}"

if [ "${#prefixes[@]}" -eq 0 ]; then
  echo "::error::The mapping is empty"
  exit 1
fi

# Fork and Dependabot pull requests only get a read-only token, so labeling them
# would fail anyway.
if [ "$head_repo" != "$GITHUB_REPOSITORY" ]; then
  echo "::notice::Skipping pull request from fork '${head_repo:-unknown}'"
  write_labels_output
  exit 0
fi

if [ "$author" = "dependabot[bot]" ]; then
  echo "::notice::Skipping Dependabot pull request"
  write_labels_output
  exit 0
fi

wanted=()
for i in "${!prefixes[@]}"; do
  if [[ "$branch" == "${prefixes[$i]}"* ]]; then
    wanted+=("${mapped_labels[$i]}")
  fi
done

if [ "${#wanted[@]}" -eq 0 ]; then
  echo "::notice::No label mapped to branch '$branch'"
  write_labels_output
  exit 0
fi

# Adding a label that does not exist would create it, so only existing labels are
# applied. Label names are case-insensitive on GitHub.
if ! repo_labels=$(gh api --paginate "repos/$GITHUB_REPOSITORY/labels?per_page=100" --jq '.[].name'); then
  echo "::error::Failed to list the labels of $GITHUB_REPOSITORY"
  exit 1
fi

to_apply=()
for label in "${wanted[@]}"; do
  match=""
  while IFS= read -r repo_label; do
    if [ "${repo_label,,}" = "${label,,}" ]; then
      match=$repo_label
      break
    fi
  done <<< "$repo_labels"
  if [ -z "$match" ]; then
    echo "::warning::Label '$label' does not exist in $GITHUB_REPOSITORY, create it to apply it automatically"
    continue
  fi
  duplicate=false
  for applied in "${to_apply[@]}"; do
    if [ "$applied" = "$match" ]; then
      duplicate=true
    fi
  done
  if [ "$duplicate" = false ]; then
    to_apply+=("$match")
  fi
done

if [ "${#to_apply[@]}" -eq 0 ]; then
  write_labels_output
  exit 0
fi

if ! jq -n '{labels: $ARGS.positional}' --args "${to_apply[@]}" |
  gh api --method POST "repos/$GITHUB_REPOSITORY/issues/$pr_number/labels" --input - --silent; then
  echo "::error::Failed to label pull request #$pr_number, check the job grants 'pull-requests: write'"
  exit 1
fi

echo "Applied labels to pull request #$pr_number: ${to_apply[*]}"
write_labels_output "${to_apply[@]}"
