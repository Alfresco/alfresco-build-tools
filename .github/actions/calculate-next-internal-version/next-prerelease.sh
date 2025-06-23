#!/usr/bin/env bash
set -euo pipefail

: "${NEXT_VERSION:?}"
: "${PRERELEASE_TYPE:?}"
: "${GITHUB_REPOSITORY:?}"
: "${GITHUB_TOKEN:?}"

API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/tags"
PER_PAGE=100
PAGE=1
MATCHING_TAG=""
echo "::group::Fetching tags from GitHub API"

while true; do
  response=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
    "${API_URL}?per_page=${PER_PAGE}&page=${PAGE}")

  tag_names=$(echo "$response" | jq -r '.[].name')
  if [[ -z "$tag_names" || "$tag_names" == "null" ]]; then
    break
  fi

  for tag in $tag_names; do
    if [[ "$tag" =~ ^${NEXT_VERSION}-${PRERELEASE_TYPE}\.[0-9]+$ ]]; then
      echo "Matched: $tag"
      MATCHING_TAG="$tag"
      break 2
    fi
  done

  PAGE=$((PAGE + 1))
done
echo "::endgroup::"

if [[ -n "$MATCHING_TAG" ]]; then
  echo "Found latest matching prerelease tag: $MATCHING_TAG"
  NEXT_PRERELEASE=$(pysemver bump prerelease "$MATCHING_TAG")
else
  echo "No prerelease found, starting at .1"
  NEXT_PRERELEASE="${NEXT_VERSION}-${PRERELEASE_TYPE}.1"
fi

echo "Resolved next prerelease version: $NEXT_PRERELEASE"
echo "next-prerelease=$NEXT_PRERELEASE" >> "$GITHUB_OUTPUT"
