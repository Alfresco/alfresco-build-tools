#!/bin/bash
set -e

if [ -z "$GITHUB_WORKSPACE" ]; then
  echo "You should not run anymore this script from your machine, see updated README"
  exit 1
fi

if [ -z "$1" ] || [[ ! "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo 'First argument should be next version to release with a leading v char'
  exit 1
fi

NEXT_VERSION=$1

echo "Going to flip Alfresco-build-tools refs in actions and docs to $NEXT_VERSION"

grep -Rl "Alfresco/alfresco-build-tools.*@v" | xargs sed -i -e "s/\(Alfresco\/alfresco-build-tools.*@\)v[0-9]\+\.[0-9]\+\.[0-9]\+/\1$NEXT_VERSION/g"
echo "Bump to $NEXT_VERSION completed successfully."
