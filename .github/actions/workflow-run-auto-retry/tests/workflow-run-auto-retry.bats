setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # The script shells out to yq, so the real one has to parse the real YAML fixtures.
    command -v yq >/dev/null || skip "yq is not installed"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    export GITHUB_STEP_SUMMARY="$BATS_TMPDIR/github_summary_${RANDOM}"
    > "$GITHUB_OUTPUT"
    > "$GITHUB_STEP_SUMMARY"

    export GITHUB_EVENT_NAME="workflow_run"
    export REPOSITORY="Alfresco/alfresco-community-repo"
    export CONFIG_PATH=".github/workflow-run-auto-retry.yml"
    export RUN_ID="123"
    export RUN_ATTEMPT="1"
    export HEAD_BRANCH="master"
    export HEAD_SHA="aaaaaaa"

    export MOCK_CONFIG='max-attempts: 3
non-retryable-jobs:
  - "Parse commit metadata"
  - "Push to Nexus"'
    export MOCK_CONFIG_STATUS="ok"
    export MOCK_JOBS='{"jobs":[
        {"name":"Parse commit metadata","conclusion":"success"},
        {"name":"run_ci / PMD Scan","conclusion":"failure"},
        {"name":"Push to Nexus","conclusion":"skipped"},
        {"name":"run_ci / Repository - MariaDB ${{ matrix.version }} tests","conclusion":"skipped"}
    ]}'
    export MOCK_TIP="aaaaaaa"
    export MOCK_TIP_STATUS="ok"

    mock_gh
}

teardown() {
    rm -f "$GITHUB_OUTPUT" "$GITHUB_STEP_SUMMARY"
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

# Stands in for the three read-only API calls, keyed on the path. It applies the real jq to a real
# JSON fixture so the --jq filters in the script are exercised rather than assumed.
mock_gh() {
    gh() {
        local url="" jq_expr="" use_jq=0 body=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --jq) jq_expr="$2"; use_jq=1; shift 2 ;;
                -H) shift 2 ;;
                repos/*) url="$1"; shift ;;
                *) shift ;;
            esac
        done

        case "$url" in
            */contents/*)
                case "$MOCK_CONFIG_STATUS" in
                    missing) echo "gh: Not Found (HTTP 404)" >&2; return 1 ;;
                    error) echo "gh: Bad credentials (HTTP 401)" >&2; return 1 ;;
                esac
                body="$MOCK_CONFIG" ;;
            */actions/runs/*)
                body="$MOCK_JOBS" ;;
            */git/ref/heads/*)
                case "$MOCK_TIP_STATUS" in
                    missing) echo "gh: Not Found (HTTP 404)" >&2; return 1 ;;
                    error) echo "gh: Internal Server Error (HTTP 500)" >&2; return 1 ;;
                esac
                body="{\"object\":{\"sha\":\"$MOCK_TIP\"}}" ;;
            *)
                echo "unexpected gh invocation: $url" >&2
                return 1 ;;
        esac

        if [ "$use_jq" -eq 1 ]; then
            printf '%s' "$body" | jq -r "$jq_expr"
        else
            printf '%s' "$body"
        fi
    }
    export -f gh
}

@test "retries when only retryable jobs failed" {
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "attempt" "1"
    assert_output_var "max-attempts" "3"
    assert_failed_jobs "run_ci / PMD Scan"
}

@test "a timed out job counts as a failure" {
    export MOCK_JOBS='{"jobs":[{"name":"run_ci / Integration tests","conclusion":"timed_out"}]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_failed_jobs "run_ci / Integration tests"
}

@test "skipped and successful jobs are not treated as failures" {
    export MOCK_JOBS='{"jobs":[
        {"name":"Push to Nexus","conclusion":"skipped"},
        {"name":"Parse commit metadata","conclusion":"success"},
        {"name":"run_ci / Unit tests","conclusion":"cancelled"}
    ]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    [[ "$output" == *"without any job reporting a failure"* ]]
}

@test "does nothing when the repository has no configuration file" {
    export MOCK_CONFIG_STATUS="missing"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    assert_failed_jobs ""
}

@test "fails when the configuration cannot be read" {
    export MOCK_CONFIG_STATUS="error"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::Could not read"* ]]
}

@test "fails when the branch tip cannot be read" {
    export MOCK_TIP_STATUS="error"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::Could not read branch"* ]]
}

@test "escalates when a non-retryable job failed" {
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    [[ "$output" == *"Push to Nexus"* ]]
}

@test "escalates when a non-retryable job failed alongside a retryable one" {
    export MOCK_JOBS='{"jobs":[
        {"name":"run_ci / PMD Scan","conclusion":"failure"},
        {"name":"Push to Nexus","conclusion":"failure"}
    ]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "a job name containing a comma is reported intact" {
    export MOCK_CONFIG='non-retryable-jobs:
  - "Release, tag and push"'
    export MOCK_JOBS='{"jobs":[{"name":"Release, tag and push","conclusion":"failure"}]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    [[ "$output" == *'"Release, tag and push"'* ]]
}

@test "a nested job sharing a denylisted name is still retried" {
    export MOCK_JOBS='{"jobs":[{"name":"run_ci / Parse commit metadata","conclusion":"failure"}]}'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "escalates when the attempt budget is spent" {
    export RUN_ATTEMPT="3"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "retries on the last attempt still within budget" {
    export RUN_ATTEMPT="2"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "does not retry a run whose branch has moved on" {
    export MOCK_TIP="bbbbbbb"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"supersedes"* ]]
}

@test "does not retry a run whose branch was deleted" {
    export MOCK_TIP_STATUS="missing"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"no longer exists"* ]]
}

@test "max-attempts defaults to 3 when not configured" {
    export MOCK_CONFIG='non-retryable-jobs:
  - "Push to Nexus"'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "max-attempts" "3"
}

@test "max-attempts is read from a hyphenated YAML key" {
    export MOCK_CONFIG='max-attempts: 5
non-retryable-jobs:
  - "Push to Nexus"'
    export RUN_ATTEMPT="4"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "max-attempts" "5"
}

@test "fails when max-attempts is not a number" {
    export MOCK_CONFIG='max-attempts: "two"
non-retryable-jobs: ["x"]'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::"* ]]
}

@test "fails when max-attempts is zero" {
    export MOCK_CONFIG='max-attempts: 0
non-retryable-jobs: ["x"]'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
}

@test "fails when no non-retryable jobs are configured" {
    export MOCK_CONFIG='max-attempts: 3'
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"non-retryable-jobs"* ]]
}

@test "fails when not triggered by a workflow_run event" {
    export GITHUB_EVENT_NAME="push"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"only works on a workflow_run event"* ]]
}

@test "writes the decision to the job summary" {
    export MOCK_TIP="bbbbbbb"
    mock_gh
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    grep -q "^\*\*none\*\*: Branch master moved" "$GITHUB_STEP_SUMMARY"
}
