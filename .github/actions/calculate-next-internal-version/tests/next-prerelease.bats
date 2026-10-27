setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    export REPO_DIR="$BATS_TEST_TMPDIR/repo"
    export GITHUB_OUTPUT="$BATS_TEST_TMPDIR/github_output"
    export NEXT_VERSION="7.21.0"
    export PRERELEASE_TYPE="alpha"
    > "$GITHUB_OUTPUT"

    git init --quiet "$REPO_DIR"
    git -C "$REPO_DIR" config user.name "Test"
    git -C "$REPO_DIR" config user.email "test@example.com"
    git -C "$REPO_DIR" -c commit.gpgsign=false commit --quiet --allow-empty -m "Initial commit"

    pysemver() {
        [ "$1" = "bump" ] && [ "$2" = "prerelease" ] || return 1
        local version="$3"
        echo "${version%.*}.$((${version##*.} + 1))"
    }
    export -f pysemver
}

@test "highest prerelease wins even when a lower tag has a newer timestamp" {
    GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" \
        git -C "$REPO_DIR" -c tag.gpgsign=false tag -a "7.21.0-alpha.836" -m "Higher version"
    GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" \
        git -C "$REPO_DIR" -c tag.gpgsign=false tag -a "7.21.0-alpha.835" -m "Newer timestamp"

    [ "$(git -C "$REPO_DIR" tag --sort=-creatordate | head -n 1)" = "7.21.0-alpha.835" ]

    run bash "$DIR/../next-prerelease.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"Latest prerelease version found: 7.21.0-alpha.836"* ]]
    [[ "$output" == *"Next prerelease: 7.21.0-alpha.837"* ]]
    [ "$(cat "$GITHUB_OUTPUT")" = $'latest-prerelease=7.21.0-alpha.836\nnext-prerelease=7.21.0-alpha.837' ]
}

@test "prerelease numbers are ordered numerically rather than lexically" {
    git -C "$REPO_DIR" tag "7.21.0-alpha.9"
    git -C "$REPO_DIR" tag "7.21.0-alpha.10"

    run bash "$DIR/../next-prerelease.sh"

    [ "$status" -eq 0 ]
    [ "$(cat "$GITHUB_OUTPUT")" = $'latest-prerelease=7.21.0-alpha.10\nnext-prerelease=7.21.0-alpha.11' ]
}

@test "first prerelease is created when there are no tags" {
    run bash "$DIR/../next-prerelease.sh"

    [ "$status" -eq 0 ]
    [[ "$output" == *"No prerelease found for version 7.21.0 yet"* ]]
    [ "$(cat "$GITHUB_OUTPUT")" = "next-prerelease=7.21.0-alpha.1" ]
}

@test "tags for other base versions and prerelease types are ignored" {
    git -C "$REPO_DIR" tag "7.22.0-alpha.999"
    git -C "$REPO_DIR" tag "7.21.0-beta.999"
    git -C "$REPO_DIR" tag "7.21.0"

    run bash "$DIR/../next-prerelease.sh"

    [ "$status" -eq 0 ]
    [ "$(cat "$GITHUB_OUTPUT")" = "next-prerelease=7.21.0-alpha.1" ]
}
