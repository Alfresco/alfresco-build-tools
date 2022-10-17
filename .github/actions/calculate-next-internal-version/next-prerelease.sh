#!/usr/bin/env bash
set -e

if [ -n "$REPO_DIR" ]
then
  cd "$REPO_DIR"
fi

echo "Fetching tags ... "
git fetch --tags

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
echo "Next prerelease: $NEXT_PRERELEASE"
echo "next-prerelease=$NEXT_PRERELEASE" >> $GITHUB_OUTPUT
