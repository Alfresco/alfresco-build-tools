setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"

    export REPOSITORY="Alfresco/alfresco-community-repo"
    export CONFIG_PATH=".github/release-auto-retry.yml"
    export RUN_ID="123"
    export RUN_ATTEMPT="1"
    export HEAD_BRANCH="master"
    export HEAD_SHA="aaaaaaa"

    export MOCK_CONFIG="non-retryable-jobs: [x]"
    export MOCK_CONFIG_JSON='{"max-attempts":3,"non-retryable-jobs":["Parse commit metadata","Push to Nexus"]}'
    export MOCK_FAILED="run_ci / PMD Scan"
    export MOCK_TIP="aaaaaaa"

    mock_gh
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

assert_failed_jobs() {
    local expected="$1" actual
    actual=$(sed -n '/^failed-jobs<<EOF_/,/^EOF_/p' "$GITHUB_OUTPUT" | sed '1d;$d')
    [ "$actual" = "$expected" ] || { echo "Expected failed-jobs '${expected}', got '${actual}'" >&2; return 1; }
}

# Stands in for the three read-only API calls the script makes, keyed on the path it asks for.
mock_gh() {
    gh() {
        local url=""
        for arg in "$@"; do
            case "$arg" in repos/*) url="$arg" ;; esac
        done
        case "$url" in
            */contents/*)
                [ -n "$MOCK_CONFIG" ] || return 1
                printf '%s\n' "$MOCK_CONFIG" ;;
            */actions/runs/*)
                [ -n "$MOCK_FAILED" ] && printf '%s\n' "$MOCK_FAILED"
                return 0 ;;
            */commits/*)
                [ -n "$MOCK_TIP" ] || return 1
                printf '%s\n' "$MOCK_TIP" ;;
            *)
                echo "unexpected gh invocation: $*" >&2
                return 1 ;;
        esac
    }
    yq() { printf '%s\n' "$MOCK_CONFIG_JSON"; }
    export -f gh yq
}

@test "retries when only retryable jobs failed" {
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "attempt" "1"
    assert_output_var "max-attempts" "3"
    assert_failed_jobs "run_ci / PMD Scan"
}

@test "does nothing when the repository has no configuration file" {
    export MOCK_CONFIG=""
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    assert_failed_jobs ""
}

@test "escalates when a non-retryable job failed" {
    export MOCK_FAILED="Push to Nexus"
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    [[ "$output" == *"Push to Nexus"* ]]
}

@test "escalates when a non-retryable job failed alongside a retryable one" {
    export MOCK_FAILED=$'run_ci / PMD Scan\nPush to Nexus'
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "a nested job sharing a denylisted name is still retried" {
    export MOCK_FAILED="run_ci / Parse commit metadata"
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "escalates when the attempt budget is spent" {
    export RUN_ATTEMPT="3"
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "retries on the last attempt still within budget" {
    export RUN_ATTEMPT="2"
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "does not retry a run whose branch has moved on" {
    export MOCK_TIP="bbbbbbb"
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"supersedes"* ]]
}

@test "does not retry a run whose branch was deleted" {
    export MOCK_TIP=""
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
}

@test "does nothing when no job reported a failure" {
    export MOCK_FAILED=""
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
}

@test "max-attempts defaults to 3 when not configured" {
    export MOCK_CONFIG_JSON='{"non-retryable-jobs":["Push to Nexus"]}'
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "max-attempts" "3"
}

@test "fails when max-attempts is not a number" {
    export MOCK_CONFIG_JSON='{"max-attempts":"two","non-retryable-jobs":["x"]}'
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::"* ]]
}

@test "fails when max-attempts is zero" {
    export MOCK_CONFIG_JSON='{"max-attempts":0,"non-retryable-jobs":["x"]}'
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -ne 0 ]
}

@test "fails when no non-retryable jobs are configured" {
    export MOCK_CONFIG_JSON='{"max-attempts":3}'
    mock_gh
    run release-chain-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-retryable-jobs"* ]]
}
