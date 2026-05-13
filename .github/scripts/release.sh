#!/bin/bash
set -e

if [ -z "$GITHUB_WORKSPACE" ]; then
  echo "You should not run anymore this script from your machine, see updated README"
  exit 1
fi

if [ -z "$RELEASE_VERSION" ] || [[ ! "$RELEASE_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo "RELEASE_VERSION must start with a leading v char, current value: '$RELEASE_VERSION'"
  exit 1
fi

echo "Going to flip Alfresco-build-tools refs in actions and docs to $RELEASE_VERSION"

RELEASE_SHA=$(git rev-parse --verify --quiet "refs/tags/$RELEASE_VERSION^{commit}" || true)
if [ -z "$RELEASE_SHA" ]; then
  RELEASE_SHA=$(git rev-parse HEAD)
  echo "Tag $RELEASE_VERSION not found yet, using current HEAD commit: $RELEASE_SHA"
else
  echo "Found commit $RELEASE_SHA for tag $RELEASE_VERSION"
fi

grep -RIl "Alfresco/alfresco-build-tools.*@" | xargs -r sed -i -e "s#\(Alfresco/alfresco-build-tools[^@[:space:]]*@\)\(v[0-9]\+\.[0-9]\+\.[0-9]\+\|[a-f0-9]\{40\}\)#\1$RELEASE_SHA#g"
echo "Bump to $RELEASE_VERSION ($RELEASE_SHA) completed successfully."
