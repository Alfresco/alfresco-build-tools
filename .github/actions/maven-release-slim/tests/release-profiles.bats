setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
    : > "$GITHUB_OUTPUT"

    export RELEASE_PROFILE="release"
    export PRERELEASE_PROFILE="prerelease"
    export PRERELEASE_MARKER="-A."
}

assert_profiles() {
    local expected="$1" actual
    actual=$(grep "^profiles=" "$GITHUB_OUTPUT" | cut -d= -f2-)
    [ "$actual" = "$expected" ] || { echo "Expected profiles=${expected}, got profiles=${actual}" >&2; return 1; }
}

@test "adds the prerelease profile for a prerelease version" {
    export RELEASE_VERSION="5.10.0-A.3"

    run release-profiles.sh

    [ "$status" -eq 0 ]
    assert_profiles "release,prerelease"
}

@test "uses only the release profile for a GA version" {
    export RELEASE_VERSION="5.10.0"

    run release-profiles.sh

    [ "$status" -eq 0 ]
    assert_profiles "release"
}

@test "uses only the release profile when no prerelease profile is set" {
    export RELEASE_VERSION="5.10.0-A.3"
    export PRERELEASE_PROFILE=""

    run release-profiles.sh

    [ "$status" -eq 0 ]
    assert_profiles "release"
}

@test "honours a custom prerelease marker" {
    export RELEASE_VERSION="2.0.0-RC1"
    export PRERELEASE_MARKER="-RC"

    run release-profiles.sh

    [ "$status" -eq 0 ]
    assert_profiles "release,prerelease"
}
