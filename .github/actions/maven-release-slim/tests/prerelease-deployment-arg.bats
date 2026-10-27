setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
    : > "$GITHUB_OUTPUT"

    export PRERELEASE_REPOSITORY="alfresco-releases::https://example.test/internal-releases/maven/"
    export PRERELEASE_MARKER="-A."
}

assert_maven_arg() {
    local expected="$1" actual
    actual=$(grep "^maven-arg=" "$GITHUB_OUTPUT" | cut -d= -f2-)
    [ "$actual" = "$expected" ] || { echo "Expected maven-arg=${expected}, got maven-arg=${actual}" >&2; return 1; }
}

@test "redirects a prerelease version to the prerelease repository" {
    export RELEASE_VERSION="5.10.0-A.3"

    run prerelease-deployment-arg.sh

    [ "$status" -eq 0 ]
    assert_maven_arg "-DaltReleaseDeploymentRepository=$PRERELEASE_REPOSITORY"
}

@test "keeps a GA version on the default repository" {
    export RELEASE_VERSION="5.10.0"

    run prerelease-deployment-arg.sh

    [ "$status" -eq 0 ]
    assert_maven_arg ""
}

@test "keeps a prerelease version on the default repository when no prerelease repository is set" {
    export RELEASE_VERSION="5.10.0-A.3"
    export PRERELEASE_REPOSITORY=""

    run prerelease-deployment-arg.sh

    [ "$status" -eq 0 ]
    assert_maven_arg ""
}

@test "honours a custom prerelease marker" {
    export RELEASE_VERSION="2.0.0-RC1"
    export PRERELEASE_MARKER="-RC"

    run prerelease-deployment-arg.sh

    [ "$status" -eq 0 ]
    assert_maven_arg "-DaltReleaseDeploymentRepository=$PRERELEASE_REPOSITORY"
}
