setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    SCRIPT="$DIR/../github-pr-label-from-branch.sh"

    WORK_DIR="$(mktemp -d)"
    export GITHUB_OUTPUT="$WORK_DIR/output"
    export GITHUB_EVENT_PATH="$WORK_DIR/event.json"
    export GITHUB_EVENT_NAME=pull_request
    export GITHUB_REPOSITORY=Alfresco/example
    export GH_CALLS="$WORK_DIR/gh-calls"
    export GH_LABELS_BODY="$WORK_DIR/gh-labels-body"
    export REPO_LABELS=$'bug\nenhancement\ndocumentation'
    export MAPPING=$'feature/: enhancement\nimprovement/: enhancement\nfix/: bug'
    : > "$GITHUB_OUTPUT"
    : > "$GH_CALLS"
    unset GH_FAIL

    # Stub gh: lists REPO_LABELS and records the body of the add labels call
    mkdir -p "$WORK_DIR/bin"
    cat > "$WORK_DIR/bin/gh" <<'EOF'
#!/bin/bash
echo "$*" >> "$GH_CALLS"
if [ -n "$GH_FAIL" ]; then
    exit 1
fi
if [[ "$*" == *"--method POST"* ]]; then
    cat > "$GH_LABELS_BODY"
else
    printf '%s\n' "$REPO_LABELS"
fi
EOF
    chmod +x "$WORK_DIR/bin/gh"
    export PATH="$WORK_DIR/bin:$PATH"

    write_event "feature/AAE-123-new-thing"
}

teardown() {
    rm -rf "$WORK_DIR"
}

write_event() {
    local branch=$1
    local head_repo=${2:-$GITHUB_REPOSITORY}
    local author=${3:-someone}
    jq -n --arg branch "$branch" --arg repo "$head_repo" --arg author "$author" \
        '{pull_request: {number: 42, head: {ref: $branch, repo: {full_name: $repo}}, user: {login: $author}}}' \
        > "$GITHUB_EVENT_PATH"
}

applied_labels() {
    jq -c '.labels' "$GH_LABELS_BODY"
}

@test "labels a feature branch as enhancement" {
    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(applied_labels)" = '["enhancement"]' ]
    grep -q "issues/42/labels" "$GH_CALLS"
    grep -qx 'labels=\["enhancement"\]' "$GITHUB_OUTPUT"
}

@test "labels an improvement branch as enhancement" {
    write_event "improvement/AAE-123-better"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(applied_labels)" = '["enhancement"]' ]
}

@test "labels a fix branch as bug" {
    write_event "fix/AAE-123-broken"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(applied_labels)" = '["bug"]' ]
}

@test "does not label an unmapped branch" {
    write_event "chore/AAE-123-cleanup"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
    grep -qx 'labels=\[\]' "$GITHUB_OUTPUT"
}

@test "matches prefixes case-sensitively" {
    write_event "Feature/AAE-123-new-thing"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}

@test "uses a custom mapping with several labels per prefix" {
    export MAPPING=$'# release notes\nbug/: bug\n  docs/ : documentation  \ndocs/: enhancement\n'
    write_event "docs/AAE-123-readme"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(applied_labels)" = '["documentation","enhancement"]' ]
}

@test "applies a label once when several prefixes map to it" {
    export MAPPING=$'feature/: enhancement\nfeature/AAE-: Enhancement'

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ "$(applied_labels)" = '["enhancement"]' ]
}

@test "warns and skips labels missing from the repository" {
    export REPO_LABELS=bug

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"::warning::Label 'enhancement' does not exist"* ]]
    [ ! -e "$GH_LABELS_BODY" ]
    grep -qx 'labels=\[\]' "$GITHUB_OUTPUT"
}

@test "skips pull requests from forks" {
    write_event "feature/AAE-123-new-thing" "someone/example"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Skipping pull request from fork"* ]]
    [ ! -s "$GH_CALLS" ]
}

@test "skips Dependabot pull requests" {
    write_event "fix/dependabot-like" "$GITHUB_REPOSITORY" "dependabot[bot]"

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -s "$GH_CALLS" ]
}

@test "does not execute a branch name containing shell syntax" {
    write_event 'feature/$(touch pwned)`touch pwned2`'

    run "$SCRIPT"

    [ "$status" -eq 0 ]
    [ ! -e pwned ]
    [ ! -e pwned2 ]
    [ "$(applied_labels)" = '["enhancement"]' ]
}

@test "fails on an invalid mapping line" {
    export MAPPING=$'feature/: enhancement\nfix/ bug'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid mapping on line 2"* ]]
}

@test "fails on a mapping entry without label" {
    export MAPPING='feature/:'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"prefix and label are required"* ]]
}

@test "fails on an empty mapping" {
    export MAPPING=$'# nothing\n'

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"The mapping is empty"* ]]
}

@test "fails on a mapping error even for pull requests that would be skipped" {
    export MAPPING='nonsense'
    write_event "feature/AAE-123-new-thing" "someone/example"

    run "$SCRIPT"

    [ "$status" -ne 0 ]
}

@test "fails outside of pull_request events" {
    export GITHUB_EVENT_NAME=pull_request_target

    run "$SCRIPT"

    [ "$status" -ne 0 ]
    [[ "$output" == *"only supports the pull_request event"* ]]
}

@test "fails when the labels cannot be applied" {
    export GH_FAIL=1

    run "$SCRIPT"

    [ "$status" -ne 0 ]
}
