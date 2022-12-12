setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR"/test-get-rp-output_ghoutput_"$RANDOM"'.log'
    > $GITHUB_OUTPUT

    export RP_LAUNCH_KEY=my-tests-push-3665876492
    export RP_TOKEN=tok
    export RP_URL=https://rpserver:8080

    export ECHO_DISABLED="Report Portal not enabled: configuration not available"
    export DISABLED=$(cat << BATS
enabled=false
content=
url=
BATS
)
}

teardown() {
    rm -f $GITHUB_OUTPUT
}

@test "rp disabled (no key)" {
    export RP_LAUNCH_KEY=""
    run get-rp-output.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no token)" {
    export RP_TOKEN=""
    run get-rp-output.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no url)" {
    export RP_URL=""
    run get-rp-output.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no project)" {
    export RP_PROJECT=""
    run get-rp-output.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "slack message rp disabled" {
    export RP_LAUNCH_KEY=""
    run get-slack-message.sh
    [ "$status" -eq 0 ]

    expected="message="
    [ "$(< $GITHUB_OUTPUT)" = "$expected" ]
}
