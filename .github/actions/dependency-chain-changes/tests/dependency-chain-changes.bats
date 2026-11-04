setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export API_RETRY_DELAY="0"
    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"

    export REPOSITORY="Alfresco/acs-packaging"
    export FROM_REF="1.0.0"
    export TO_REF="1.0.1"
    export MENTION_DOMAIN="hyland.com"
    export UPSTREAM=""
    export MAX_DEPTH="3"

    # Two humans and one release-plugin commit that no pull request produced.
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"aaaaaaaaaa","html_url":"u/1","author":{"login":"alice"},
         "commit":{"message":"ACS-1 fix the thing (#11)","author":{"name":"Alice A","email":"alice.a@hyland.com"}}},
        {"sha":"bbbbbbbbbb","html_url":"u/2","author":{"login":"bob"},
         "commit":{"message":"ACS-2 another thing (#12)","author":{"name":"Bob B","email":"2+bob@users.noreply.github.com"}}},
        {"sha":"cccccccccc","html_url":"u/3","author":{"login":"alfresco-build"},
         "commit":{"message":"[maven-release-plugin][skip ci] prepare release 1.0.1","author":{"name":"build","email":"build@example.com"}}}
    ]}'
    export MOCK_COMPARE_UP='{"commits":[
        {"sha":"dddddddddd","html_url":"u/4","author":{"login":"carol"},
         "commit":{"message":"ACS-3 upstream change (#21)","author":{"name":"Carol C","email":"carol.c@hyland.com"}}}
    ]}'
    export MOCK_VERSION_FROM="2.0.0"
    export MOCK_VERSION_TO="2.0.1"
    export MOCK_MERGED_BY="dave"

    mock_gh
}

teardown() { rm -f "$GITHUB_OUTPUT"; }

output_var() { grep "^${1}=" "$GITHUB_OUTPUT" | cut -d= -f2-; }

assert_output_var() {
    local actual; actual=$(output_var "$1")
    [ "$actual" = "$2" ] || { echo "Expected ${1}=${2}, got ${1}=${actual}" >&2; return 1; }
}

changes_json() { sed -n '/^changes<</,/^EOF_/p' "$GITHUB_OUTPUT" | sed '1d;$d'; }

# Keyed on the request path, applying the real jq so the filters in the script are exercised.
mock_gh() {
    gh() {
        local url="" jq_expr="" use_jq=0 body=""
        while [ $# -gt 0 ]; do
            case "$1" in
                --jq) jq_expr="$2"; use_jq=1; shift 2 ;;
                -H) shift 2 ;;
                repos/*) url="$1"; shift ;;
                *) shift ;;
            esac
        done

        case "$url" in
            *"/compare/"*)
                if [ "${MOCK_COMPARE_FAILS:-}" = "true" ]; then
                    echo "gh: Not Found (HTTP 404)" >&2; return 1
                fi
                case "$url" in
                    *acs-packaging*) body="$MOCK_COMPARE_ROOT" ;;
                    *) body="$MOCK_COMPARE_UP" ;;
                esac ;;
            *"/contents/"*)
                local v="$MOCK_VERSION_TO"
                case "$url" in *"ref=$FROM_REF"*) v="$MOCK_VERSION_FROM" ;; esac
                body="{\"content\":\"$(printf '<dependency.up.version>%s</dependency.up.version>' "$v" | base64)\"}" ;;
            *"/pulls/"*)
                body="{\"merged_by\":{\"login\":\"$MOCK_MERGED_BY\"}}" ;;
            *)
                echo "unexpected gh invocation: $url" >&2; return 1 ;;
        esac

        if [ "$use_jq" -eq 1 ]; then printf '%s' "$body" | jq -r "$jq_expr"
        else printf '%s' "$body"; fi
    }
    export -f gh
}

edge() {
    echo 'Alfresco/acs-packaging | Alfresco/alfresco-enterprise-repo | pom.xml | <dependency\.up\.version>([^<]*)< | {version}'
}

@test "collects the humans behind the pull requests in range" {
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
    assert_output_var "count" "2"
    assert_output_var "truncated" "false"
}

@test "a commit with no pull request behind it is left out" {
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    [[ "$(changes_json)" != *"alfresco-build"* ]]
}

@test "a merge commit subject is recognised too" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"eeeeeeeeee","html_url":"u/9","author":{"login":"erin"},
         "commit":{"message":"Merge pull request #77 from Alfresco/topic","author":{"name":"Erin E","email":"erin.e@hyland.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "erin"
}

@test "splits mentionable from plain on the email domain" {
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "mentionable" "Alice A|alice.a@hyland.com"
    assert_output_var "plain" "@bob"
}

@test "an address outside the domain stays a plain handle" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"ffffffffff","html_url":"u/5","author":{"login":"tiago"},
         "commit":{"message":"ACS-9 thing (#13)","author":{"name":"Tiago S","email":"tiago@gmail.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "mentionable" ""
    assert_output_var "plain" "@tiago"
}

@test "without a mention domain everybody is plain" {
    export MENTION_DOMAIN=""
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "mentionable" ""
    assert_output_var "plain" "@alice,@bob"
}

@test "names the bot and mentions whoever merged its pull request" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"1111111111","html_url":"u/6","author":{"login":"dependabot[bot]"},
         "commit":{"message":"Bump the github-actions group (#14)","author":{"name":"dependabot[bot]","email":"49699333+dependabot[bot]@users.noreply.github.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "bots" "dependabot[bot]"
    assert_output_var "people" "dave"
    assert_output_var "plain" "@dave"
}

@test "follows an upstream whose pinned version moved" {
    export UPSTREAM="$(edge)"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob,carol"
    assert_output_var "count" "3"
}

@test "does not follow an upstream whose version is unchanged" {
    export UPSTREAM="$(edge)"
    export MOCK_VERSION_FROM="2.0.0"
    export MOCK_VERSION_TO="2.0.0"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
}

@test "an edge for another repository is ignored" {
    export UPSTREAM='Alfresco/somewhere-else | Alfresco/alfresco-enterprise-repo | pom.xml | <v>([^<]*)< | {version}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
}

@test "stops at max-depth and says so" {
    export UPSTREAM="$(edge)"
    export MAX_DEPTH="1"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
    assert_output_var "truncated" "true"
}

@test "comments and blank lines in the edge list are ignored" {
    export UPSTREAM="# a comment
$(edge)

"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob,carol"
}

@test "a failed comparison warns instead of ending the run" {
    export MOCK_COMPARE_FAILS="true"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "0"
    [[ "$output" == *"::warning::"* ]]
}

@test "rejects a max-depth that is not a positive number" {
    export MAX_DEPTH="0"
    run dependency-chain-changes.sh
    [ "$status" -eq 1 ]
    [[ "$output" == *"max-depth must be a positive whole number"* ]]
}

@test "requires the refs" {
    unset TO_REF
    run dependency-chain-changes.sh
    [ "$status" -ne 0 ]
}

@test "cc joins the mentionable and plain lists" {
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com,@bob"
}

@test "cc carries no stray separator when nobody is mentionable" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"ffffffffff","html_url":"u/5","author":{"login":"tiago"},
         "commit":{"message":"ACS-9 thing (#13)","author":{"name":"Tiago S","email":"tiago@gmail.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "@tiago"
}

@test "cc carries no stray separator when everybody is mentionable" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"ffffffffff","html_url":"u/5","author":{"login":"alice"},
         "commit":{"message":"ACS-9 thing (#13)","author":{"name":"Alice A","email":"alice.a@hyland.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com"
}

@test "cc is empty when no humans are in range" {
    export MOCK_COMPARE_ROOT='{"commits":[]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" ""
}

@test "an author GitHub cannot match to an account is named rather than dropped" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"ffffffffff","html_url":"u/5","author":null,
         "commit":{"message":"ACS-9 thing (#13)","author":{"name":"Old Laptop","email":"someone@oldcompany.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "plain" "Old Laptop"
    assert_output_var "cc" "Old Laptop"
}

@test "an unmatched author inside the domain is still mentionable by email" {
    export MOCK_COMPARE_ROOT='{"commits":[
        {"sha":"ffffffffff","html_url":"u/5","author":null,
         "commit":{"message":"ACS-9 thing (#13)","author":{"name":"Old Laptop","email":"old.laptop@hyland.com"}}}
    ]}'
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "mentionable" "Old Laptop|old.laptop@hyland.com"
    assert_output_var "plain" ""
}

@test "a hash inside an edge regex is not taken for a comment" {
    export UPSTREAM="  # an indented comment is still ignored
Alfresco/acs-packaging | Alfresco/alfresco-enterprise-repo | pom.xml | <dependency\.up\.version>([^<#]*)< | {version}"
    run dependency-chain-changes.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob,carol"
}
