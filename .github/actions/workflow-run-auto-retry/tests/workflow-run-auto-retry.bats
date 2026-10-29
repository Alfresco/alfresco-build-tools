setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    export GITHUB_STEP_SUMMARY="$BATS_TMPDIR/github_summary_${RANDOM}"
    > "$GITHUB_OUTPUT"
    > "$GITHUB_STEP_SUMMARY"

    export GITHUB_EVENT_NAME="workflow_run"
    export REPOSITORY="Alfresco/alfresco-community-repo"
    export RUN_ID="123"
    export RUN_ATTEMPT="1"
    export HEAD_BRANCH="master"
    export HEAD_SHA="aaaaaaa"

    export MAX_ATTEMPTS="3"
    export NON_RETRYABLE_JOBS='Parse commit metadata
Push to Nexus'
    export MOCK_JOBS='{"jobs":[
        {"name":"Parse commit metadata","conclusion":"success"},
        {"name":"run_ci / PMD Scan","conclusion":"failure"},
        {"name":"Push to Nexus","conclusion":"skipped"},
        {"name":"run_ci / Repository - MariaDB ${{ matrix.version }} tests","conclusion":"skipped"}
    ]}'
    export MOCK_TIP="aaaaaaa"
    export MOCK_TIP_STATUS="ok"
    export MOCK_RUN_STATUS="completed"

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

# Stands in for the read-only API calls, keyed on the path. It applies the real jq to a real
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
            */actions/runs/*/jobs)
                body="$MOCK_JOBS" ;;
            */actions/runs/*)
                body="{\"run_attempt\":${MOCK_RUN_ATTEMPT:-$RUN_ATTEMPT},\"status\":\"$MOCK_RUN_STATUS\"}" ;;
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
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_failed_jobs "run_ci / Integration tests"
}

@test "escalates when only skipped, successful and cancelled jobs are present" {
    export MOCK_JOBS='{"jobs":[
        {"name":"Push to Nexus","conclusion":"skipped"},
        {"name":"Parse commit metadata","conclusion":"success"},
        {"name":"run_ci / Unit tests","conclusion":"cancelled"}
    ]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "reason-code" "nothing-to-retry"
    [[ "$output" == *"without any job reporting a failure"* ]]
}

@test "fails when the branch tip cannot be read" {
    export MOCK_TIP_STATUS="error"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::Could not read branch"* ]]
}

@test "escalates when a non-retryable job failed" {
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "reason-code" "non-retryable"
    [[ "$output" == *"Push to Nexus"* ]]
}

@test "escalates when a non-retryable job failed alongside a retryable one" {
    export MOCK_JOBS='{"jobs":[
        {"name":"run_ci / PMD Scan","conclusion":"failure"},
        {"name":"Push to Nexus","conclusion":"failure"}
    ]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "a job name containing a comma is reported intact" {
    export NON_RETRYABLE_JOBS="Release, tag and push"
    export MOCK_JOBS='{"jobs":[{"name":"Release, tag and push","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    [[ "$output" == *'"Release, tag and push"'* ]]
}

@test "a nested job sharing a denylisted name is still retried" {
    export MOCK_JOBS='{"jobs":[{"name":"run_ci / Parse commit metadata","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "blank lines and indentation in non-retryable-jobs are ignored" {
    export NON_RETRYABLE_JOBS='
  Push to Nexus

      Parse commit metadata
'
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
}

@test "escalates when the attempt budget is spent" {
    export RUN_ATTEMPT="3"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "reason-code" "attempts-exhausted"
}

@test "retries on the last attempt still within budget" {
    export RUN_ATTEMPT="2"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    # Only an escalation carries a code.
    assert_output_var "reason-code" ""
    [[ "$output" == *"re-running them"* ]]
}

@test "does not retry a run whose branch has moved on" {
    export MOCK_TIP="bbbbbbb"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"supersedes"* ]]
}

@test "does not retry a run whose branch was deleted" {
    export MOCK_TIP_STATUS="missing"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"no longer exists"* ]]
}

@test "max-attempts defaults to 3 when empty" {
    export MAX_ATTEMPTS=""
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "max-attempts" "3"
}

@test "a higher max-attempts extends the budget" {
    export MAX_ATTEMPTS="5"
    export RUN_ATTEMPT="4"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "max-attempts" "5"
}

@test "fails when max-attempts is not a number" {
    export MAX_ATTEMPTS="two"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::"* ]]
}

@test "fails when max-attempts is zero" {
    export MAX_ATTEMPTS="0"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
}

@test "an empty denylist retries every failure" {
    export NON_RETRYABLE_JOBS=""
    export MOCK_JOBS='{"jobs":[
        {"name":"Push to Nexus","conclusion":"failure"},
        {"name":"run_ci / PMD Scan","conclusion":"failure"}
    ]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "an empty denylist does not match every job as a blank pattern" {
    export NON_RETRYABLE_JOBS='
'
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
}

@test "fails when not triggered by a workflow_run event" {
    export GITHUB_EVENT_NAME="push"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"only works on a workflow_run event"* ]]
}

@test "ignores a stale event when the run has a newer attempt" {
    export MOCK_RUN_ATTEMPT="3"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"attempt 3"* ]]
}

@test "ignores a run that is in progress again" {
    export MOCK_RUN_STATUS="in_progress"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"in_progress"* ]]
}

@test "writes the decision to the job summary" {
    export MOCK_TIP="bbbbbbb"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    grep -q "^\*\*none\*\*: Branch master moved" "$GITHUB_STEP_SUMMARY"
}
