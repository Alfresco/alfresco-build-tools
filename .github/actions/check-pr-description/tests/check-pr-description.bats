#!/usr/bin/env bats

setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    SCRIPT="$DIR/../check-pr-description.sh"
    export MIN_CHARS=15
    export MIN_WORDS=3
    export SKIP_AUTHORS="dependabot renovate alfresco-build*"
    export SKIP_BRANCHES="dependabot/* renovate/* updatecli* image-update* flux-* pr-* release-please--* changeset-release/* snyk-* whitesource* mend-* automated-* automation/*"
    export PR_AUTHOR="octocat"
    export PR_DRAFT="false"
    export PR_BRANCH="feature/foo"
}

@test "passes on a meaningful description" {
    export PR_BODY="Fixes the login redirect loop on session expiry."
    run "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "keeps markdown link text as meaningful content" {
    export PR_BODY="Refactor the [token refresh](https://example.com/docs) handling to avoid races."
    run "$SCRIPT"
    [ "$status" -eq 0 ]
}

@test "fails on an empty description" {
    export PR_BODY=""
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR description is empty"* ]]
}

@test "fails when only PR-template HTML comments are present" {
    export PR_BODY="<!-- describe your change here -->"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PR description is empty"* ]]
}

@test "fails on a ticket-link-only description" {
    export PR_BODY="https://hyland.atlassian.net/browse/AAE-1234"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"only a link"* ]]
}

@test "fails on a bare ticket key description" {
    export PR_BODY="AAE-1234"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"only a link"* ]]
}

@test "fails when the description is too short in characters" {
    export PR_BODY="typo fix here"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"too short"* ]]
}

@test "fails when the description has too few words" {
    export PR_BODY="aaaaaaaaaaaaaaaaaaaa"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"too short"* ]]
}

@test "skips draft PRs" {
    export PR_DRAFT="true"
    export PR_BODY="short"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping draft PR"* ]]
}

@test "skips bot authors" {
    export PR_AUTHOR="dependabot[bot]"
    export PR_BODY="short"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping automated PR"* ]]
}

@test "skips authors matching a skip-authors glob" {
    export PR_AUTHOR="alfresco-build-user"
    export PR_BODY="x"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping automated PR"* ]]
}

@test "skips head branches matching a skip-branches glob" {
    export PR_AUTHOR="svc-account"
    export PR_BRANCH="dependabot/terraform/aws-5.0"
    export PR_BODY="x"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping automated PR"* ]]
}

@test "does not skip regular authors and branches" {
    export PR_AUTHOR="octocat"
    export PR_BRANCH="feature/login-fix"
    export PR_BODY="x"
    run "$SCRIPT"
    [ "$status" -eq 1 ]
}

@test "fails with a clear error on non-integer min-chars" {
    export MIN_CHARS="abc"
    export PR_BODY="Fixes the login redirect loop on session expiry."
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid min-chars"* ]]
}

@test "fails with a clear error on non-integer min-words" {
    export MIN_WORDS="two"
    export PR_BODY="Fixes the login redirect loop on session expiry."
    run "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid min-words"* ]]
}

@test "does not expand skip-authors globs against the workspace" {
    export SKIP_AUTHORS="*"
    export PR_AUTHOR="octocat"
    export PR_BODY="x"
    run "$SCRIPT"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping automated PR"* ]]
}
