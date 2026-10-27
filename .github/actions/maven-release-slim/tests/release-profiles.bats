setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
    : > "$GITHUB_OUTPUT"

    export RELEASE_PROFILE="release"
    export PRERELEASE_PROFILE="prerelease"
    export PRERELEASE_MARKER="-A."

    # Stub mvn printing help:all-profiles output for the profiles in POM_PROFILES
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/mvn" <<'STUB'
#!/bin/bash
for p in $POM_PROFILES; do
  echo "  Profile Id: $p (Active: false, Source: pom)"
done
STUB
    chmod +x "$BATS_TEST_TMPDIR/bin/mvn"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"
    export POM_PROFILES="release prerelease"
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

@test "fails a prerelease when the pom does not define the prerelease profile" {
    export RELEASE_VERSION="5.10.0-A.3"
    export POM_PROFILES="release prerelease-other"

    run release-profiles.sh

    [ "$status" -ne 0 ]
    [[ "$output" == *"prerelease profile 'prerelease' is not defined in the pom"* ]]
}
