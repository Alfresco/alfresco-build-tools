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
    export API_RETRY_DELAY="0"
    export MOCK_TIP="aaaaaaa"
    export MOCK_TIP_STATUS="ok"
    export MOCK_RUN_STATUS="completed"

    export WORKFLOW_ID="999"
    export RUN_NUMBER="42"
    export MOCK_RUNS_STATUS="ok"
    export MOCK_WORKFLOW_RUNS='{"workflow_runs":[
        {"run_number":41,"head_sha":"ggggggg"},
        {"run_number":38,"head_sha":"fffffff"}
    ]}'

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
        local url="" jq_expr="" use_jq=0 body="" paginate=0
        while [ $# -gt 0 ]; do
            case "$1" in
                --jq) jq_expr="$2"; use_jq=1; shift 2 ;;
                --paginate) paginate=1; shift ;;
                -H) shift 2 ;;
                repos/*) url="$1"; shift ;;
                *) shift ;;
            esac
        done

        case "$url" in
            */actions/workflows/*/runs*)
                if [ "$MOCK_RUNS_STATUS" = "error" ]; then
                    echo "gh: Internal Server Error (HTTP 500)" >&2; return 1
                fi
                body="$MOCK_WORKFLOW_RUNS" ;;
            */actions/runs/*/jobs*)
                # GitHub times out on a big page of a re-run attempt. --paginate asks for 100 unless told otherwise.
                if [ -n "${MOCK_JOBS_MAX_PAGE:-}" ]; then
                    local per_page=30
                    [ "$paginate" -eq 1 ] && per_page=100
                    [[ "$url" =~ per_page=([0-9]+) ]] && per_page="${BASH_REMATCH[1]}"
                    if [ "$per_page" -gt "$MOCK_JOBS_MAX_PAGE" ]; then
                        echo "gh: Server Error (HTTP 502)" >&2; return 1
                    fi
                fi
                body="$MOCK_JOBS" ;;
            */actions/runs/*)
                body="{\"run_attempt\":${MOCK_RUN_ATTEMPT:-$RUN_ATTEMPT},\"status\":\"$MOCK_RUN_STATUS\"}" ;;
            */git/ref/heads/*)
                case "$MOCK_TIP_STATUS" in
                    missing) echo "gh: Not Found (HTTP 404)" >&2; return 1 ;;
                    error) echo "gh: Forbidden (HTTP 403)" >&2; return 1 ;;
                    flaky)
                        echo x >> "$MOCK_TIP_CALLS"
                        if [ "$(wc -l < "$MOCK_TIP_CALLS")" -lt 3 ]; then
                            echo "gh: Internal Server Error (HTTP 500)" >&2; return 1
                        fi ;;
                    always-5xx) echo "gh: Bad Gateway (HTTP 502)" >&2; return 1 ;;
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

@test "an escalation reports the last successful sha" {
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "last-successful-sha" "ggggggg"
}

@test "only a success older than the failing run can be the anchor" {
    export RUN_NUMBER="39"
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "last-successful-sha" "fffffff"
}

@test "the anchor is empty when the branch has no earlier successful run" {
    export MOCK_WORKFLOW_RUNS='{"workflow_runs":[]}'
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "last-successful-sha" ""
    [[ "$output" == *"::warning::No earlier successful run"* ]]
}

@test "a failed anchor lookup leaves it empty without failing the step" {
    export MOCK_RUNS_STATUS="error"
    export MOCK_JOBS='{"jobs":[{"name":"Push to Nexus","conclusion":"failure"}]}'
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "escalate"
    assert_output_var "last-successful-sha" ""
}

@test "a decision other than escalate does not look the anchor up" {
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_output_var "last-successful-sha" ""
}

@test "a transient 5xx is retried and the run continues" {
    export MOCK_TIP_STATUS="flaky"
    export MOCK_TIP_CALLS="$BATS_TMPDIR/tip_calls_${RANDOM}"
    > "$MOCK_TIP_CALLS"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    [ "$(wc -l < "$MOCK_TIP_CALLS")" -eq 3 ]
    rm -f "$MOCK_TIP_CALLS"
}

@test "a 5xx that never clears still fails the step" {
    export MOCK_TIP_STATUS="always-5xx"
    run workflow-run-auto-retry.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::Could not read branch"* ]]
}

@test "lists the jobs in pages small enough for GitHub to answer in time" {
    export MOCK_JOBS_MAX_PAGE=50
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "retry"
    assert_failed_jobs "run_ci / PMD Scan"
}

@test "a 404 is not retried and is told apart from an error" {
    export MOCK_TIP_STATUS="missing"
    run workflow-run-auto-retry.sh
    [ "$status" -eq 0 ]
    assert_output_var "decision" "none"
    [[ "$output" == *"no longer exists"* ]]
}
