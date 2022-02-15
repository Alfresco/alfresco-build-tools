#!/usr/bin/env bash
set -e

CURRENT_YEAR=$(date +%y)
echo "Year: $CURRENT_YEAR"
LATEST_MINOR=$(git tag --sort=-creatordate | grep -m 1  "^$CURRENT_YEAR\.[[:digit:]]\{1,2\}\.[[:digit:]]\{1,2\}$" | cat)
PRERELEASE_LABEL="alpha"
FIRST_PRERELEASE_SUFFIX="-${PRERELEASE_LABEL}.1"

if [ -n  "$LATEST_MINOR" ]; then
  echo "Latest minor version found: $LATEST_MINOR"
  NEXT_MINOR="$(pysemver bump minor "$LATEST_MINOR")"
  echo "Next minor: $NEXT_MINOR"
  LATEST_PRERELEASE="$(git tag --sort=-creatordate | grep -m 1  "^$NEXT_MINOR\-$PRERELEASE_LABEL\.[[:digit:]]\{1,4\}$" | cat)"
  if [ -n "$LATEST_PRERELEASE" ]; then
    echo "Latest prerelease version found: $LATEST_PRERELEASE"
    NEXT_PRERELEASE="$(pysemver bump prerelease "$LATEST_PRERELEASE")"
  else
    echo "No prerelease found for minor $NEXT_MINOR yet"
    NEXT_PRERELEASE="$NEXT_MINOR$FIRST_PRERELEASE_SUFFIX"
  fi
else
  NEXT_PRERELEASE="$CURRENT_YEAR.1.0$FIRST_PRERELEASE_SUFFIX"
  echo "No minor version found for year '$CURRENT_YEAR'"
fi
echo "Next prerelease: $NEXT_PRERELEASE"
