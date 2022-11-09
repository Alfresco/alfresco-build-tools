setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock send-slack-notification defaults
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
AAE-10092 review gh actions workflows (#789)

* AAE-10092: review gh workflow triggers

* AAE-10092: use ubuntu-latest

* AAE-10092: setup concurrency and cancel in progress

* AAE-10092: use alfresco-build-tools action for pre-commit

* AAE-10092: upgrade alfresco-build-tools to v1.20.0

* AAE-10092: ignore jenv .java-version

* AAE-10092: update maven build logic

* AAE-10092: add slack notification

commit
)
}

@test "basic slack message" {
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

@test "pull_request slack message" {
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

@test "multiline markdown for issues slack message" {
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

@test "multiline commit message for default slack message" {
    export EVENT_NAME=whatever

    run compute-message.sh

    [ "$status" -eq 0 ]

    expected_output=$(cat << 'BATS'
result<<EOF
AAE-10092 review gh actions workflows (#789)\n\n* AAE-10092: review gh workflow triggers\n\n* AAE-10092: use ubuntu-latest\n\n* AAE-10092: setup concurrency and cancel in progress\n\n* AAE-10092: use alfresco-build-tools action for pre-commit\n\n* AAE-10092: upgrade alfresco-build-tools to v1.20.0\n\n* AAE-10092: ignore jenv .java-version\n\n* AAE-10092: update maven build logic\n\n* AAE-10092: add slack notification
EOF
BATS
)

    [ "$output" = "$expected_output" ]
}
