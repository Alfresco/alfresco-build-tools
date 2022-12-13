setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_ENV=/dev/null
    export GITHUB_HEAD_REF="OPSEXP-1234"

    # Mock git-latest-tag defaults
    export PATTERN="*"
    export REPO_DIR="$PWD"
}

@test "latest tag" {
    latest_tag=$(git tag --sort=-creatordate | head -n 1)
    tag_sha=$(git rev-list -n 1 $(git tag --sort=-creatordate | head -n 1))
    run git-latest-tag.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Latest tag for the pattern $PATTERN is $latest_tag ($tag_sha)" ]
}
