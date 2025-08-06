#!/usr/bin/env bats

setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    REPO_ROOT="$DIR/mockrepo"
    mkdir -p "$REPO_ROOT/.github/actions/action1"
    mkdir -p "$REPO_ROOT/.github/actions/action2"
    touch "$REPO_ROOT/.github/actions/action1/action.yml"
    touch "$REPO_ROOT/.github/actions/action2/action.yml"
    cd "$REPO_ROOT"
    git init >/dev/null 2>&1
}

teardown() {
    rm -rf "$REPO_ROOT"
}

@test "all actions listed in dependabot.yml (single directory)" {
    cat > .github/dependabot.yml <<EOF
updates:
  - package-ecosystem: github-actions
    directory: .github/actions/action1
  - package-ecosystem: github-actions
    directory: .github/actions/action2
EOF
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing"* ]]
}

@test "missing action in dependabot.yml (single directory)" {
    cat > .github/dependabot.yml <<EOF
updates:
  - package-ecosystem: github-actions
    directory: .github/actions/action1
EOF
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"action2"* ]]
}

@test "all actions listed in dependabot.yml (directories array)" {
    cat > .github/dependabot.yml <<EOF
updates:
  - package-ecosystem: github-actions
    directories:
      - .github/actions/action1
      - .github/actions/action2
EOF
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *"missing"* ]]
}

@test "missing action in dependabot.yml (directories array)" {
    cat > .github/dependabot.yml <<EOF
updates:
  - package-ecosystem: github-actions
    directories:
      - .github/actions/action1
EOF
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *"action2"* ]]
}

@test "no .github/actions directory" {
    rm -rf .github/actions
    cat > .github/dependabot.yml <<EOF
updates:
  - package-ecosystem: github-actions
    directory: .github/actions/action1
EOF
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *".github/actions directory not found"* ]]
}

@test "no .github/dependabot.yml file" {
    rm -f .github/dependabot.yml
    run "$DIR/../dependabot-coverage-check.sh"
    [ "$status" -eq 1 ]
    [[ "$output" == *".github/dependabot.yml file not found"* ]]
}
