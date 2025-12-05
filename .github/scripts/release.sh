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

CURRENT_VERSION=$(git tag | sort -r --version-sort | head -n1)
if [ -z "$CURRENT_VERSION" ]; then
  echo "Can't retrieve tags"
  exit 1
fi

echo "Current version is $CURRENT_VERSION"
echo "Going to flip refs to $1"

grep -Rl "Alfresco/alfresco-build-tools.*@$CURRENT_VERSION" | xargs sed -i -e "s/\(Alfresco\/alfresco-build-tools.*@\)$CURRENT_VERSION/\1$1/g"
sed -i -e "s/$CURRENT_VERSION/$1/" .pre-commit-config.yaml
sed -i -e "s/@$CURRENT_VERSION/@$1/" docs/*.md

echo "Bump to $1 completed successfully."
