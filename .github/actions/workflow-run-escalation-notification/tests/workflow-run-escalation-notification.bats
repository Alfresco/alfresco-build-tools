setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
    : > "$GITHUB_OUTPUT"

    export GITHUB_EVENT_NAME="workflow_run"
    export REASON_CODE="attempts-exhausted"
    export ATTEMPT="3"
    export MAX_ATTEMPTS="3"
    export FAILED_JOBS="Repository - PostgreSQL 15.17 tests"
    export HEADING="Release chain blocked"
    export POSITION="Hop 2 of 5 - alfresco-enterprise-repo"
    export DOWNSTREAM="Nothing propagates downstream until this is resolved."
    export CC="cc: release duty"
    export REPOSITORY="Alfresco/alfresco-enterprise-repo"
    export BRANCH="release/26.2"
    export WORKFLOW="Master/Release branch workflow"
}

body() {
    sed 's/^body=//' "$GITHUB_OUTPUT"
}

fact() {
    body | jq -r --arg t "$1" '.[] | select(.type=="FactSet").facts[] | select(.title==$t).value'
}

message() {
    body | jq -r '.[1].text'
}

jobs_block() {
    body | jq -r '.[] | select(.type=="Container").items[1].text'
}

@test "builds a card whose body is a JSON array" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r 'type')" = "array" ]
}

@test "a spent budget says the retries ran out" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [[ "$(message)" == "Automated retries were exhausted."* ]]
}

@test "a non-retryable job says no retry was attempted" {
    export REASON_CODE="non-retryable"
    run build-card.sh
    [ "$status" -eq 0 ]
    [[ "$(message)" == "A job that must not be re-run automatically failed, so no retry was attempted."* ]]
}

@test "a run with no failed job says a retry would change nothing" {
    export REASON_CODE="nothing-to-retry"
    run build-card.sh
    [ "$status" -eq 0 ]
    [[ "$(message)" == "The run failed without any job reporting a failure, so a retry would change nothing."* ]]
}

@test "the downstream sentence is appended to the generated one" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [[ "$(message)" == *"Nothing propagates downstream until this is resolved." ]]
}

@test "an empty downstream sentence leaves no trailing space" {
    export DOWNSTREAM=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(message)" = "Automated retries were exhausted." ]
}

@test "the first attempt reports no automated retries" {
    export ATTEMPT="1"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "1 of 3" ]
}

@test "a single retry is reported in the singular" {
    export ATTEMPT="2"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "2 of 3" ]
}

@test "several retries are reported in the plural" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "3 of 3" ]
}

@test "run details are taken from the triggering run" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Repository)" = "Alfresco/alfresco-enterprise-repo" ]
    [ "$(fact Branch)" = "release/26.2" ]
    [ "$(fact Workflow)" = "Master/Release branch workflow" ]
}

@test "the upstream version defaults to Unknown" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact 'Upstream version')" = "Unknown" ]
}

@test "a known upstream version is used" {
    export UPSTREAM_VERSION="26.2.0.147 (alfresco-community-repo)"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact 'Upstream version')" = "26.2.0.147 (alfresco-community-repo)" ]
}

@test "each failed job becomes its own bullet" {
    export FAILED_JOBS="one
two"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = "- one
- two" ]
}

@test "blank lines and indentation in the job list are ignored" {
    export FAILED_JOBS="  one

	two
"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = "- one
- two" ]
}

@test "a job name containing quotes survives into the card" {
    export FAILED_JOBS='Release "prod" job'
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = '- Release "prod" job' ]
}

@test "an empty job list says none reported" {
    export FAILED_JOBS=""
    export REASON_CODE="nothing-to-retry"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = "- none reported" ]
}

@test "fails on a reason code that is not an escalation" {
    export REASON_CODE="retry"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"reason-code must be"* ]]
}

@test "fails when no reason code is given" {
    unset REASON_CODE
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"reason-code must be"* ]]
}

@test "fails when attempt is not a positive number" {
    export ATTEMPT="0"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"attempt must be"* ]]
}

@test "fails when attempt is not a number" {
    export ATTEMPT="many"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"attempt must be"* ]]
}

@test "a card is only built for a workflow_run event" {
    export GITHUB_EVENT_NAME="push"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"only works on a workflow_run event"* ]]
}

@test "a missing attempt is rejected rather than assumed" {
    unset ATTEMPT
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"attempt must be a positive whole number"* ]]
}

@test "an empty position leaves the heading on its own" {
    export POSITION=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq '.[0].columns[1].items | length')" -eq 1 ]
}

@test "an empty cc adds no trailing block" {
    export CC=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq '.[-1].type')" = '"Container"' ]
}

@test "the attempt stands alone without a max" {
    unset MAX_ATTEMPTS
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "3" ]
}
