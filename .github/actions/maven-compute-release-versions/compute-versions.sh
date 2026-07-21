#!/usr/bin/env bash
set -euo pipefail

POM_VERSION=$(mvn -B -q help:evaluate -Dexpression=project.version -DforceStdout)
RELEASE_VERSION="${POM_VERSION%-SNAPSHOT}"
NEXT_VERSION=$(echo "${RELEASE_VERSION}" | awk -F. '{OFS="."; $NF=$NF+1; print $0}')
DEVELOPMENT_VERSION="${NEXT_VERSION}-SNAPSHOT"

echo "release-version=${RELEASE_VERSION}" >> "$GITHUB_OUTPUT"
echo "development-version=${DEVELOPMENT_VERSION}" >> "$GITHUB_OUTPUT"
