setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/output"
    : > "$GITHUB_OUTPUT"

    export GITHUB_EVENT_NAME="workflow_run"
    export REASON_CODE="attempts-exhausted"
    export ATTEMPT="3"
    export MAX_ATTEMPTS="3"
    export FACTS=""
    export FAILED_JOBS="Repository - PostgreSQL 15.17 tests"
    export TITLE="Release chain blocked"
    export SUBTITLE="Hop 2 of 5 - alfresco-enterprise-repo"
    export MESSAGE="Nothing propagates downstream until this is resolved."
    export FOOTER="cc: release duty"
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

fact_titles() {
    body | jq -r '[.[] | select(.type=="FactSet").facts[].title] | join(",")'
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

@test "the message is appended to the generated sentence" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(message)" = "Automated retries were exhausted. Nothing propagates downstream until this is resolved." ]
}

@test "an empty message leaves no trailing space" {
    export MESSAGE=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(message)" = "Automated retries were exhausted." ]
}

@test "without a reason code the message stands alone" {
    export REASON_CODE=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(message)" = "Nothing propagates downstream until this is resolved." ]
}

@test "fails when neither a reason code nor a message is given" {
    export REASON_CODE=""
    export MESSAGE=""
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"reason-code or message is required"* ]]
}

@test "fails on a reason code that is not an escalation" {
    export REASON_CODE="retry"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"reason-code must be"* ]]
}

@test "the first attempt is reported as one of the budget" {
    export ATTEMPT="1"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "1 of 3" ]
}

@test "a later attempt is counted against the budget" {
    export ATTEMPT="2"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "2 of 3" ]
}

@test "the last attempt of the budget is reported as such" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "3 of 3" ]
}

@test "the attempt stands alone without a max" {
    unset MAX_ATTEMPTS
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Attempt)" = "3" ]
}

@test "run details are taken from the triggering run" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Repository)" = "Alfresco/alfresco-enterprise-repo" ]
    [ "$(fact Branch)" = "release/26.2" ]
    [ "$(fact Workflow)" = "Master/Release branch workflow" ]
}

@test "no facts leaves only the run details" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact_titles)" = "Repository,Branch,Workflow,Attempt" ]
}

@test "facts are added after the run details in the given order" {
    export FACTS="Release version|26.2.0.147
Owner|release duty"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact_titles)" = "Repository,Branch,Workflow,Attempt,Release version,Owner" ]
    [ "$(fact 'Release version')" = "26.2.0.147" ]
}

@test "a fact value keeps commas and later separators" {
    export FACTS="Modules|repo, share|community"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact Modules)" = "repo, share|community" ]
}

@test "blank lines and padding around facts are ignored" {
    export FACTS="
  Release version | 26.2.0.147

"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(fact_titles)" = "Repository,Branch,Workflow,Attempt,Release version" ]
    [ "$(fact 'Release version')" = "26.2.0.147" ]
}

@test "fails on a fact without a separator" {
    export FACTS="Release version 26.2.0.147"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"facts entry 'Release version 26.2.0.147'"* ]]
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

@test "markdown characters in a job name are escaped" {
    export FAILED_JOBS='build [linux] *nightly* `x`'
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = '- build \[linux\] \*nightly\* \`x\`' ]
}

@test "a backslash in a job name is escaped before anything else" {
    export FAILED_JOBS='weird\name'
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = '- weird\\name' ]
}

@test "underscores in a job name are escaped" {
    export FAILED_JOBS="run_ci / PMD Scan"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(jobs_block)" = '- run\_ci / PMD Scan' ]
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

@test "a missing attempt is rejected rather than assumed" {
    unset ATTEMPT
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"attempt must be a positive whole number"* ]]
}

@test "a card is only built for a workflow_run event" {
    export GITHUB_EVENT_NAME="push"
    run build-card.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"only works on a workflow_run event"* ]]
}

@test "the title and subtitle head the card" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r '[.[0].columns[1].items[].text] | join(",")')" = "Release chain blocked,Hop 2 of 5 - alfresco-enterprise-repo" ]
}

@test "an empty subtitle leaves the title on its own" {
    export SUBTITLE=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r '[.[0].columns[1].items[].text] | join(",")')" = "Release chain blocked" ]
}

@test "an empty title leaves its block off the card" {
    export TITLE=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r '[.[0].columns[1].items[].text] | join(",")')" = "Hop 2 of 5 - alfresco-enterprise-repo" ]
}

@test "the footer closes the card" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r '.[-1].text')" = "cc: release duty" ]
}

@test "an empty footer adds no trailing block" {
    export FOOTER=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(body | jq -r '.[-1].type')" = "Container" ]
}
