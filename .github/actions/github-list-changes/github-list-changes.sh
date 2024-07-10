#!/bin/bash
set -x

if [[ $GITHUB_EVENT_NAME == "pull_request" ]]; then
    # Get the list of changed files from the pull request
    git diff --name-only refs/heads/$GITHUB_HEAD_REF refs/heads/$GITHUB_REF > all-changed-files.txt
elif [[ $GITHUB_EVENT_NAME == "push" ]]; then
    # Check if github.event.before exists (it might not for force pushes).
    old_commit=$BEFORE_COMMIT
    echo "old commit: $old_commit"
    git rev-parse --verify $old_commit > /dev/null 2>&1
    if [[ $? != 0 ]]; then
        # If it doesn't exist, then run against the (single) latest commit.
        old_commit="$AFTER_COMMIT~"
        echo "old commit changed to: $old_commit"
    fi
    # Get the list of changed files from the pushed commits
    echo "Diffing: $old_commit $AFTER_COMMIT"
    git diff --name-only $old_commit $AFTER_COMMIT > all-changed-files.txt
    cat all-changed-files.txt
else
    echo "Unsupported event type: $GITHUB_EVENT_NAME"
    exit 1
fi

# Write the list to the GitHub step output.
echo "all-changed-files=$( cat all-changed-files.txt )" >> $GITHUB_OUTPUT

# Write the list to the environment variable if requested
if [[ "$WRITE_LIST_TO_ENV" == "true" ]]; then
    echo "GITHUB_MODIFIED_FILES=$( cat all-changed-files.txt )" >> $GITHUB_ENV
fi

set +x
