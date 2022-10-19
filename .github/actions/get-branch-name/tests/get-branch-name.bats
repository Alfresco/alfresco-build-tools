setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_ENV=/dev/null
    export GITHUB_HEAD_REF="OPSEXP-1234"

    # Mock get-branch-name defaults
    export MAX_LENGTH="0"
    export SANITIZE="false"
}

@test "basic" {
    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Branch name is 'OPSEXP-1234'" ]
}

@test "sanitize" {
    export SANITIZE="true"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Branch name is 'opsexp-1234'" ]
}

@test "max-length" {
    export MAX_LENGTH="6"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Branch name is 'OPSEXP'" ]
}

@test "max-length and trailing dash" {
    export MAX_LENGTH="7"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Branch name is 'OPSEXP'" ]
}

@test "max-length and not trailing dash" {
    export MAX_LENGTH="9"

    run get-branch-name.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Branch name is 'OPSEXP-12'" ]
}
