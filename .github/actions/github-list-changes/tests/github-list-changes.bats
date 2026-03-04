#!/usr/bin/env bats

setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Use a temp directory so all-changed-files.txt doesn't pollute the workspace
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    export GITHUB_OUTPUT="$TEMP_DIR/github_output"
    export GITHUB_ENV="$TEMP_DIR/github_env"
    export WRITE_LIST_TO_ENV="false"
    export GH_TOKEN="fake-token"

    touch "$GITHUB_OUTPUT" "$GITHUB_ENV"
}

teardown() {
    rm -rf "$TEMP_DIR"
}

# ---------------------------------------------------------------------------
# issue_comment event
# ---------------------------------------------------------------------------

@test "issue_comment: lists changed files successfully" {
    export GITHUB_EVENT_NAME="issue_comment"

    TEMP_EVENT=$(mktemp)
    echo '{"issue":{"pull_request":{"html_url":"https://github.com/test/repo/pull/42"}}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"number":42,"baseRefName":"main"}'
        fi
    }
    export -f gh

    function git() {
        if [ "$1" = "diff" ]; then
            echo -e "src/foo.txt\nsrc/bar.txt"
        fi
    }
    export -f git

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"issue_comment"* ]]
    [[ "$output" == *"src/foo.txt"* ]]
    [[ "$output" == *"src/bar.txt"* ]]

    rm "$TEMP_EVENT"
}

@test "issue_comment: fails when GH_TOKEN is not set" {
    export GITHUB_EVENT_NAME="issue_comment"
    unset GH_TOKEN

    TEMP_EVENT=$(mktemp)
    echo '{"issue":{"pull_request":{"html_url":"https://github.com/test/repo/pull/42"}}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    run github-list-changes.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"github-token not provided"* ]]

    rm "$TEMP_EVENT"
}

@test "issue_comment: exits cleanly when event is not associated with a pull request" {
    export GITHUB_EVENT_NAME="issue_comment"

    # Issue comment without a pull_request field
    TEMP_EVENT=$(mktemp)
    echo '{"issue":{"number":10}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"not associated with a pull request"* ]]

    rm "$TEMP_EVENT"
}

@test "issue_comment: fails when PR number cannot be retrieved" {
    export GITHUB_EVENT_NAME="issue_comment"

    TEMP_EVENT=$(mktemp)
    echo '{"issue":{"pull_request":{"html_url":"https://github.com/test/repo/pull/42"}}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"number":null,"baseRefName":"main"}'
        fi
    }
    export -f gh

    run github-list-changes.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to get PR number"* ]]

    rm "$TEMP_EVENT"
}

# ---------------------------------------------------------------------------
# pull_request_review event
# ---------------------------------------------------------------------------

@test "pull_request_review: lists changed files successfully" {
    export GITHUB_EVENT_NAME="pull_request_review"
    export GH_TOKEN="fake-token"

    TEMP_EVENT=$(mktemp)
    echo '{"pull_request":{"html_url":"https://github.com/test/repo/pull/99"}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"number":99,"baseRefName":"develop"}'
        fi
    }
    export -f gh

    function git() {
        if [ "$1" = "diff" ]; then
            echo -e "lib/a.ts\nlib/b.ts"
        fi
    }
    export -f git

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"pull_request_review"* ]]
    [[ "$output" == *"lib/a.ts"* ]]
    [[ "$output" == *"lib/b.ts"* ]]

    rm "$TEMP_EVENT"
}

@test "pull_request_review: fails when GH_TOKEN is not set" {
    export GITHUB_EVENT_NAME="pull_request_review"
    unset GH_TOKEN

    TEMP_EVENT=$(mktemp)
    echo '{"pull_request":{"html_url":"https://github.com/test/repo/pull/99"}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    run github-list-changes.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"github-token not provided"* ]]

    rm "$TEMP_EVENT"
}

@test "pull_request_review: exits cleanly when pull_request field is missing" {
    export GITHUB_EVENT_NAME="pull_request_review"

    TEMP_EVENT=$(mktemp)
    echo '{}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"not associated with a pull request"* ]]

    rm "$TEMP_EVENT"
}

@test "pull_request_review: fails when PR number cannot be retrieved" {
    export GITHUB_EVENT_NAME="pull_request_review"

    TEMP_EVENT=$(mktemp)
    echo '{"pull_request":{"html_url":"https://github.com/test/repo/pull/99"}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"number":null,"baseRefName":"main"}'
        fi
    }
    export -f gh

    run github-list-changes.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to get PR number"* ]]

    rm "$TEMP_EVENT"
}

@test "pull_request_review: fails when base ref cannot be retrieved" {
    export GITHUB_EVENT_NAME="pull_request_review"

    TEMP_EVENT=$(mktemp)
    echo '{"pull_request":{"html_url":"https://github.com/test/repo/pull/99"}}' > "$TEMP_EVENT"
    export GITHUB_EVENT_PATH="$TEMP_EVENT"

    # gh returns a valid PR number but empty base ref (e.g. permission issue)
    function gh() {
        if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
            echo '{"number":99,"baseRefName":""}'
        fi
    }
    export -f gh

    run github-list-changes.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"Failed to get PR base ref"* ]]

    rm "$TEMP_EVENT"
}


# ---------------------------------------------------------------------------
# pull_request event
# ---------------------------------------------------------------------------

@test "pull_request: lists changed files successfully" {
    export GITHUB_EVENT_NAME="pull_request"
    export PULL_REQUEST_NUMBER="42"
    export GITHUB_BASE_REF="main"

    function git() {
        if [ "$1" = "diff" ]; then
            echo -e "src/foo.txt\nsrc/bar.txt"
        fi
    }
    export -f git

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"pull request 42"* ]]
    [[ "$output" == *"src/foo.txt"* ]]
    [[ "$output" == *"src/bar.txt"* ]]
}

# ---------------------------------------------------------------------------
# push event
# ---------------------------------------------------------------------------

@test "push: lists changed files from old commit to new commit" {
    export GITHUB_EVENT_NAME="push"
    export BEFORE_COMMIT="abc1234"
    export AFTER_COMMIT="def5678"

    function git() {
        if [ "$1" = "log" ]; then
            return 0
        fi
        if [ "$1" = "diff" ]; then
            echo -e "README.md\nsrc/main.py"
        fi
    }
    export -f git

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"abc1234"* ]]
    [[ "$output" == *"def5678"* ]]
    [[ "$output" == *"README.md"* ]]
    [[ "$output" == *"src/main.py"* ]]
}

@test "push: falls back to AFTER_COMMIT~ when BEFORE_COMMIT does not exist (force push)" {
    export GITHUB_EVENT_NAME="push"
    export BEFORE_COMMIT="deadbeef"
    export AFTER_COMMIT="cafebabe"

    function git() {
        if [ "$1" = "log" ]; then
            return 1
        fi
        if [ "$1" = "diff" ]; then
            echo -e "force-pushed-file.txt"
        fi
    }
    export -f git

    run github-list-changes.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"cafebabe~"* ]]
    [[ "$output" == *"cafebabe"* ]]
    [[ "$output" == *"force-pushed-file.txt"* ]]
}
