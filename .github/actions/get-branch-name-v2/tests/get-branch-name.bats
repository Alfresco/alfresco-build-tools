#!/usr/bin/env bash
setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_ENV=/dev/null
    export GITHUB_OUTPUT=/dev/null
    export GITHUB_HEAD_REF="OPSEXP-1234"
    export GITHUB_BASE_REF="master"

    # Mock get-branch-name defaults
    export MAX_LENGTH="0"
    export SANITIZE="false"
}

@test "basic" {
    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected branch name is 'OPSEXP-1234'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "sanitize" {
    export SANITIZE="true"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected branch name is 'opsexp-1234'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "max-length" {
    export MAX_LENGTH="6"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected branch name is 'OPSEXP'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "max-length and trailing dash" {
    export MAX_LENGTH="7"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected branch name is 'OPSEXP'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "max-length and not trailing dash" {
    export MAX_LENGTH="9"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Detected branch name is 'OPSEXP-12'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "additional-pr-events disabled by default" {
    export ADDITIONAL_PR_EVENTS="false"
    export GITHUB_EVENT_NAME="issue_comment"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" != *"Additional events handling is enabled"* ]]
    [[ "$output" == *"Detected branch name is 'OPSEXP-1234'"* ]]
    [[ "$output" == *"Detected base branch name is 'master'"* ]]
}

@test "additional-pr-events for issue_comment event" {
    export ADDITIONAL_PR_EVENTS="true"
    export GITHUB_EVENT_NAME="issue_comment"

    # Create temporary event payload
    TEMP_EVENT=$(mktemp)
    echo '{"issue":{"pull_request":{"html_url":"https://github.com/test/repo/pull/123"}}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    # Mock gh command
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"headRefName":"feature-branch","baseRefName":"main"}'
        fi
    }
    export -f gh

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Additional events handling is enabled"* ]]
    [[ "$output" == *"Evaluated issue_comment event"* ]]
    [[ "$output" == *"Detected branch name is 'feature-branch'"* ]]
    [[ "$output" == *"Detected base branch name is 'main'"* ]]

    # Cleanup
    rm "$TEMP_EVENT"
}

@test "additional-pr-events for pull_request_review event" {
    export ADDITIONAL_PR_EVENTS="true"
    export GITHUB_EVENT_NAME="pull_request_review"

    # Create temporary event payload
    TEMP_EVENT=$(mktemp)
    echo '{"pull_request":{"html_url":"https://github.com/test/repo/pull/456"}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    # Mock gh command
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"headRefName":"review-branch","baseRefName":"develop"}'
        fi
    }
    export -f gh

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Additional events handling is enabled"* ]]
    [[ "$output" == *"Evaluated pull_request_review event"* ]]
    [[ "$output" == *"Detected branch name is 'review-branch'"* ]]
    [[ "$output" == *"Detected base branch name is 'develop'"* ]]

    # Cleanup
    rm "$TEMP_EVENT"
}
