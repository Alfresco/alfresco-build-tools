setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR"/test-get-teams-message_ghoutput_"$RANDOM"'.log'
    > $GITHUB_OUTPUT

    export RP_LAUNCH_KEY=my-tests-push-3665876492
    export RP_TOKEN=tok
    export RP_URL=https://rpserver:8080

    export RP_CONTENT=""
    export RP_LAUNCH_URL=https://rpserver:8080/ui/#my-project/launches/all

    export NO_MESSAGE="message="
    export KEY_NO_REPORT="message=No report found for key \`my-tests-push-3665876492\`.\n\nSee [latest reports](https://rpserver:8080/ui/#my-project/launches/all)."
    export SINGLE_REPORT="message=See [report](https://rpserver:8080/ui/#my-project/launches/all/88) ✅"
    export MULTIPLE_REPORTS=$(cat << BATS
message=3 reports found for key \`my-tests-push-3665876492\`.\n\n[Report #3](https://rpserver:8080/ui/#my-project/launches/all/91) ❌\n\n[Report #2](https://rpserver:8080/ui/#my-project/launches/all/90) WHATEVER_STATUS\n\n[Report #1](https://rpserver:8080/ui/#my-project/launches/all/89) ✅
BATS
)
}

teardown() {
    rm -f $GITHUB_OUTPUT
}

@test "teams message rp disabled" {
    export RP_LAUNCH_KEY=""
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$NO_MESSAGE" ]
}

@test "teams message no launch id" {
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "teams message single" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launch.json)"
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$SINGLE_REPORT" ]
}

@test "teams message multiple" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launches.json)"
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$MULTIPLE_REPORTS" ]
}

@test "teams message rp failure no results" {
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "teams message rp failure no results empty json" {
    export RP_CONTENT="{}"
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "teams message rp success no results" {
    export OUTCOME="success"
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/empty-launch.json)"
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$KEY_NO_REPORT" ]
}

@test "teams message rp failure no results empty json no launch key" {
    export RP_LAUNCH_KEY=""
    export RP_CONTENT="{}"
    run get-teams-message.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$NO_MESSAGE" ]

}
