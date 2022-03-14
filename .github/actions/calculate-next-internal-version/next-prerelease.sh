#!/usr/bin/env bash
set -e

echo "Fetching tags ... "
git fetch --tags

PRERELEASE_LABEL="alpha"
FIRST_PRERELEASE_SUFFIX="-${PRERELEASE_LABEL}.1"

echo "Next version: $NEXT_VERSION"
LATEST_PRERELEASE="$(git tag --sort=-creatordate | grep -m 1  "^$NEXT_VERSION\-$PRERELEASE_LABEL\.[[:digit:]]\{1,4\}$" | cat)"
if [ -n "$LATEST_PRERELEASE" ]; then
  echo "Latest prerelease version found: $LATEST_PRERELEASE"
  NEXT_PRERELEASE="$(pysemver bump prerelease "$LATEST_PRERELEASE")"
else
  echo "No prerelease found for version $NEXT_VERSION yet"
  NEXT_PRERELEASE="$NEXT_VERSION$FIRST_PRERELEASE_SUFFIX"
fi
echo "Next prerelease: $NEXT_PRERELEASE"
echo "::set-output name=next-prerelease::$NEXT_PRERELEASE"
