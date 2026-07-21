setup() {
    DIR="$( cd "$( dirname "$BATS_TEST_FILENAME" )" >/dev/null 2>&1 && pwd )"
    PATH="$DIR/..:$PATH"

    export GITHUB_ENV="$BATS_TEST_TMPDIR/github_env"
    : > "$GITHUB_ENV"
    export IGNORE_REGEX='^$'
}

@test "simple value is written" {
    export YML_PATH="$DIR/simple.yml"
    run env-load-from-yaml.sh
    [ "$status" -eq 0 ]
    grep -qx 'APP_SETTING_ONE=value' "$GITHUB_ENV"
}

@test "ignore_regex skips matching lines" {
    export YML_PATH="$DIR/simple.yml"
    export IGNORE_REGEX='^TRAVIS_BRANCH=.*'
    run env-load-from-yaml.sh
    [ "$status" -eq 0 ]
    grep -qx 'APP_SETTING_ONE=value' "$GITHUB_ENV"
    ! grep -q '^TRAVIS_BRANCH=' "$GITHUB_ENV"
}

@test "single-line variable reference is expanded" {
    export YML_PATH="$DIR/expansion.yml"
    export ANOTHER_VAR="expanded-value"
    export SOURCE_MULTILINE="ignored-here"
    run env-load-from-yaml.sh
    [ "$status" -eq 0 ]
    grep -qx 'VAR2=expanded-value' "$GITHUB_ENV"
}

@test "multiline value uses heredoc and round-trips" {
    export YML_PATH="$DIR/expansion.yml"
    export ANOTHER_VAR="whatever"
    export SOURCE_MULTILINE=$'-----BEGIN RSA PRIVATE KEY-----\nline one\nline two\n-----END RSA PRIVATE KEY-----'
    run env-load-from-yaml.sh
    [ "$status" -eq 0 ]

    grep -q '^PEM<<EOF_' "$GITHUB_ENV"
    grep -qx -- '-----BEGIN RSA PRIVATE KEY-----' "$GITHUB_ENV"
    grep -qx -- '-----END RSA PRIVATE KEY-----' "$GITHUB_ENV"

    # the value between the heredoc delimiters must round-trip in full,
    # parsing the file the way GitHub Actions consumes $GITHUB_ENV
    delimiter="$(sed -n 's/^PEM<<//p' "$GITHUB_ENV")"
    extracted="$(awk -v d="$delimiter" '
        $0 == "PEM<<" d { capture = 1; next }
        capture && $0 == d { capture = 0; next }
        capture { print }
    ' "$GITHUB_ENV")"
    [ "$extracted" = "$SOURCE_MULTILINE" ]
}
