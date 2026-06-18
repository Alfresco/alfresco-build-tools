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

echo "Going to pin Alfresco-build-tools refs via two-pass approach (release $RELEASE_VERSION)"

# Pass 1: release candidate commit
# Pin all .github/ refs to SHA_PREV (the last merged commit).
SHA_PREV=$(git rev-parse HEAD)
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ --include="*.yml" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)[0-9a-f]{40}|\1$SHA_PREV|g"

# Update version tags in docs/ (human-readable semver for user-facing documentation)
grep -Rl "Alfresco/alfresco-build-tools.*@v" docs/ | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)v[0-9]+\.[0-9]+\.[0-9]+|\1$RELEASE_VERSION|g"

# Auth for the @gionn scope; keep ${GH_TOKEN} literal so npm interpolates it at runtime.
{
  echo "@gionn:registry=https://npm.pkg.github.com"
  # shellcheck disable=SC2016 # literal ${GH_TOKEN}; npm interpolates it at runtime
  echo '//npm.pkg.github.com/:_authToken=${GH_TOKEN}'
} >> "$HOME/.npmrc"
GITHUB_TOKEN=$GH_TOKEN npx --yes @gionn/verified-bot-commit@2.3.2-alpha.9fe9b4e \
  --repository "Alfresco/alfresco-build-tools" \
  --ref "$TARGET_BRANCH" \
  --files "**" \
  --message "Release candidate $RELEASE_VERSION"

# verified-bot-commit creates the commit remotely, so pull it to advance local HEAD.
git pull origin "$TARGET_BRANCH"
SHA_RC=$(git rev-parse HEAD)
echo "Pass 1 complete: pinned refs to SHA_PREV=$SHA_PREV, pushed SHA_RC=$SHA_RC"

# Pass 2: release commit (picked up by verified-bot-commit)
# Pin all .github/ refs to SHA_RC so the tagged release commit references the
# candidate commit, which in turn references SHA_PREV (the actual code).
# Each release adds 2 more levels of consistent nesting depth; deeper chains
# gain full consistency over successive releases.
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ --include="*.yml" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)[0-9a-f]{40}|\1$SHA_RC|g"
echo "Pass 2 complete: pinned refs to SHA_RC=$SHA_RC (verified-bot-commit will create the final release commit)"
