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

if [ -z "$2" ] || [[ ! "$2" =~ ^v[0-9]+\.[0-9]+\.[0-9]+ ]]; then
  echo 'Second argument should be current version already released with a leading v char'
  exit 1
fi

NEXT_VERSION=$1
CURRENT_VERSION=$2

echo "Current version is $CURRENT_VERSION"
echo "Going to flip refs to $NEXT_VERSION"

grep -Rl "Alfresco/alfresco-build-tools.*@$CURRENT_VERSION" | xargs sed -i -e "s/\(Alfresco\/alfresco-build-tools.*@\)$CURRENT_VERSION/\1$NEXT_VERSION/g"
sed -i -e "s/$CURRENT_VERSION/$NEXT_VERSION/" .pre-commit-config.yaml
sed -i -e "s/@$CURRENT_VERSION/@$NEXT_VERSION/" docs/*.md
echo "Bump to $NEXT_VERSION completed successfully."
