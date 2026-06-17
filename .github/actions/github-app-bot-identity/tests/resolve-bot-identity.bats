#!/usr/bin/env bats
setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_OUTPUT=/dev/null
    export GH_TOKEN="dummy"
    export APP_SLUG=""

    # Mock gh to return a fixed user id for the /users/<bot> lookup
    function gh() {
        if [ "$1" = "api" ]; then
            echo "12345678"
        fi
    }
    export -f gh
}

@test "resolves identity from app-slug" {
    export APP_SLUG="my-app"

    run resolve-bot-identity.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolved bot name is 'my-app[bot]'"* ]]
    [[ "$output" == *"Resolved user id is '12345678'"* ]]
    [[ "$output" == *"Resolved identity is 'my-app[bot] <12345678+my-app[bot]@users.noreply.github.com>'"* ]]
}

@test "falls back to github-actions[bot] when app-slug is empty" {
    export APP_SLUG=""

    run resolve-bot-identity.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolved bot name is 'github-actions[bot]'"* ]]
    [[ "$output" == *"Resolved user id is '41898282'"* ]]
    [[ "$output" == *"Resolved identity is 'github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>'"* ]]
}

@test "does not call the API when falling back" {
    export APP_SLUG=""

    # gh mock fails the test if invoked
    function gh() {
        echo "gh should not be called" >&2
        return 1
    }
    export -f gh

    run resolve-bot-identity.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"github-actions[bot]"* ]]
}
