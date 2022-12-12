setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR"/test_rp_prepare_ghoutput_"$RANDOM"'.log'
    > $GITHUB_OUTPUT

    export RP_LAUNCH_PREFIX=my-tests
    export RP_TOKEN=tok
    export RP_URL=https://rpserver:8080
    export RP_PROJECT=my-project
    export AUTO=true

    export BRANCH_NAME=main
    export GITHUB_SERVER_URL=https://github.com
    export GITHUB_REPOSITORY=mygh/repo
    export GITHUB_RUN_ID=3665876492
    export GITHUB_EVENT_NAME=push

    export ECHO_ENABLED="Report Portal key=my-tests-push-3665876492, url=https://rpserver:8080/ui/#my-project/launches/all"
    export ECHO_DISABLED="Report Portal not enabled: configuration not available"
    export DISABLED=$(cat << BATS
enabled=false
key=
url=
mvnopts=
BATS
)

}

teardown() {
    rm $GITHUB_OUTPUT
}

@test "rp disabled (no prefix)" {
    export RP_LAUNCH_PREFIX=""
    run get-rp-input.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no token)" {
    export RP_TOKEN=""
    run get-rp-input.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no url)" {
    export RP_URL=""
    run get-rp-input.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp disabled (no project)" {
    export RP_PROJECT=""
    run get-rp-input.sh
    [ "$status" -eq 0 ]
    [ "$(< $GITHUB_OUTPUT)" = "$DISABLED" ]
    [ "$output" = "$ECHO_DISABLED" ]
}

@test "rp enabled basic" {
    run get-rp-input.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
enabled=true
key=my-tests-push-3665876492
url=https://rpserver:8080/ui/#my-project/launches/all
mvn-opts="-Drp.launch=my-tests-push-3665876492" "-Drp.uuid=tok" "-Drp.endpoint=https://rpserver:8080" "-Drp.project=my-project" "-Drp.description=[Run on GitHub Actions 3665876492](https://github.com/mygh/repo/actions/runs/3665876492)" "-Drp.attributes=branch:main;event:push;repository:mygh/repo;run:my-tests-push-3665876492"
BATS
)
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$expected" ]
    [ "$output" = "$ECHO_ENABLED" ]
}

@test "rp enabled extra" {
    export RP_EXTRA_ATTRIBUTES=";metafilter:+smoke"

    run get-rp-input.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
enabled=true
key=my-tests-push-3665876492
url=https://rpserver:8080/ui/#my-project/launches/all
mvn-opts="-Drp.launch=my-tests-push-3665876492" "-Drp.uuid=tok" "-Drp.endpoint=https://rpserver:8080" "-Drp.project=my-project" "-Drp.description=[Run on GitHub Actions 3665876492](https://github.com/mygh/repo/actions/runs/3665876492)" "-Drp.attributes=branch:main;event:push;repository:mygh/repo;run:my-tests-push-3665876492;metafilter:+smoke"
BATS
)
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$expected" ]
    [ "$output" = "$ECHO_ENABLED" ]
}

@test "rp enabled not auto" {
    export AUTO="false"
    export RP_EXTRA_ATTRIBUTES=";metafilter:+smoke"
    export RP_LAUNCH_PREFIX="my-tests-with-id"

    run get-rp-input.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
enabled=true
key=my-tests-with-id
url=https://rpserver:8080/ui/#my-project/launches/all
mvn-opts="-Drp.launch=my-tests-with-id" "-Drp.uuid=tok" "-Drp.endpoint=https://rpserver:8080" "-Drp.project=my-project"
BATS
)
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$expected" ]
    expected_echo="Report Portal key=my-tests-with-id, url=https://rpserver:8080/ui/#my-project/launches/all"
    echo "$output"
    [ "$output" = "$expected_echo" ]
}

@test "rp enabled weird character in values" {

    export GITHUB_EVENT_NAME="weird event"
    export RP_LAUNCH_PREFIX="my launch prefix with spaces"
    export RP_TOKEN="with some more spaces"
    export RP_URL="https://rpserver:8080 with spaces too"
    export RP_PROJECT="my project with spaces"

    run get-rp-input.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
enabled=true
key=my launch prefix with spaces-weird event-3665876492
url=https://rpserver:8080 with spaces too/ui/#my project with spaces/launches/all
mvn-opts="-Drp.launch=my launch prefix with spaces-weird event-3665876492" "-Drp.uuid=with some more spaces" "-Drp.endpoint=https://rpserver:8080 with spaces too" "-Drp.project=my project with spaces" "-Drp.description=[Run on GitHub Actions 3665876492](https://github.com/mygh/repo/actions/runs/3665876492)" "-Drp.attributes=branch:main;event:weird event;repository:mygh/repo;run:my launch prefix with spaces-weird event-3665876492"
BATS
)
    echo "$(< $GITHUB_OUTPUT)"
    [ "$(< $GITHUB_OUTPUT)" = "$expected" ]
    expected_echo="Report Portal key=my launch prefix with spaces-weird event-3665876492, url=https://rpserver:8080 with spaces too/ui/#my project with spaces/launches/all"
    echo "$output"
    [ "$output" = "$expected_echo" ]
}
