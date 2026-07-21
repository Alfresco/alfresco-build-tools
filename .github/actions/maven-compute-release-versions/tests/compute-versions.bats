setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TMPDIR/github_output_${RANDOM}"
    > "$GITHUB_OUTPUT"

    mvn() {
        echo "${MOCK_POM_VERSION}"
    }
    export -f mvn
}

teardown() {
    rm -f "$GITHUB_OUTPUT"
}

assert_output_var() {
    local key="$1" expected="$2"
    local actual
    actual=$(grep "^${key}=" "$GITHUB_OUTPUT" | cut -d= -f2-)
    [ "$actual" = "$expected" ] || { echo "Expected ${key}=${expected}, got ${key}=${actual}" >&2; return 1; }
}

@test "standard three-part SNAPSHOT version" {
    export MOCK_POM_VERSION="26.2.0-SNAPSHOT"
    run compute-versions.sh
    [ "$status" -eq 0 ]
    assert_output_var "release-version"     "26.2.0"
    assert_output_var "next-development-version" "26.2.1-SNAPSHOT"
}

@test "patch rollover from 9 to 10" {
    export MOCK_POM_VERSION="1.2.9-SNAPSHOT"
    run compute-versions.sh
    [ "$status" -eq 0 ]
    assert_output_var "release-version"     "1.2.9"
    assert_output_var "next-development-version" "1.2.10-SNAPSHOT"
}

@test "patch rollover from 99 to 100" {
    export MOCK_POM_VERSION="3.0.99-SNAPSHOT"
    run compute-versions.sh
    [ "$status" -eq 0 ]
    assert_output_var "release-version"     "3.0.99"
    assert_output_var "next-development-version" "3.0.100-SNAPSHOT"
}

@test "patch zero is incremented to one" {
    export MOCK_POM_VERSION="1.0.0-SNAPSHOT"
    run compute-versions.sh
    [ "$status" -eq 0 ]
    assert_output_var "release-version"     "1.0.0"
    assert_output_var "next-development-version" "1.0.1-SNAPSHOT"
}

@test "fails when mvn exits non-zero" {
    mvn() { return 1; }
    export -f mvn
    run compute-versions.sh
    [ "$status" -ne 0 ]
}

@test "non-SNAPSHOT input is used as-is for release version" {
    export MOCK_POM_VERSION="2.5.3"
    run compute-versions.sh
    [ "$status" -eq 0 ]
    assert_output_var "release-version"     "2.5.3"
    assert_output_var "next-development-version" "2.5.4-SNAPSHOT"
}
