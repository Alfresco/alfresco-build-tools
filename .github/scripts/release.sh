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

# Internal action references use the $/ self-repository syntax and resolve to
# the commit being released, so nothing under .github/ needs rewriting.
# Only the user-facing documentation examples carry a version tag.
echo "Updating documentation examples to $RELEASE_VERSION"
grep -Rl "Alfresco/alfresco-build-tools.*@v" docs/ .github/actions/ .github/skills/ --include="*.md" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)v[0-9]+\.[0-9]+\.[0-9]+|\1$RELEASE_VERSION|g"
