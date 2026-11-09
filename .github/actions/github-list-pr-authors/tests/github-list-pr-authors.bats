setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export API_RETRY_DELAY="0"
    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"
    export MOCK_FLAG="$BATS_TMPDIR/mock_flag_${RANDOM}"
    rm -f "$MOCK_FLAG"

    export REPOSITORY="Alfresco/acs-packaging"
    export FROM_REF="1.0.0"
    export TO_REF="1.0.1"
    export MENTION_EMAIL_DOMAIN="hyland.com"

    # Two humans and one release-plugin commit that no pull request produced.
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}},
        {"sha":"bbbbbbbbbb","author":{"login":"bob"},
         "commit":{"author":{"name":"Bob B","email":"2+bob@users.noreply.github.com"}}},
        {"sha":"cccccccccc","author":{"login":"alfresco-build"},
         "commit":{"author":{"name":"build","email":"build@example.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"ACS-1 fix the thing","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}],
        "bbbbbbbbbb":[{"number":12,"title":"ACS-2 another thing","html_url":"p/12",
                       "merged_at":"2026-01-02T00:00:00Z","user":{"login":"bob"}}],
        "cccccccccc":[]
    }'
    export MOCK_MERGED_BY="dave"

    mock_gh
}

teardown() { rm -f "$GITHUB_OUTPUT" "$MOCK_FLAG"; }

output_var() { grep "^${1}=" "$GITHUB_OUTPUT" | cut -d= -f2-; }

assert_output_var() {
    local actual; actual=$(output_var "$1")
    [ "$actual" = "$2" ] || { echo "Expected ${1}=${2}, got ${1}=${actual}" >&2; return 1; }
}

changes_json() { sed -n '/^changes<</,/^EOF_/p' "$GITHUB_OUTPUT" | sed '1d;$d'; }

# Keyed on the request path, applying the real jq so the filters in the script are exercised.
mock_gh() {
    gh() {
        local url="" jq_expr="" use_jq=0 body="" sha=""
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
                case "${MOCK_COMPARE_FAILS:-}" in
                    true) echo "gh: Not Found (HTTP 404)" >&2; return 1 ;;
                    flaky)
                        # A command substitution runs in a subshell, so the one-shot
                        # failure is tracked in a file rather than a variable.
                        if [ ! -e "$MOCK_FLAG" ]; then
                            : > "$MOCK_FLAG"
                            echo "gh: Bad Gateway (HTTP 502)" >&2; return 1
                        fi ;;
                esac
                body="$MOCK_COMPARE" ;;
            *"/commits/"*"/pulls")
                if [ "${MOCK_PULLS_FAIL:-}" = "true" ]; then
                    echo "gh: Not Found (HTTP 404)" >&2; return 1
                fi
                sha="${url#*/commits/}"; sha="${sha%%/*}"
                body=$(jq -c --arg s "$sha" '.[$s] // []' <<<"$MOCK_PULLS") ;;
            *"/pulls/"*)
                if [ "${MOCK_MERGER_FAILS:-}" = "true" ]; then
                    echo "gh: Not Found (HTTP 404)" >&2; return 1
                fi
                body="{\"merged_by\":{\"login\":\"$MOCK_MERGED_BY\"}}" ;;
            *)
                echo "unexpected gh invocation: $url" >&2; return 1 ;;
        esac

        if [ "$use_jq" -eq 1 ]; then printf '%s' "$body" | jq -r "$jq_expr"
        else printf '%s' "$body"; fi
    }
    export -f gh
}

@test "collects the humans behind the pull requests in range" {
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
    assert_output_var "count" "2"
    assert_output_var "truncated" "false"
}

@test "a commit with no pull request behind it is left out" {
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    [[ "$(changes_json)" != *"alfresco-build"* ]]
}

@test "the pull request is reported, not the commit subject" {
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    [ "$(changes_json | jq -r '[.[].pr] | join(",")')" = "11,12" ]
    [ "$(changes_json | jq -r '.[0].title')" = "ACS-1 fix the thing" ]
}

@test "several commits of one pull request are reported once" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}},
        {"sha":"a2a2a2a2a2","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}],
        "a2a2a2a2a2":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "1"
    assert_output_var "people" "alice"
}

@test "a merged pull request is chosen over an open one holding the same commit" {
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":99,"title":"still open","html_url":"p/99",
                       "merged_at":null,"user":{"login":"mallory"}},
                      {"number":11,"title":"ACS-1 fix the thing","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}],
        "bbbbbbbbbb":[],
        "cccccccccc":[]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice"
}

@test "a commit held only by an open pull request is not reported" {
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":99,"title":"still open","html_url":"p/99",
                       "merged_at":null,"user":{"login":"mallory"}}],
        "bbbbbbbbbb":[],
        "cccccccccc":[]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "0"
    assert_output_var "people" ""
}

@test "a company address survives a later commit under a noreply one" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}},
        {"sha":"a2a2a2a2a2","author":{"login":"alice"},
         "commit":{"author":{"name":"alice","email":"9+alice@users.noreply.github.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}],
        "a2a2a2a2a2":[{"number":12,"title":"t2","html_url":"p/12",
                       "merged_at":"2026-01-02T00:00:00Z","user":{"login":"alice"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com"
}

@test "a comma in a display name does not split the cc list" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Appleby, Alice | A","email":"alice.a@hyland.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Appleby Alice A|alice.a@hyland.com"
}

@test "somebody who authored a pull request is not repeated as a merger" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}},
        {"sha":"1111111111","author":{"login":"dependabot[bot]"},
         "commit":{"author":{"name":"dependabot[bot]","email":"49699333+dependabot[bot]@users.noreply.github.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}],
        "1111111111":[{"number":14,"title":"bump","html_url":"p/14",
                       "merged_at":"2026-01-03T00:00:00Z","user":{"login":"dependabot[bot]"}}]
    }'
    export MOCK_MERGED_BY="alice"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com"
    assert_output_var "people" "alice"
}

@test "says the list is partial when a merger lookup fails" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"1111111111","author":{"login":"dependabot[bot]"},
         "commit":{"author":{"name":"dependabot[bot]","email":"d@users.noreply.github.com"}}}
    ]}'
    export MOCK_PULLS='{
        "1111111111":[{"number":14,"title":"bump","html_url":"p/14",
                       "merged_at":"2026-01-03T00:00:00Z","user":{"login":"dependabot[bot]"}}]
    }'
    export MOCK_MERGER_FAILS="true"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "bots" "dependabot[bot]"
    assert_output_var "people" ""
    assert_output_var "truncated" "true"
    [[ "$output" == *"Could not look up who merged"* ]]
}

@test "a direct push authored by a human is still left out" {
    export MOCK_PULLS='{"aaaaaaaaaa":[],"bbbbbbbbbb":[],"cccccccccc":[]}'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "0"
    assert_output_var "people" ""
}

@test "without a mention domain everybody keeps their handle" {
    export MENTION_EMAIL_DOMAIN=""
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "@alice,@bob"
}

@test "names the bot and mentions whoever merged its pull request" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"1111111111","author":{"login":"dependabot[bot]"},
         "commit":{"author":{"name":"dependabot[bot]","email":"49699333+dependabot[bot]@users.noreply.github.com"}}}
    ]}'
    export MOCK_PULLS='{
        "1111111111":[{"number":14,"title":"Bump the github-actions group","html_url":"p/14",
                       "merged_at":"2026-01-03T00:00:00Z","user":{"login":"dependabot[bot]"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "bots" "dependabot[bot]"
    assert_output_var "people" "dave"
    assert_output_var "cc" "@dave"
}

@test "an author with no commit of their own in range keeps their handle" {
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"carol"}}],
        "bbbbbbbbbb":[],
        "cccccccccc":[]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "@carol"
    [ "$(changes_json | jq -r '.[0].name')" = "carol" ]
}

@test "a failed comparison warns instead of ending the run" {
    export MOCK_COMPARE_FAILS="true"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "0"
    assert_output_var "truncated" "true"
    [[ "$output" == *"::warning::"* ]]
}

@test "a server error is retried before the call is believed" {
    export MOCK_COMPARE_FAILS="flaky"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
    assert_output_var "truncated" "false"
}

@test "says the list is partial when the comparison is longer than one page" {
    export MOCK_COMPARE="$(jq -c '. + {total_commits: 400}' <<<"$MOCK_COMPARE")"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "people" "alice,bob"
    assert_output_var "truncated" "true"
    [[ "$output" == *"longer than one page"* ]]
}

@test "says the list is partial when a pull request lookup fails" {
    export MOCK_PULLS_FAIL="true"
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "count" "0"
    assert_output_var "truncated" "true"
    [[ "$output" == *"Could not look up the pull request"* ]]
}

@test "requires the refs" {
    unset TO_REF
    run github-list-pr-authors.sh
    [ "$status" -ne 0 ]
}

@test "an address in the mention domain carries its email, the rest keep their handle" {
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com,@bob"
}

@test "an address outside the domain stays a plain handle, with no stray separator" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"ffffffffff","author":{"login":"tiago"},
         "commit":{"author":{"name":"Tiago S","email":"tiago@gmail.com"}}}
    ]}'
    export MOCK_PULLS='{
        "ffffffffff":[{"number":13,"title":"t","html_url":"p/13",
                       "merged_at":"2026-01-04T00:00:00Z","user":{"login":"tiago"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "@tiago"
}

@test "everybody mentionable leaves no trailing separator" {
    export MOCK_COMPARE='{"commits":[
        {"sha":"aaaaaaaaaa","author":{"login":"alice"},
         "commit":{"author":{"name":"Alice A","email":"alice.a@hyland.com"}}}
    ]}'
    export MOCK_PULLS='{
        "aaaaaaaaaa":[{"number":11,"title":"t","html_url":"p/11",
                       "merged_at":"2026-01-01T00:00:00Z","user":{"login":"alice"}}]
    }'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" "Alice A|alice.a@hyland.com"
}

@test "cc is empty when no pull requests are in range" {
    export MOCK_COMPARE='{"commits":[]}'
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    assert_output_var "cc" ""
    assert_output_var "count" "0"
}

@test "the repository is reported on every row" {
    run github-list-pr-authors.sh
    [ "$status" -eq 0 ]
    [ "$(changes_json | jq -r '[.[].repo] | unique | join(",")')" = "Alfresco/acs-packaging" ]
}
