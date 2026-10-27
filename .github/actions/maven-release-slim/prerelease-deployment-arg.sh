#!/bin/bash
set -e

maven_arg=""
if [ -n "$PRERELEASE_REPOSITORY" ] && [[ "$RELEASE_VERSION" == *"$PRERELEASE_MARKER"* ]]; then
  echo "Deploying prerelease $RELEASE_VERSION to $PRERELEASE_REPOSITORY"
  maven_arg="-DaltReleaseDeploymentRepository=$PRERELEASE_REPOSITORY"
fi

echo "maven-arg=$maven_arg" >> "$GITHUB_OUTPUT"
