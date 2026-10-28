setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    cd "$BATS_TEST_TMPDIR"
}

@test "installs the repository settings file" {
    echo '<settings><!-- repo --></settings>' > .ci.settings.xml
    export MAVEN_SETTINGS=".ci.settings.xml"

    run install-settings.sh

    [ "$status" -eq 0 ]
    cmp .ci.settings.xml "$HOME/.m2/settings.xml"
}

@test "installs nothing when the repository has no settings file" {
    export MAVEN_SETTINGS=".ci.settings.xml"

    run install-settings.sh

    [ "$status" -eq 0 ]
    [ ! -e "$HOME/.m2/settings.xml" ]
}
