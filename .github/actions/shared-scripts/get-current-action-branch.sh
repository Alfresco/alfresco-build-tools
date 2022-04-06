#!/usr/bin/env bash
set -e
readonly FULL_PATH="$GITHUB_ACTION_PATH"
readonly STRIPPED_LEFT_PATH=${FULL_PATH/*alfresco-build-tools\/}
readonly ACTION_BRANCH=${STRIPPED_LEFT_PATH/\/.github*}
echo "Action branch: $ACTION_BRANCH"
echo "::set-output name=action-branch::$ACTION_BRANCH"
