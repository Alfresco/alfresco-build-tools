#!/usr/bin/env bats
setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_OUTPUT=/dev/null
    export GH_TOKEN="dummy"
    export APP_SLUG=""

    # Mock gh to resolve the user id from the queried /users/<bot> endpoint
    function gh() {
        if [ "$1" = "api" ]; then
            case "$2" in
                "/users/my-app[bot]") echo "12345678" ;;
                "/users/github-actions[bot]") echo "41898282" ;;
                *) echo "0" ;;
            esac
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

@test "falls back to github-actions[bot] and resolves its id via the API" {
    export APP_SLUG=""

    run resolve-bot-identity.sh

    [ "$status" -eq 0 ]
    [[ "$output" == *"Resolved bot name is 'github-actions[bot]'"* ]]
    [[ "$output" == *"Resolved user id is '41898282'"* ]]
    [[ "$output" == *"Resolved identity is 'github-actions[bot] <41898282+github-actions[bot]@users.noreply.github.com>'"* ]]
}

@test "fails when the API lookup fails" {
    export APP_SLUG="my-app"

    # gh mock returns a non-zero status to simulate an API failure
    function gh() {
        return 1
    }
    export -f gh

    run resolve-bot-identity.sh

    [ "$status" -ne 0 ]
}
