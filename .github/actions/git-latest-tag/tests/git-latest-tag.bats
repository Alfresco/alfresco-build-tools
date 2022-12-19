setup() {
    git fetch --tags

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
    regex="v[0-9]+\.[0-9]+\.[0-9]+"
    run git-latest-tag.sh
    [ "$status" -eq 0 ]
    if [[ ! $output =~ $regex ]]; then
        echo "Output does not match regex: $regex"
        exit 1
    fi
}

@test "tag_v1.0.0" {
    export PATTERN="v1.0.0"
    export REPO_DIR="$PWD"
    tag="v1.0.0"
    tag_sha="93891a5cfd55868bdfbd145ed8016ea8c63e37be"
    run git-latest-tag.sh

    [ "$status" -eq 0 ]
    [ "$output" = "Tag for the pattern $PATTERN is $tag ($tag_sha)" ]
}
