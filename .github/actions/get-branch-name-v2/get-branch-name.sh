#!/bin/bash -e
BRANCH_NAME="${GITHUB_HEAD_REF:-$GITHUB_REF_NAME}"
BASE_BRANCH_NAME="${GITHUB_BASE_REF:-}"

if [ "$ADDITIONAL_PR_EVENTS" = "true" ]; then
    echo "Additional events handling is enabled, checking for issue_comment and pull_request_review events"

    if [ "$GITHUB_EVENT_NAME" == "issue_comment" ]; then
        PR_URL=$(cat "$GITHUB_EVENT_PATH" | jq -r '.issue.pull_request.html_url // empty')
    fi

    if [ "$GITHUB_EVENT_NAME" == "pull_request_review" ]; then
        PR_URL=$(cat "$GITHUB_EVENT_PATH" | jq -r '.pull_request.html_url // empty')
    fi

    if [ -n "$PR_URL" ]; then
        PR_DATA=$(gh pr view "$PR_URL" --json baseRefName,headRefName 2>/dev/null)
        BRANCH_NAME=$(echo "$PR_DATA" | jq -r '.headRefName')
        BASE_BRANCH_NAME=$(echo "$PR_DATA" | jq -r '.baseRefName')
        echo "Evaluated $GITHUB_EVENT_NAME event"
    fi
fi

if [ "$SANITIZE" = "true" ]; then
    BRANCH_NAME=$(echo "$BRANCH_NAME" | tr -d "." | tr "/" "-" | tr "[:upper:]" "[:lower:]")
    BASE_BRANCH_NAME=$(echo "$BASE_BRANCH_NAME" | tr -d "." | tr "/" "-" | tr "[:upper:]" "[:lower:]")
fi

if [ "$MAX_LENGTH" -gt "0" ]; then
    BRANCH_NAME="${BRANCH_NAME:0:$MAX_LENGTH}"
    # shellcheck disable=SC2001
    BRANCH_NAME=$(echo "$BRANCH_NAME" | sed 's/-$//')

    BASE_BRANCH_NAME="${BASE_BRANCH_NAME:0:$MAX_LENGTH}"
    # shellcheck disable=SC2001
    BASE_BRANCH_NAME=$(echo "$BASE_BRANCH_NAME" | sed 's/-$//')
fi

echo "Detected branch name is '$BRANCH_NAME'"
echo "Detected base branch name is '$BASE_BRANCH_NAME'"

echo "branch-name=$BRANCH_NAME" >> "$GITHUB_OUTPUT"
echo "base-branch-name=$BASE_BRANCH_NAME" >> "$GITHUB_OUTPUT"
