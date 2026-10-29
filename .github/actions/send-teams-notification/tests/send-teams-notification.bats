setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock send-teams-notification defaults
    export PR_TITLE="fix(jx-updatebot-pr): update release binary version to 0.3.13 #158"
    export ISSUE_BODY=$(cat << 'body'
This PR adds support for retrying `jx-updatebot-pr` action in case there is a race condition on the target pr branch due to a concurrent commit from another project, i.e.

```
- uses: Alfresco/alfresco-build-tools/.github/actions/jx-updatebot-pr@ref
  with:
    retries: '3'
    retries-wait: '10'

```
body
)
    export COMMIT_MESSAGE=$(cat << 'commit'
fix: update retry inputs to use string type

* use strings
* add tests
commit
)
}

# compute-message.sh tests

@test "basic teams message" {
    export BLOCK_MESSAGE="my custom message"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
my custom message
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "a percent sign in the message survives" {
    export BLOCK_MESSAGE="100% complete"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
100% complete
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "a printf placeholder in the message is not expanded" {
    export BLOCK_MESSAGE="coverage a%db then 80%s"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
coverage a%db then 80%s
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "pull_request teams message" {
    export EVENT_NAME=pull_request

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
fix(jx-updatebot-pr): update release binary version to 0.3.13 #158
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "multiline markdown for issues teams message" {
    export EVENT_NAME=issues

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
This PR adds support for retrying `jx-updatebot-pr` action in case there is a race condition on the target pr branch due to a concurrent commit from another project, i.e.\n\n```\n- uses: Alfresco/alfresco-build-tools/.github/actions/jx-updatebot-pr@ref\n  with:\n    retries: '3'\n    retries-wait: '10'\n\n```
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "multiline commit message for default teams message" {
    export EVENT_NAME=whatever

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
fix: update retry inputs to use string type\n\n* use strings\n* add tests
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "multiline commit message using CTRL-M" {
    export EVENT_NAME=whatever
    export COMMIT_MESSAGE=$(<$BATS_TEST_DIRNAME/sample-commit-message.txt)

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
AAE-12140 Check and fix inconsistent scenarios in UAT (#734)\n\n* AAE-12140 Add assertion to check for correct application status\n\nCo-authored-by: Elias Ricken de Medeiros <26007058+erdemedeiros@users.noreply.github.com>
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "empty teams message" {
    export COMMIT_MESSAGE=""

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result=
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "empty block message" {
    export BLOCK_MESSAGE=""

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
fix: update retry inputs to use string type\n\n* use strings\n* add tests
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "message with double quotes" {
    export BLOCK_MESSAGE="Message with \"double quotes\""

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
Message with \"double quotes\"
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "message with single quotes" {
    export BLOCK_MESSAGE="Message with 'single quotes'"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
Message with 'single quotes'
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "empty block message append" {
    export EVENT_NAME=push
    export BLOCK_MESSAGE=""
    export APPEND="true"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
fix: update retry inputs to use string type\n\n* use strings\n* add tests
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "block message append" {
    export EVENT_NAME=push
    export BLOCK_MESSAGE="bye"
    export APPEND="true"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
fix: update retry inputs to use string type\n\n* use strings\n* add tests\n\nbye
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "block message append empty default" {
    export EVENT_NAME=push
    export COMMIT_MESSAGE=""
    export BLOCK_MESSAGE="bye"
    export APPEND="true"

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
bye
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}

@test "long message" {
    export COMMIT_MESSAGE=$(<$BATS_TEST_DIRNAME/sample-long-message.txt)
    export CUT_MESSAGE=$(<$BATS_TEST_DIRNAME/sample-long-message-cut.txt)

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << BATS
result<<EOF
${CUT_MESSAGE}
EOF
BATS
)

    [ "$output" = "$expected_output" ]

}

@test "needs" {
    export NEEDS_JSON=$(<$BATS_TEST_DIRNAME/sample-needs.json)
    export NEEDS=$(echo $NEEDS_JSON | jq -r 'to_entries | map([.key, .value.result]|join(": ")) | join("\n\n")')

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
build: success\n\npromote: failure\n\nfix: update retry inputs to use string type\n\n* use strings\n* add tests
EOF
BATS
)

    [ "$output" = "$expected_output" ]

}

# transform-mentions.sh tests

@test "transform-mentions with no mentions" {
    export USERS=""
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = "result=[]" ]
}

@test "transform-mentions with single user" {
    export USERS="John Doe|john.doe@example.com"
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=[{"type":"mention","text":"<at>John Doe</at>","mentioned":{"id":"john.doe@example.com","name":"John Doe"}}]' ]
}

@test "transform-mentions with multiple users" {
    export USERS="John Doe|john.doe@example.com,Jane Smith|jane.smith@example.com"
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=[{"type":"mention","text":"<at>John Doe</at>","mentioned":{"id":"john.doe@example.com","name":"John Doe"}},{"type":"mention","text":"<at>Jane Smith</at>","mentioned":{"id":"jane.smith@example.com","name":"Jane Smith"}}]' ]
}

@test "transform-mentions with single tag" {
    export USERS=""
    export TAGS="Security|TagId123=="

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=[{"type":"mention","text":"<at>Security</at>","mentioned":{"id":"TagId123==","name":"Security","type":"tag"}}]' ]
}

@test "transform-mentions with multiple tags" {
    export USERS=""
    export TAGS="Security|TagId123==,DevOps|TagId456=="

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=[{"type":"mention","text":"<at>Security</at>","mentioned":{"id":"TagId123==","name":"Security","type":"tag"}},{"type":"mention","text":"<at>DevOps</at>","mentioned":{"id":"TagId456==","name":"DevOps","type":"tag"}}]' ]
}

@test "transform-mentions with users and tags" {
    export USERS="John Doe|john.doe@example.com"
    export TAGS="Security|TagId123=="

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=[{"type":"mention","text":"<at>John Doe</at>","mentioned":{"id":"john.doe@example.com","name":"John Doe"}},{"type":"mention","text":"<at>Security</at>","mentioned":{"id":"TagId123==","name":"Security","type":"tag"}}]' ]
}

@test "transform-mentions with missing mention id" {
    export USERS="John Doe"
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 1 ]
    [ "$output" = "Error: Input 'John Doe' does not contain the expected format with a '|' separator" ]
}

# compute-extra-body.sh tests

@test "compute-extra-body with default empty array" {
    export EXTRA_BODY="[]"

    run compute-extra-body.sh

    [ "$status" -eq 0 ]
    [ "$output" = "result=" ]
}

@test "compute-extra-body unset defaults to empty" {
    unset EXTRA_BODY

    run compute-extra-body.sh

    [ "$status" -eq 0 ]
    [ "$output" = "result=" ]
}

@test "compute-extra-body with single element" {
    export EXTRA_BODY='[{"type":"FactSet","facts":[{"title":"Cluster","value":"my-env"}]}]'

    run compute-extra-body.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=,{"type":"FactSet","facts":[{"title":"Cluster","value":"my-env"}]}' ]
}

@test "compute-extra-body with multiple elements" {
    export EXTRA_BODY='[{"type":"TextBlock","text":"one"},{"type":"TextBlock","text":"two"}]'

    run compute-extra-body.sh

    [ "$status" -eq 0 ]
    [ "$output" = 'result=,{"type":"TextBlock","text":"one"},{"type":"TextBlock","text":"two"}' ]
}

@test "compute-extra-body rejects a JSON object" {
    export EXTRA_BODY='{"type":"TextBlock"}'

    run compute-extra-body.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a JSON array"* ]]
}

@test "compute-extra-body rejects a JSON string" {
    export EXTRA_BODY='"foo"'

    run compute-extra-body.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a JSON array"* ]]
}

@test "compute-extra-body rejects invalid JSON" {
    export EXTRA_BODY='not json'

    run compute-extra-body.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"must be a JSON array"* ]]
}

# resolve-run-context.sh tests

run_context() {
    export REPO_URL="https://github.com/Alfresco/example"
    export WR_SHA="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    export WR_BRANCH="release/25.5"
    export WR_RUN_ID="111"
    export WR_RUN_ATTEMPT="3"
    export WR_WORKFLOW="Master/Release branch workflow"
    export SELF_SHA="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    export SELF_BRANCH="master"
    export SELF_RUN_ID="222"
    export SELF_RUN_ATTEMPT="1"
    export SELF_WORKFLOW="Auto-retry"
}

key() {
    grep "^$1=" <<<"$output" | cut -d= -f2-
}

@test "a workflow_run event describes the run that triggered it" {
    run_context
    export GITHUB_EVENT_NAME="workflow_run"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$WR_SHA" ]
    [ "$(key branch)" = "release/25.5" ]
    [ "$(key run-link)" = "https://github.com/Alfresco/example/actions/runs/111/attempts/3" ]
    [ "$(key workflow-title)" = "Master/Release branch workflow (attempt #3)" ]
}

@test "any other event describes the run this action is part of" {
    run_context
    export GITHUB_EVENT_NAME="push"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$SELF_SHA" ]
    [ "$(key branch)" = "master" ]
    [ "$(key run-link)" = "https://github.com/Alfresco/example/actions/runs/222/attempts/1" ]
    [ "$(key workflow-title)" = "Auto-retry" ]
}

@test "an event nobody thought about falls back to this run" {
    run_context
    export GITHUB_EVENT_NAME="schedule"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$SELF_SHA" ]
}

@test "the small sha is the first six characters" {
    run_context
    export GITHUB_EVENT_NAME="push"
    export SELF_SHA="ed25e9f1c0deadbeef"

    run resolve-run-context.sh

    [ "$(key small-sha)" = "ed25e9" ]
}

@test "a first attempt carries no attempt suffix" {
    run_context
    export GITHUB_EVENT_NAME="workflow_run"
    export WR_RUN_ATTEMPT="1"

    run resolve-run-context.sh

    [ "$(key workflow-title)" = "Master/Release branch workflow" ]
}

@test "a watcher can ask for its own run instead of the trigger" {
    run_context
    export GITHUB_EVENT_NAME="workflow_run"
    export REPORT_ON="self"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$SELF_SHA" ]
    [ "$(key branch)" = "master" ]
    [ "$(key run-link)" = "https://github.com/Alfresco/example/actions/runs/222/attempts/1" ]
    [ "$(key workflow-title)" = "Auto-retry" ]
}

@test "asking for the trigger explicitly matches the default" {
    run_context
    export GITHUB_EVENT_NAME="workflow_run"
    export REPORT_ON="triggering-run"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$WR_SHA" ]
    [ "$(key branch)" = "release/25.5" ]
}

@test "report-on changes nothing outside a workflow_run event" {
    run_context
    export GITHUB_EVENT_NAME="push"
    export REPORT_ON="self"

    run resolve-run-context.sh

    [ "$status" -eq 0 ]
    [ "$(key sha)" = "$SELF_SHA" ]
}

@test "rejects a report-on nobody implemented" {
    run_context
    export GITHUB_EVENT_NAME="workflow_run"
    export REPORT_ON="selff"

    run resolve-run-context.sh

    [ "$status" -ne 0 ]
    [[ "$output" == *"report-on must be"* ]]
}
