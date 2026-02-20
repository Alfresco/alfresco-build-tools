#!/bin/bash -e
BRANCH_NAME=${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}

if [ "$ADDITIONAL_PR_EVENTS" = "true" ]; then
    echo "Additional events handling is enabled, checking for issue_comment and pull_request_review events"
    if [ "$GITHUB_EVENT_NAME" == "issue_comment" ]; then
        PR_URL=$(cat "$GITHUB_EVENT_PATH" | jq -r '.issue.pull_request.html_url')
        BRANCH_NAME=$(gh pr view "$PR_URL" --json baseRefName --jq '.baseRefName' 2>/dev/null)
        echo "Evaluated branch name for issue_comment event: $BRANCH_NAME"
    fi

    if [ "$GITHUB_EVENT_NAME" == "pull_request_review" ]; then
        PR_URL=$(cat "$GITHUB_EVENT_PATH" | jq -r '.pull_request.html_url')
        BRANCH_NAME=$(gh pr view "$PR_URL" --json baseRefName --jq '.baseRefName' 2>/dev/null)
        echo "Evaluated branch name for pull_request_review event: $BRANCH_NAME"
    fi
fi

if [ "$SANITIZE" = "true" ]; then
    BRANCH_NAME=$(echo "$BRANCH_NAME" | tr -d "." | tr "/" "-" | tr "[:upper:]" "[:lower:]")
fi

if [ "$MAX_LENGTH" -gt "0" ]; then
    BRANCH_NAME="${BRANCH_NAME:0:$MAX_LENGTH}"
    # shellcheck disable=SC2001
    BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/-$//')
fi

echo "Detected branch name is '$BRANCH_NAME'"

if [ "$EXPORT_TO_ENV" = "true" ]; then
    echo "::warning::Exporting branch name to environment variable is DEPRECATED, please switch to using \`branch-name\` output instead."
    echo "BRANCH_NAME=$BRANCH_NAME" >> "$GITHUB_ENV"
fi

echo "branch-name=$BRANCH_NAME" >> "$GITHUB_OUTPUT"
