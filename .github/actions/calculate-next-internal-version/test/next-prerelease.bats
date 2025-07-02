#!/usr/bin/env bash
set -euo pipefail

: "${NEXT_VERSION:?}"
: "${PRERELEASE_TYPE:?}"
: "${GITHUB_TOKEN:?Missing GITHUB_TOKEN}"

GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
if [[ -z "$GITHUB_REPOSITORY" ]]; then
  echo "GITHUB_REPOSITORY is not set"
  exit 1
fi

PER_PAGE=100
PAGE=1
MATCHING_TAGS=()

escaped_prerelease_type=$(printf '%s\n' "$PRERELEASE_TYPE" | sed 's/[][\\.^$*+?/{}|]/\\&/g')

echo "::group::Fetching tags from GitHub API"
while true; do
  response=$(curl -s -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/repos/${GITHUB_REPOSITORY}/tags?per_page=${PER_PAGE}&page=${PAGE}")

  tag_names=$(echo "$response" | jq -r '.[].name' | sed '/^$/d')
  if [[ -z "$tag_names" || "$tag_names" == "null" ]]; then
    break
  fi

  while IFS= read -r tag; do
    [[ -z "$tag" ]] && continue
    if [[ "$tag" =~ ^${NEXT_VERSION}-${escaped_prerelease_type}\.([0-9]+)$ ]]; then
      echo "Matched: $tag"
      MATCHING_TAGS+=("$tag")
    fi
  done <<< "$tag_names"

  count=$(echo "$tag_names" | grep -c . || true)
  if (( count < PER_PAGE )); then
    break
  fi

  PAGE=$((PAGE + 1))
done
echo "::endgroup::"

if [[ ${#MATCHING_TAGS[@]} -gt 0 ]]; then
  highest_num=$(printf "%s\n" "${MATCHING_TAGS[@]}" | sed -nE "s/^.*\.([0-9]+)$/\1/p" | sort -n | tail -1)
  latest_tag=$(printf "%s\n" "${MATCHING_TAGS[@]}" | grep -E "\.${highest_num}$" | head -1)
  if [[ -n "$latest_tag" ]]; then
    echo "Found latest matching prerelease tag: $latest_tag"
  fi
  if [[ -n "$highest_num" ]]; then
    next_num=$((highest_num + 1))
  else
    next_num=1
  fi
  NEXT_PRERELEASE="${NEXT_VERSION}-${PRERELEASE_TYPE}.${next_num}"
else
  echo "No prerelease found, starting at .1"
  NEXT_PRERELEASE="${NEXT_VERSION}-${PRERELEASE_TYPE}.1"
fi

echo "Resolved next prerelease version: $NEXT_PRERELEASE"
echo "next-prerelease=$NEXT_PRERELEASE" >> "$GITHUB_OUTPUT"
