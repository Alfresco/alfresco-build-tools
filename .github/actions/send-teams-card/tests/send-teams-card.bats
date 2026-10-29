setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"
}

payload() {
    sed -n '/^{/,$p' <<<"$output"
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

# send-card.sh tests

@test "send-card wraps the body in the Teams message envelope" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -r '.type')" = "message" ]
    [ "$(payload | jq -r '.attachments[0].contentType')" = "application/vnd.microsoft.card.adaptive" ]
    [ "$(payload | jq -r '.attachments[0].content.type')" = "AdaptiveCard" ]
    [ "$(payload | jq -r '.attachments[0].content.version')" = "1.5" ]
    [ "$(payload | jq -r '.attachments[0].content."$schema"')" = "http://adaptivecards.io/schemas/adaptive-card.json" ]
}

@test "send-card passes the body through untouched" {
    export CARD_BODY='[{"type":"TextBlock","text":"first"},{"type":"FactSet","facts":[]}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -c '.attachments[0].content.body')" = '[{"type":"TextBlock","text":"first"},{"type":"FactSet","facts":[]}]' ]
}

@test "send-card keeps non-ASCII text intact" {
    export CARD_BODY='[{"type":"TextBlock","text":"🔴 blocked"}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -r '.attachments[0].content.body[0].text')" = "🔴 blocked" ]
}

@test "send-card carries actions and mention entities" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export CARD_ACTIONS='[{"type":"Action.OpenUrl","title":"View run","url":"https://example.com"}]'
    export ENTITIES='[{"type":"mention","text":"<at>Jane</at>","mentioned":{"id":"jane@example.com","name":"Jane"}}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -r '.attachments[0].content.actions[0].title')" = "View run" ]
    [ "$(payload | jq -r '.attachments[0].content.msteams.entities[0].mentioned.name')" = "Jane" ]
}

@test "send-card defaults actions and entities to empty" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -c '.attachments[0].content.actions')" = "[]" ]
    [ "$(payload | jq -c '.attachments[0].content.msteams.entities')" = "[]" ]
}

@test "send-card paints the card with the given colour" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export COLOR="A30200"
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -r '.attachments[0].content.backgroundImage.url')" = "https://singlecolorimage.com/get/A30200/2x2" ]
}

@test "send-card falls back to grey without a colour" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 0 ]
    [ "$(payload | jq -r '.attachments[0].content.backgroundImage.url')" = "https://singlecolorimage.com/get/808080/2x2" ]
}

@test "send-card rejects a body that is not a JSON array" {
    export CARD_BODY='{"type":"TextBlock"}'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"card-body must be a JSON array"* ]]
}

@test "send-card rejects invalid JSON in the body" {
    export CARD_BODY='[{"type":'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"card-body must be a JSON array"* ]]
}

@test "send-card rejects actions that are not a JSON array" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export CARD_ACTIONS='"nope"'
    export DRY_RUN="true"

    run send-card.sh

    [ "$status" -eq 1 ]
    [[ "$output" == *"card-actions must be a JSON array"* ]]
}

@test "send-card needs a webhook url when it is really sending" {
    export CARD_BODY='[{"type":"TextBlock","text":"hi"}]'
    export DRY_RUN="false"

    run send-card.sh

    [ "$status" -ne 0 ]
    [[ "$output" == *"webhook-url is required"* ]]
}

@test "transform-mentions accepts a newline separated list" {
    export USERS=$'Alice|alice@x.com\nBob|bob@x.com\n'
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$(sed 's/^result=//' <<<"$output" | jq -c '[.[].mentioned.name]')" = '["Alice","Bob"]' ]
}

@test "transform-mentions ignores a blank entry after a trailing separator" {
    export USERS='John|a@b.c, '
    export TAGS=""

    run transform-mentions.sh

    [ "$status" -eq 0 ]
    [ "$(sed 's/^result=//' <<<"$output" | jq -c '[.[].mentioned.name]')" = '["John"]' ]
}

# compute-status.sh tests

mock_gh() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/gh" <<'MOCK'
#!/usr/bin/env bash
echo "$*" > "$BATS_TEST_TMPDIR/gh-args"
[ -n "${MOCK_GH_FAIL:-}" ] && { echo "gh: HTTP 403" >&2; exit 1; }
printf '%s' "$MOCK_CONCLUSIONS"
MOCK
    chmod +x "$BATS_TEST_TMPDIR/bin/gh"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export GITHUB_REPOSITORY="Alfresco/example" GITHUB_RUN_ID="42"
}

@test "compute-status reports failure when any completed step failed" {
    mock_gh
    export MOCK_CONCLUSIONS=$'success\ncancelled\nfailure\nskipped'

    run compute-status.sh

    [ "$status" -eq 0 ]
    [ "$output" = "status=failure" ]
}

@test "compute-status reports cancelled when a step was cancelled and none failed" {
    mock_gh
    export MOCK_CONCLUSIONS=$'success\ncancelled\nskipped'

    run compute-status.sh

    [ "$status" -eq 0 ]
    [ "$output" = "status=cancelled" ]
}

@test "compute-status reports success otherwise" {
    mock_gh
    export MOCK_CONCLUSIONS=$'success\nskipped'

    run compute-status.sh

    [ "$status" -eq 0 ]
    [ "$output" = "status=success" ]
}

@test "compute-status matches whole conclusions only" {
    mock_gh
    export MOCK_CONCLUSIONS=$'startup_failure_ignored\nsuccess'

    run compute-status.sh

    [ "$status" -eq 0 ]
    [ "$output" = "status=success" ]
}

@test "compute-status reads every page of jobs for the current run" {
    mock_gh
    export MOCK_CONCLUSIONS="success"

    run compute-status.sh

    [ "$status" -eq 0 ]
    [[ "$(cat "$BATS_TEST_TMPDIR/gh-args")" == *"--paginate repos/Alfresco/example/actions/runs/42/jobs"* ]]
}

@test "compute-status fails rather than guessing when the API call fails" {
    mock_gh
    export MOCK_GH_FAIL=1

    run compute-status.sh

    [ "$status" -ne 0 ]
    [[ "$output" != *"status="* ]]
}
