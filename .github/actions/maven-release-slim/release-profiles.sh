#!/bin/bash
set -e

profiles="$RELEASE_PROFILE"
if [ -n "$PRERELEASE_PROFILE" ] && [[ "$RELEASE_VERSION" == *"$PRERELEASE_MARKER"* ]]; then
  echo "Activating the $PRERELEASE_PROFILE profile for prerelease $RELEASE_VERSION"
  profiles="$profiles,$PRERELEASE_PROFILE"
fi

echo "profiles=$profiles" >> "$GITHUB_OUTPUT"
