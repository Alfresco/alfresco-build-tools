#!/usr/bin/env bash
set -e
readonly FULL_PATH="$GITHUB_ACTION_PATH"
readonly STRIPPED_LEFT_PATH=${FULL_PATH/*alfresco-build-tools\/}
ACTION_BRANCH=${STRIPPED_LEFT_PATH/\/.github*}
#covers the usage in current repository where the action is referenced using relative path
if [ "$ACTION_BRANCH" = "." ]; then
  ACTION_BRANCH=$GITHUB_REF
fi
echo "Action branch: $ACTION_BRANCH"
echo "::set-output name=action-branch::$ACTION_BRANCH"
