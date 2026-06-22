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

# Verify the published package integrity before executing it with npx.
VBC_PKG="@gionn-net/verified-bot-commit@3.0.0"
VBC_EXPECTED_INTEGRITY="sha512-gNWco5bzvqhAYTSFXrnzNGxd3PYspX9CHb4wtGbw+VHfeo4s83sUe2BgglRWSl2nS85uUEU+je7/u9Fyn5F9CQ=="
VBC_ACTUAL_INTEGRITY=$(npm view "$VBC_PKG" dist.integrity)
if [ "$VBC_ACTUAL_INTEGRITY" != "$VBC_EXPECTED_INTEGRITY" ]; then
  echo "Integrity check failed for $VBC_PKG: expected '$VBC_EXPECTED_INTEGRITY', got '$VBC_ACTUAL_INTEGRITY'"
  exit 1
fi

GITHUB_TOKEN=$GH_TOKEN npx --yes "$VBC_PKG" \
  --repository "Alfresco/alfresco-build-tools" \
  --ref "$TARGET_BRANCH" \
  --files "**" \
  --message "Release candidate $RELEASE_VERSION"

# verified-bot-commit advances the local branch ref to the new commit, so HEAD
# already points at the candidate commit here.
SHA_RC=$(git rev-parse HEAD)
echo "Pass 1 complete: pinned refs to SHA_PREV=$SHA_PREV, pushed SHA_RC=$SHA_RC"

# Wait until the GitHub API reports the candidate commit as the branch head
# before the next step creates the release commit. The release commit step
# (verified-bot-commit action) reads the branch head from the API to use as the
# new commit's parent; GitHub ref reads are eventually consistent, so right
# after this push the API may still return SHA_PREV. If that happens, the
# release commit is parented on SHA_PREV (a sibling of the candidate instead of
# a child) and the non-force ref update fails with "Update is not a fast
# forward".
echo "Waiting for the GitHub API to report $SHA_RC as the head of $TARGET_BRANCH"
ENCODED_BRANCH=${TARGET_BRANCH//\//%2F}
for attempt in $(seq 1 30); do
  REMOTE_HEAD=$(gh api "repos/Alfresco/alfresco-build-tools/git/ref/heads/$ENCODED_BRANCH" \
    --jq '.object.sha' 2>/dev/null || echo "")
  if [ "$REMOTE_HEAD" = "$SHA_RC" ]; then
    echo "API reports $TARGET_BRANCH at $SHA_RC after $attempt attempt(s)"
    break
  fi
  if [ "$attempt" -eq 30 ]; then
    echo "Timed out waiting for $TARGET_BRANCH to report $SHA_RC (last seen: '$REMOTE_HEAD')"
    exit 1
  fi
  sleep 2
done

# Pass 2: release commit (picked up by verified-bot-commit)
# Pin all .github/ refs to SHA_RC so the tagged release commit references the
# candidate commit, which in turn references SHA_PREV (the actual code).
# Each release adds 2 more levels of consistent nesting depth; deeper chains
# gain full consistency over successive releases.
grep -Rl "Alfresco/alfresco-build-tools.*@" .github/ --include="*.yml" | xargs sed -i -E \
  "s|(Alfresco/alfresco-build-tools[^@]*@)[0-9a-f]{40}|\1$SHA_RC|g"
echo "Pass 2 complete: pinned refs to SHA_RC=$SHA_RC (verified-bot-commit will create the final release commit)"
