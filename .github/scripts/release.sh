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

if [ -z "$COMMIT_USERNAME" ] || [ -z "$COMMIT_EMAIL" ]; then
  echo "COMMIT_USERNAME and COMMIT_EMAIL must be set for git authorship"
  exit 1
fi

echo "Going to pin Alfresco-build-tools refs via two-pass approach (release $RELEASE_VERSION)"

git config user.name "$COMMIT_USERNAME"
git config user.email "$COMMIT_EMAIL"

# Pass 1: release candidate commit
# Pin all .github/ refs to SHA_PREV (the last merged commit).
SHA_PREV=$(git rev-parse HEAD)
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ --include="*.yml" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)[0-9a-f]{40}|\1$SHA_PREV|g"

# Update version tags in docs/ (human-readable semver for user-facing documentation)
grep -Rl "Alfresco/alfresco-build-tools.*@v" docs/ | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)v[0-9]+\.[0-9]+\.[0-9]+|\1$RELEASE_VERSION|g"

GITHUB_TOKEN=$GH_TOKEN npx --yes @gionn/verified-bot-commit@2.3.2-alpha.9fe9b4e \
  --repository "Alfresco/alfresco-build-tools" \
  --ref "refs/heads/master" \
  --files "**" \
  --message "Release candidate $RELEASE_VERSION"

SHA_RC=$(git rev-parse HEAD)

# Push the release candidate commit to the remote. The next step commits the
# release changes via the GitHub API (verified-bot-commit), which builds on top
# of the remote branch tip; without this push it would create the release commit
# on top of SHA_PREV and silently drop this candidate commit.
git push origin HEAD
echo "Pass 1 complete: pinned refs to SHA_PREV=$SHA_PREV, pushed SHA_RC=$SHA_RC"

# Pass 2: release commit (picked up by verified-bot-commit)
# Pin all .github/ refs to SHA_RC so the tagged release commit references the
# candidate commit, which in turn references SHA_PREV (the actual code).
# Each release adds 2 more levels of consistent nesting depth; deeper chains
# gain full consistency over successive releases.
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ --include="*.yml" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)[0-9a-f]{40}|\1$SHA_RC|g"
echo "Pass 2 complete: pinned refs to SHA_RC=$SHA_RC (verified-bot-commit will create the final release commit)"
