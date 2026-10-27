#!/bin/bash
set -e

profiles="$RELEASE_PROFILE"
if [ -n "$PRERELEASE_PROFILE" ] && [[ "$RELEASE_VERSION" == *"$PRERELEASE_MARKER"* ]]; then
  # Maven 3 only warns about a missing profile, so the prerelease would deploy to the release repository
  if ! mvn -B -ntp help:all-profiles | grep -qF "Profile Id: $PRERELEASE_PROFILE ("; then
    echo "::error::The prerelease profile '$PRERELEASE_PROFILE' is not defined in the pom, refusing to deploy $RELEASE_VERSION"
    exit 1
  fi
  echo "Activating the $PRERELEASE_PROFILE profile for prerelease $RELEASE_VERSION"
  profiles="$profiles,$PRERELEASE_PROFILE"
fi

echo "profiles=$profiles" >> "$GITHUB_OUTPUT"
