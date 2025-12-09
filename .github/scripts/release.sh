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

grep -Rl "Alfresco/alfresco-build-tools.*@v" | xargs sed -i -e "s/\(Alfresco\/alfresco-build-tools.*@\)v[0-9]\+\.[0-9]\+\.[0-9]\+/\1$RELEASE_VERSION/g"
echo "Bump to $RELEASE_VERSION completed successfully."
