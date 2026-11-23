#!/usr/bin/env bats

bats_require_minimum_version 1.5.0

LIBS=(bats-support bats-assert bats-file)

setup() {
    SCRIPT="$BATS_TEST_DIRNAME/../../scripts/install-bats-libs.sh"
    TMP="$(mktemp -d)"
    DEST="$TMP/dest"
    VERSIONS="$TMP/versions.yml"
    export HOME="$TMP/home"
    mkdir -p "$HOME" "$TMP/bin" "$TMP/tarballs"

    cat > "$VERSIONS" <<YAML
# comment
bats_support: 1.0.0
bats_assert: "2.0.0"
bats_file: 3.0.0
YAML

    for lib in "${LIBS[@]}"; do
        src="$TMP/src/bats-core-$lib-abc123"
        mkdir -p "$src/src" "$src/test"
        echo "load $lib" > "$src/load.bash"
        echo "impl $lib" > "$src/src/$lib.bash"
        echo "readme" > "$src/README.md"
        echo "test" > "$src/test/t.bats"
        tar -czf "$TMP/tarballs/$lib.tar.gz" -C "$TMP/src" "bats-core-$lib-abc123"
    done

    # Fake curl: logs the URL and serves the fixture tarball for that lib
    cat > "$TMP/bin/curl" <<'CURL'
#!/bin/bash
url="${*: -1}"
echo "$url" >> "$CURL_LOG"
[[ -n "${CURL_FAIL:-}" ]] && exit 22
lib="$(sed -E 's#.*/bats-core/([^/]+)/.*#\1#' <<< "$url")"
cat "$TARBALLS/$lib.tar.gz"
CURL
    chmod +x "$TMP/bin/curl"
    export CURL_LOG="$TMP/curl.log"
    export TARBALLS="$TMP/tarballs"
    : > "$CURL_LOG"
    export PATH="$TMP/bin:$PATH"
}

teardown() {
    rm -rf "$TMP"
}

@test "installs the three libraries with load.bash and src" {
    run "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ "$status" -eq 0 ]
    for lib in "${LIBS[@]}"; do
        [ -f "$DEST/$lib/load.bash" ]
        [ -f "$DEST/$lib/src/$lib.bash" ]
    done
}

@test "does not copy anything besides load.bash and src" {
    "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ ! -e "$DEST/bats-assert/README.md" ]
    [ ! -e "$DEST/bats-assert/test" ]
}

@test "downloads the release tag pinned in the versions file" {
    "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    grep -q 'bats-core/bats-support/.*v1\.0\.0' "$CURL_LOG"
    grep -q 'bats-core/bats-assert/.*v2\.0\.0' "$CURL_LOG"
    grep -q 'bats-core/bats-file/.*v3\.0\.0' "$CURL_LOG"
}

@test "prints only the BATS_LIB_PATH export on stdout" {
    run --separate-stderr "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ "$status" -eq 0 ]
    [ "$output" = "export BATS_LIB_PATH=\"$DEST\"" ]
}

@test "defaults the destination to ~/.local/lib/bats" {
    "$SCRIPT" --versions-file "$VERSIONS"

    [ -f "$HOME/.local/lib/bats/bats-assert/load.bash" ]
}

@test "skips the download when the pinned version is already installed" {
    "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"
    : > "$CURL_LOG"

    run "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ "$status" -eq 0 ]
    [ ! -s "$CURL_LOG" ]
}

@test "replaces a library installed at another version" {
    "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"
    echo stale > "$DEST/bats-assert/src/stale.bash"
    sed 's/"2.0.0"/"2.1.0"/' "$VERSIONS" > "$VERSIONS.new" && mv "$VERSIONS.new" "$VERSIONS"

    "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    grep -q 'v2\.1\.0' "$CURL_LOG"
    [ ! -e "$DEST/bats-assert/src/stale.bash" ]
    [ -f "$DEST/bats-assert/load.bash" ]
}

@test "fails when the versions file lacks a library" {
    grep -v bats_file "$VERSIONS" > "$VERSIONS.new" && mv "$VERSIONS.new" "$VERSIONS"

    run "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ "$status" -ne 0 ]
    [[ "$output" == *"bats_file"* ]]
    [ ! -s "$CURL_LOG" ]
}

@test "fails and installs nothing for the library when the download fails" {
    CURL_FAIL=1 run "$SCRIPT" --dest "$DEST" --versions-file "$VERSIONS"

    [ "$status" -ne 0 ]
    [ ! -e "$DEST/bats-support/load.bash" ]
}

@test "rejects unknown options" {
    run "$SCRIPT" --bogus

    [ "$status" -ne 0 ]
    [[ "$output" == *"Usage:"* ]]
}

@test "the repository versions file pins all three libraries" {
    run "$SCRIPT" --dest "$DEST" --versions-file "$BATS_TEST_DIRNAME/../bats-libs.yml"

    [ "$status" -eq 0 ]
    grep -q 'bats-core/bats-support/.*v[0-9]' "$CURL_LOG"
    grep -q 'bats-core/bats-assert/.*v[0-9]' "$CURL_LOG"
    grep -q 'bats-core/bats-file/.*v[0-9]' "$CURL_LOG"
}
