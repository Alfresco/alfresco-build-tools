#!/usr/bin/env bash
set -euo pipefail

: "${NEXT_VERSION:?}"
: "${PRERELEASE_TYPE:?}"

MATCHING_TAG=""
NEXT_PRERELEASE=""

# Strategy 1: GitHub API (preferred if token is available)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  echo "::group::Fetching tags via GitHub API"
  : "${GITHUB_REPOSITORY:?}"

  API_URL="https://api.github.com/repos/${GITHUB_REPOSITORY}/tags"
  PER_PAGE=100
  PAGE=1

  while true; do
    response=$(curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" \
      "${API_URL}?per_page=${PER_PAGE}&page=${PAGE}")

    tag_names=$(echo "$response" | jq -r '.[].name')
    if [[ -z "$tag_names" || "$tag_names" == "null" ]]; then
      break
    fi

    for tag in $tag_names; do
      if [[ "$tag" =~ ^${NEXT_VERSION}-${PRERELEASE_TYPE}\.[0-9]+$ ]]; then
        if [[ -z "$MATCHING_TAG" || "$tag" > "$MATCHING_TAG" ]]; then
          MATCHING_TAG="$tag"
        fi
      fi
    done

    PAGE=$((PAGE + 1))
  done
  echo "::endgroup::"

# Strategy 2: Fallback to git
else
  echo "::warning::GITHUB_TOKEN not provided. Falling back to git fetch and local tag search..."
  cd "${REPO_DIR:-.}"
  git fetch --tags --no-recurse-submodules --quiet

  FIRST_PRERELEASE_SUFFIX="-${PRERELEASE_TYPE}.1"
  echo "Next version: $NEXT_VERSION"
  LATEST_PRERELEASE="$(git tag --sort=-creatordate | grep -m 1  "^$NEXT_VERSION\-$PRERELEASE_TYPE\.[[:digit:]]\{1,4\}$" | cat)"
  if [ -n "$LATEST_PRERELEASE" ]; then
    echo "Latest prerelease version found: $LATEST_PRERELEASE"
    NEXT_PRERELEASE="$(pysemver bump prerelease "$LATEST_PRERELEASE")"
  else
    echo "No prerelease found for version $NEXT_VERSION yet"
    NEXT_PRERELEASE="$NEXT_VERSION$FIRST_PRERELEASE_SUFFIX"
  fi
fi

echo "Resolved next prerelease version: $NEXT_PRERELEASE"
echo "next-prerelease=$NEXT_PRERELEASE" >> "$GITHUB_OUTPUT"
