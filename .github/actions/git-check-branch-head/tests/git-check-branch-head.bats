setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"

    export REMOTE="origin"
    export BRANCH="master"
    export EXPECTED_SHA="1111111111111111111111111111111111111111"
    export FAIL_ON_MISMATCH="true"
}

teardown() {
    rm -f "$GITHUB_OUTPUT"
}

assert_output_var() {
    local key="$1" expected="$2"
    local actual
    actual=$(grep "^${key}=" "$GITHUB_OUTPUT" | cut -d= -f2-)
    [ "$actual" = "$expected" ] || { echo "Expected ${key}=${expected}, got ${key}=${actual}" >&2; return 1; }
}

mock_ls_remote() {
    export MOCK_LS_REMOTE_SHA="$1"
    git() {
        if [ "$1" = "ls-remote" ]; then
            [ -z "$MOCK_LS_REMOTE_SHA" ] || echo "$MOCK_LS_REMOTE_SHA	refs/heads/master"
        else
            echo "unexpected git invocation: $*" >&2
            return 1
        fi
    }
    export -f git
}

@test "passes when remote head matches expected sha" {
    mock_ls_remote "$EXPECTED_SHA"
    run git-check-branch-head.sh
    [ "$status" -eq 0 ]
    assert_output_var "changed" "false"
    assert_output_var "remote-sha" "$EXPECTED_SHA"
}

@test "fails when remote head moved" {
    mock_ls_remote "2222222222222222222222222222222222222222"
    run git-check-branch-head.sh
    [ "$status" -ne 0 ]
    assert_output_var "changed" "true"
    assert_output_var "remote-sha" "2222222222222222222222222222222222222222"
    [[ "$output" == *"::error::"* ]]
}

@test "reports mismatch without failing when fail-on-mismatch is false" {
    export FAIL_ON_MISMATCH="false"
    mock_ls_remote "2222222222222222222222222222222222222222"
    run git-check-branch-head.sh
    [ "$status" -eq 0 ]
    assert_output_var "changed" "true"
    [[ "$output" == *"moved from expected"* ]]
    [[ "$output" != *"::error::"* ]]
}

@test "fails when branch is not found on remote" {
    mock_ls_remote ""
    run git-check-branch-head.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"not found on remote"* ]]
}

@test "falls back to local HEAD when expected-sha is empty" {
    export EXPECTED_SHA=""
    git() {
        case "$1" in
            rev-parse) echo "3333333333333333333333333333333333333333" ;;
            ls-remote) echo "3333333333333333333333333333333333333333	refs/heads/master" ;;
            *) echo "unexpected git invocation: $*" >&2; return 1 ;;
        esac
    }
    export -f git
    run git-check-branch-head.sh
    [ "$status" -eq 0 ]
    assert_output_var "changed" "false"
}

@test "strips refs/heads/ prefix from branch input" {
    export BRANCH="refs/heads/master"
    mock_ls_remote "$EXPECTED_SHA"
    run git-check-branch-head.sh
    [ "$status" -eq 0 ]
    assert_output_var "changed" "false"
}
