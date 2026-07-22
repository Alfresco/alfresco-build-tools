#!/usr/bin/env bash
set -euo pipefail

POM_VERSION="$(mvn -B -q help:evaluate -Dexpression=project.version -DforceStdout | tr -d '\r')"
if [[ -z "${POM_VERSION}" ]]; then
  echo "Failed to evaluate Maven project.version (empty output)" >&2
  exit 1
fi

RELEASE_VERSION="${POM_VERSION%-SNAPSHOT}"
if ! [[ "${RELEASE_VERSION}" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "Unsupported Maven project.version '${POM_VERSION}'. Expected a numeric dot-separated version with optional '-SNAPSHOT' suffix." >&2
  exit 1
fi

NEXT_VERSION="$(awk -F. -v OFS=. '{$NF=$NF+1; print}' <<< "${RELEASE_VERSION}")"
DEVELOPMENT_VERSION="${NEXT_VERSION}-SNAPSHOT"

: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is not set (this script must run in a GitHub Actions step)}"
echo "release-version=${RELEASE_VERSION}" >> "$GITHUB_OUTPUT"
echo "next-development-version=${DEVELOPMENT_VERSION}" >> "$GITHUB_OUTPUT"
