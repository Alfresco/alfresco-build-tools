setup() {
    # Runs everywhere
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    # Mock GitHub Actions default variables
    export GITHUB_ENV=/dev/null
    export GITHUB_HEAD_REF="AAE-11760-get-latest-tag-sha"

    # Mock git-latest-tag defaults
    export PATTERN="*"
    export REPO_DIR="$PWD"
}

@test "latest_tag" {
    git fetch --tags
    latest_tag=$(git tag --sort=-creatordate | head -n 1)
    echo latest_tag=$latest_tag
    tag_sha=$(git rev-list -n 1 $latest_tag)
    run git-latest-tag.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Latest tag for the pattern $PATTERN is $latest_tag ($tag_sha)" ]
}
