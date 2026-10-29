#!/usr/bin/env bats

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/check_readme.sh"
    TMP="$(mktemp -d)"
    mkdir -p "$TMP/actions/foo" "$TMP/actions/foo-bar"
    touch "$TMP/actions/foo/action.yml" "$TMP/actions/foo-bar/action.yml"
}

teardown() {
    rm -rf "$TMP"
}

@test "passes when every action has a heading" {
    printf '### foo\n\n### foo-bar\n' > "$TMP/README.md"

    run "$SCRIPT" --actions-dir "$TMP/actions" --readme-file "$TMP/README.md"

    [ "$status" -eq 0 ]
}

@test "fails when an action is only a prefix of another documented action" {
    printf '### foo-bar\n' > "$TMP/README.md"

    run "$SCRIPT" --actions-dir "$TMP/actions" --readme-file "$TMP/README.md"

    [ "$status" -eq 1 ]
    [[ "$output" == *"No entry found for ### foo in"* ]]
}

@test "does not fail within the allowed number of missing entries" {
    printf '### foo-bar\n' > "$TMP/README.md"

    run "$SCRIPT" --actions-dir "$TMP/actions" --readme-file "$TMP/README.md" --missing-entries 1

    [ "$status" -eq 0 ]
    [[ "$output" == *"No entry found for ### foo in"* ]]
}
