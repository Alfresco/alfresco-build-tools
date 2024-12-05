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
    export NEEDS=$(echo $NEEDS_JSON | jq -r 'to_entries[] | "\(.key): \(.value.result)"')

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
build: success\npromote: failure\n\nfix: update retry inputs to use string type\n\n* use strings\n* add tests
EOF
BATS
)

    echo $output
    echo $expected_output

    [ "$output" = "$expected_output" ]

}
