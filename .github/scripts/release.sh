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

echo "Going to pin Alfresco-build-tools refs in .github/ to a release candidate commit (release $RELEASE_VERSION)"

# Capture the current HEAD SHA to use as the pin target.
# This avoids the chicken-and-egg: the tagged release commit (SHA2) will reference SHA_PREV
# (the last merged commit), which carries the same code tree as SHA2.
# The SHA of SHA2 itself cannot be known before it is created.
RELEASE_COMMIT_SHA=$(git rev-parse HEAD)

# SHA-pin internal refs in action/workflow files (.github/ only — these are executed and subject to org policy)
# Replaces both existing SHA pins (@<40hexchars>) and version tags (@v1.2.3) with the release candidate SHA
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ | xargs sed -i -e \
  "s|\(Alfresco/alfresco-build-tools[^@]*@\)\([0-9a-f]\{40\}\|v[0-9]\+\.[0-9]\+\.[0-9]\+\)|\1$RELEASE_COMMIT_SHA|g"
echo "SHA-pin to $RELEASE_COMMIT_SHA in .github/ completed successfully."

# Update version tags in docs/ (user-facing documentation stays human-readable with semver tags)
if grep -Rql "Alfresco/alfresco-build-tools.*@v" docs/; then
  grep -Rl "Alfresco/alfresco-build-tools.*@v" docs/ | xargs sed -i -e \
    "s/\(Alfresco\/alfresco-build-tools[^@]*@\)v[0-9]\+\.[0-9]\+\.[0-9]\+/\1$RELEASE_VERSION/g"
  echo "Version bump to $RELEASE_VERSION in docs/ completed successfully."
fi
