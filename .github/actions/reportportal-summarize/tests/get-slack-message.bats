setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR"/test-get-slack-message_ghoutput_"$RANDOM"'.log'
    > $GITHUB_OUTPUT

    export RP_LAUNCH_KEY=my-tests-push-3665876492
    export RP_TOKEN=tok
    export RP_URL=https://rpserver:8080

    export RP_CONTENT=""
    export RP_LAUNCH_URL=https://rpserver:8080/ui/#my-project/launches/all

    export NO_MESSAGE="message="
    export KEY_NO_REPORT="message=No report found for key \`my-tests-push-3665876492\`.\nSee <https://rpserver:8080/ui/#my-project/launches/all|latest reports>."
    export SINGLE_REPORT="message=See <https://rpserver:8080/ui/#my-project/launches/all/88|report>"
    export MULTIPLE_REPORTS=$(cat << BATS
message=3 reports found for key \`my-tests-push-3665876492\`.\n<https://rpserver:8080/ui/#my-project/launches/all/91|Report #3> ❌\n<https://rpserver:8080/ui/#my-project/launches/all/90|Report #2> WHATEVER_STATUS\n<https://rpserver:8080/ui/#my-project/launches/all/89|Report #1> ✅
BATS
)
}

teardown() {
    rm -f $GITHUB_OUTPUT
}

@test "slack message rp disabled" {
    export RP_LAUNCH_KEY=""
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$NO_MESSAGE" ]
}

@test "slack message no launch id" {
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "slack message single" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launch.json)"
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$SINGLE_REPORT" ]
}

@test "slack message multiple" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launches.json)"
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$MULTIPLE_REPORTS" ]
}

@test "slack message rp failure no results" {
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "slack message rp failure no results empty json" {
    export RP_CONTENT="{}"
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "slack message rp success no results" {
    export OUTCOME="success"
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/empty-launch.json)"
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "slack message rp failure no results empty json no launch key" {
    export RP_LAUNCH_KEY=""
    export RP_CONTENT="{}"
    run get-slack-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$NO_MESSAGE" ]

}
