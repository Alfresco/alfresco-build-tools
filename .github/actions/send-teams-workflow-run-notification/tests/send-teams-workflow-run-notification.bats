setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"

    export GITHUB_EVENT_NAME="workflow_run"
    export REASON_CODE="attempts-exhausted"
    export BRANCH="release/25.5"
    export ATTEMPT="3"
    export MAX_ATTEMPTS="3"
    export TITLE="Release chain blocked"
    export SUBTITLE="Hop 1 of 5 - alfresco-community-repo"
    export MESSAGE="Nothing propagates to alfresco-enterprise-repo until this is resolved."
    export FACTS="Release version|26.3.0.85"
    export FOOTER="cc: release duty - please pick this up."
    export FAILED_JOBS='run_ci / PMD Scan
run_ci / REST API part1 TAS tests'
}

teardown() {
    rm -f "$GITHUB_OUTPUT"
}

title() {
    grep '^title=' "$GITHUB_OUTPUT" | cut -d= -f2-
}

message() {
    sed -n '/^message<<EOF_/,/^EOF_/p' "$GITHUB_OUTPUT" | sed '1d;$d'
}

extra_body() {
    grep '^extra-body=' "$GITHUB_OUTPUT" | cut -d= -f2-
}

fact_titles() {
    extra_body | jq -r '[.[] | select(.type=="FactSet").facts[].title] | join(",")'
}

fact() {
    extra_body | jq -r --arg t "$1" '.[] | select(.type=="FactSet").facts[] | select(.title==$t).value'
}

@test "builds a card for an exhausted retry budget" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(title)" = '🔴 Release chain blocked on `release/25.5`' ]
    [[ "$(message)" == *"Automated retries were exhausted."* ]]
}

@test "each reason code gets its own explanation" {
    for code in attempts-exhausted non-retryable nothing-to-retry; do
        > "$GITHUB_OUTPUT"
        REASON_CODE="$code" run build-card.sh
        [ "$status" -eq 0 ]
        [ -n "$(message)" ]
    done
}

@test "a non-retryable job is explained as such" {
    export REASON_CODE="non-retryable"
    run build-card.sh
    [[ "$(message)" == *"must not be re-run automatically"* ]]
}

@test "nothing to retry is explained as such" {
    export REASON_CODE="nothing-to-retry"
    run build-card.sh
    [[ "$(message)" == *"would change nothing"* ]]
}

@test "rejects an unknown reason code" {
    export REASON_CODE="made-up"
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"::error::reason-code must be"* ]]
}

@test "without a reason code the message stands alone" {
    export REASON_CODE=""
    export SUBTITLE=""
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(message)" = "Nothing propagates to alfresco-enterprise-repo until this is resolved." ]
}

@test "rejects a card that would explain nothing" {
    export REASON_CODE=""
    export MESSAGE=""
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"reason-code or message is required"* ]]
}

@test "rejects any event other than workflow_run" {
    export GITHUB_EVENT_NAME="push"
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"only works on a workflow_run event"* ]]
}

@test "the subtitle leads the message" {
    run build-card.sh
    [[ "$(message)" == "Hop 1 of 5 - alfresco-community-repo"* ]]
}

@test "the message follows the explanation" {
    export SUBTITLE=""
    run build-card.sh
    [ "$(message)" = "Automated retries were exhausted. Nothing propagates to alfresco-enterprise-repo until this is resolved." ]
}

@test "an omitted message leaves no trailing space" {
    export MESSAGE=""
    export SUBTITLE=""
    run build-card.sh
    [ "$(message)" = "Automated retries were exhausted." ]
}

@test "an omitted subtitle leaves the message starting with the explanation" {
    export SUBTITLE=""
    run build-card.sh
    [[ "$(message)" == "Automated retries were exhausted."* ]]
}

@test "an omitted branch leaves the title alone" {
    export BRANCH=""
    run build-card.sh
    [ "$(title)" = "🔴 Release chain blocked" ]
}

@test "a custom title is used" {
    export TITLE="Nightly build blocked"
    run build-card.sh
    [ "$(title)" = '🔴 Nightly build blocked on `release/25.5`' ]
}

@test "the title falls back to a wording any watcher can use" {
    unset TITLE
    run build-card.sh
    [ "$(title)" = '🔴 Workflow run failed on `release/25.5`' ]
}

@test "the attempt is reported against the budget" {
    run build-card.sh
    [ "$(fact Attempt)" = "3 of 3" ]
}

@test "the attempt stands alone when no budget is given" {
    export MAX_ATTEMPTS=""
    run build-card.sh
    [ "$(fact Attempt)" = "3" ]
}

@test "rejects an attempt that is not a positive number" {
    export ATTEMPT="0"
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"attempt must be a positive whole number"* ]]
}

@test "rejects a missing attempt rather than assuming one" {
    unset ATTEMPT
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"attempt must be a positive whole number"* ]]
}

@test "no facts leaves only the attempt" {
    export FACTS=""
    run build-card.sh
    [ "$(fact_titles)" = "Attempt" ]
}

@test "facts are added after the attempt in the given order" {
    export FACTS="Release version|26.3.0.85
Owner|release duty"
    run build-card.sh
    [ "$(fact_titles)" = "Attempt,Release version,Owner" ]
    [ "$(fact 'Release version')" = "26.3.0.85" ]
    [ "$(fact Owner)" = "release duty" ]
}

@test "a fact value keeps commas and later separators" {
    export FACTS="Modules|repo, share|community"
    run build-card.sh
    [ "$(fact Modules)" = "repo, share|community" ]
}

@test "blank lines and padding around facts are ignored" {
    export FACTS='
  Release version | 26.3.0.85

'
    run build-card.sh
    [ "$(fact_titles)" = "Attempt,Release version" ]
    [ "$(fact 'Release version')" = "26.3.0.85" ]
}

@test "rejects a fact without a separator" {
    export FACTS="Release version 26.3.0.85"
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"must be in the format"* ]]
}

@test "failed jobs are listed one per line" {
    run build-card.sh
    [[ "$(extra_body)" == *'- run\\_ci / PMD Scan\n- run\\_ci / REST API part1 TAS tests'* ]]
}

@test "markdown characters in a job name are escaped" {
    export FAILED_JOBS='build [x86] *fast* `quick` a_b'
    run build-card.sh
    [[ "$(extra_body)" == *'build \\[x86\\] \\*fast\\* \\`quick\\` a\\_b'* ]]
}

@test "blank lines and indentation in failed jobs are ignored" {
    export FAILED_JOBS='
  Push to Nexus

      Parse commit metadata
'
    run build-card.sh
    [[ "$(extra_body)" == *'- Push to Nexus\n- Parse commit metadata'* ]]
}

@test "no failed jobs still produces a readable list" {
    export FAILED_JOBS=""
    run build-card.sh
    [[ "$(extra_body)" == *"- none reported"* ]]
}

@test "the footer is appended when given" {
    run build-card.sh
    [ "$(extra_body | jq -r '.[-1].text')" = "cc: release duty - please pick this up." ]
}

@test "an omitted footer drops the line" {
    export FOOTER=""
    run build-card.sh
    [ "$(extra_body | jq -r '.[-1].type')" = "Container" ]
}

@test "the extra body is a JSON array" {
    run build-card.sh
    [ "$(extra_body | jq -r 'type')" = "array" ]
}

@test "a quote in the message does not break the output" {
    export MESSAGE='The "release" job must be checked.'
    run build-card.sh
    [ "$status" -eq 0 ]
    [[ "$(message)" == *'The "release" job must be checked.'* ]]
}

@test "fails when GITHUB_OUTPUT is not set" {
    unset GITHUB_OUTPUT
    run build-card.sh
    [ "$status" -ne 0 ]
    [[ "$output" == *"GITHUB_OUTPUT is not set"* ]]
}

cc_line() {
    extra_body | jq -r '[.[] | select(.type=="TextBlock" and .isSubtle == null)] | first | .text // ""'
}

mention_users() {
    grep '^mention-users=' "$GITHUB_OUTPUT" | cut -d= -f2-
}

@test "no cc line and no mentions when cc is not set" {
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "" ]
    [ "$(mention_users)" = "" ]
}

@test "an entry with an email becomes an at marker and an entity" {
    export CC="Jakub Kochman|jakub.kochman@hyland.com,Luis Medalhas|LuisFilipe.ValenteMedalhas@hyland.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: <at>Jakub Kochman</at>, <at>Luis Medalhas</at>" ]
    [ "$(mention_users)" = "Jakub Kochman|jakub.kochman@hyland.com,Luis Medalhas|LuisFilipe.ValenteMedalhas@hyland.com" ]
}

@test "an entry without an email is shown as text and mentions nobody" {
    export CC="Jakub Kochman|jakub.kochman@hyland.com,@gerardolenski,@damianujma"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: <at>Jakub Kochman</at>, [@gerardolenski](https://github.com/gerardolenski), [@damianujma](https://github.com/damianujma)" ]
    [ "$(mention_users)" = "Jakub Kochman|jakub.kochman@hyland.com" ]
}

@test "the order given is the order shown" {
    export CC="@gerardolenski,Jakub Kochman|jakub.kochman@hyland.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: [@gerardolenski](https://github.com/gerardolenski), <at>Jakub Kochman</at>" ]
}

@test "plain entries alone still produce a cc line" {
    export CC="@gerardolenski"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: [@gerardolenski](https://github.com/gerardolenski)" ]
    [ "$(mention_users)" = "" ]
}

@test "an underscore in a plain entry is escaped rather than read as markdown" {
    export CC="@some_user_name"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = 'cc: @some\_user\_name' ]
}

@test "a handle keeps its hyphens and points at the profile" {
    export CC="@dpatel-alfresco"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = 'cc: [@dpatel-alfresco](https://github.com/dpatel-alfresco)' ]
}

@test "an enterprise server is linked to instead of github.com" {
    export CC="@gerardolenski"
    export GITHUB_SERVER_URL="https://github.example.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = 'cc: [@gerardolenski](https://github.example.com/gerardolenski)' ]
}

@test "a display name with no handle is shown as text, not as a link" {
    export CC="Old Laptop"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: Old Laptop" ]
}

@test "mention-users and cc are merged without repeating anyone" {
    export MENTION_USERS="Jakub Kochman|jakub.kochman@hyland.com"
    export CC="Jakub Kochman|jakub.kochman@hyland.com,Luis Medalhas|LuisFilipe.ValenteMedalhas@hyland.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(mention_users)" = "Jakub Kochman|jakub.kochman@hyland.com,Luis Medalhas|LuisFilipe.ValenteMedalhas@hyland.com" ]
}

@test "the cc line sits above the footer" {
    export CC="@gerardolenski"
    run build-card.sh
    [ "$status" -eq 0 ]
    texts=$(extra_body | jq -r '[.[] | select(.type=="TextBlock") | .text] | join("~")')
    [[ "$texts" == *"cc: [@gerardolenski](https://github.com/gerardolenski)~cc: release duty"* ]]
}

@test "a cc entry with a separator but no email degrades to plain text" {
    export CC="Alice A|alice.a@hyland.com,Jakub Kochman|"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: <at>Alice A</at>, Jakub Kochman" ]
    [ "$(mention_users)" = "Alice A|alice.a@hyland.com" ]
    [[ "$output" == *"::warning::cc entry"* ]]
}

@test "a cc entry with an email but no name degrades to plain text" {
    export CC="|alice.a@hyland.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: alice.a@hyland.com" ]
    [ "$(mention_users)" = "" ]
}

@test "a cc entry that is only a separator is dropped" {
    export CC="|,Alice A|alice.a@hyland.com"
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: <at>Alice A</at>" ]
}

@test "blank entries and stray spaces in cc are ignored" {
    export CC=" Jakub Kochman|jakub.kochman@hyland.com ,, @gerardolenski , "
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "cc: <at>Jakub Kochman</at>, [@gerardolenski](https://github.com/gerardolenski)" ]
}

@test "an empty cc leaves the footer alone, so a group mention still goes out" {
    export MENTION_TAGS="Release Duty|dGFnaWQ="
    run build-card.sh
    [ "$status" -eq 0 ]
    [ "$(cc_line)" = "" ]
    extra_body | jq -e '[.[] | select(.isSubtle == true) | .text] | index("cc: release duty - please pick this up.")' >/dev/null
}
