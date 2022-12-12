setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_STEP_SUMMARY="$BATS_TMPDIR"/test-write-step-summary_ghstep_"$RANDOM"'.log'
    > $GITHUB_STEP_SUMMARY

    export RP_LAUNCH_KEY=my-tests-push-3665876492
    export RP_TOKEN=tok
    export RP_URL=https://rpserver:8080
    export RP_LAUNCH_URL=https://rpserver:8080/ui/#my-project/launches/all

    export OUTCOME="failure"

    export KEY_NO_REPORT=$(cat << BATS
#### 📋 Results: ✅
- No report found for key \`my-tests-push-3665876492\`
- See [latest reports](https://rpserver:8080/ui/#my-project/launches/all)
BATS
)

}

teardown() {
    rm -f $GITHUB_STEP_SUMMARY
}

@test "step summary rp disabled failure" {
    export RP_LAUNCH_KEY=""
    run write-step-summary.sh
    [ "$status" -eq 0 ]

    expected="#### 📋 Results: ❌"
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}

@test "step summary rp single success" {
    export OUTCOME="success"
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launch.json)"

    run write-step-summary.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
#### 📋 Results: ✅
See [report](https://rpserver:8080/ui/#my-project/launches/all/88)
BATS
)
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}

@test "step summary rp success no launch id" {
    export OUTCOME="success"
    export RP_CONTENT=""
    run write-step-summary.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$KEY_NO_REPORT" ]
}

@test "step summary rp single failure" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launch.json)"

    run write-step-summary.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
#### 📋 Results: ❌
See [report](https://rpserver:8080/ui/#my-project/launches/all/88)
BATS
)
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}

@test "step summary rp multiple failure" {
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/sample-launches.json)"

    run write-step-summary.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
#### 📋 Results: ❌
3 reports found for key \`my-tests-push-3665876492\`
- [Report #3](https://rpserver:8080/ui/#my-project/launches/all/91) ❌
- [Report #2](https://rpserver:8080/ui/#my-project/launches/all/90) WHATEVER_STATUS
- [Report #1](https://rpserver:8080/ui/#my-project/launches/all/89) ✅
BATS
)
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}

@test "step summary rp failure no results" {
    export RP_CONTENT=""

    run write-step-summary.sh
    [ "$status" -eq 0 ]

    expected=$(cat << BATS
#### 📋 Results: ❌
- No report found for key \`my-tests-push-3665876492\`
- See [latest reports](https://rpserver:8080/ui/#my-project/launches/all)
BATS
)
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}

@test "step summary rp success no results empty json" {
    export OUTCOME="success"
    export RP_CONTENT="{}"
    run write-step-summary.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$KEY_NO_REPORT" ]
}

@test "step summary rp success no results" {
    export OUTCOME="success"
    export RP_CONTENT="$(< $BATS_TEST_DIRNAME/empty-launch.json)"
    run write-step-summary.sh
    [ "$status" -eq 0 ]
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$KEY_NO_REPORT" ]
}

@test "step summary rp failure no results empty json no launch key" {
    export RP_LAUNCH_KEY=""
    export RP_CONTENT="{}"
    run write-step-summary.sh
    [ "$status" -eq 0 ]
    expected="#### 📋 Results: ❌"
    echo "$(< $GITHUB_STEP_SUMMARY)"
    [ "$(< $GITHUB_STEP_SUMMARY)" = "$expected" ]
}
